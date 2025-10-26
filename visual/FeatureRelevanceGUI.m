function FeatureRelevanceGUI
% FeatureRelevanceGUI - MATLAB GUI to configure and plot feature relevance

% Create UIFigure and Layout
gui.F = uifigure('Name','Feature Relevance Plotter');
centerFigure(gui.F, 2/4, 3/4);
gl = uigridlayout(gui.F, [6,1]);
gl.RowHeight    = {70,'1x','fit','fit','fit','fit'};
gl.ColumnWidth = {'1x'};

% Initialize per-file ImportParams list
gui.ImportParamsList = {};

% Per-sheet domain names (single-table mode)
gui.domainMap     = containers.Map('KeyType','char','ValueType','char'); % per-sheet domains
gui.lastSheetRow  = [];   % currently selected row in the table

%% Mode Selection Panel
gui.modePanel = uipanel(gl,'Title','Import Mode');
modeG = uibuttongroup(gui.modePanel,'Position',[10 10 470 30],... 
    'SelectionChangedFcn',@modeChanged);
gui.rbMultiTables = uiradiobutton(modeG,'Text','Multiple Tables → One Sheet','Position',[10 5 300 20],'Value',true);
gui.rbMultiSheets = uiradiobutton(modeG,'Text','One Table → Multiple Sheets','Position',[250 5 250 20]);
gui.modePanel.Layout.Row = 1;

%% Import Parameters Panel
gui.impPanel = uipanel(gl,'Title','Import Parameters', 'Scrollable','on');
impGrid = uigridlayout(gui.impPanel,[6 4]);
impGrid.RowHeight    = {22,22,22,30,30,'1x','fit'};
impGrid.ColumnWidth = {'1x','1x',80,80};
applyImportGridLayout(); 

% File list
gui.fileList = uilistbox(impGrid,'Items',{'No table selected'},... 
    'Multiselect','on','ValueChangedFcn',@fileSelectionChanged);
gui.fileList.Layout.Row    = [1 3];
gui.fileList.Layout.Column = [1 3];

% Add File button
gui.addBtn = uibutton(impGrid,'Text','Add File...','ButtonPushedFcn',@addFile);
gui.addBtn.Layout.Row    = 1;
gui.addBtn.Layout.Column = 4;

% Replace File button  
gui.replaceBtn = uibutton(impGrid, ...
    'Text','Replace File...', ...
    'ButtonPushedFcn',@replaceFile);
gui.replaceBtn.Layout.Row    = 2;   
gui.replaceBtn.Layout.Column = 4;

% Remove File button
gui.removeBtn = uibutton(impGrid, ...
  'Text','Remove File', ...
  'ButtonPushedFcn',@removeFile);
gui.removeBtn.Layout.Row    = 3;
gui.removeBtn.Layout.Column = 4;

% --- Sheet dropdown wrapper (so it never stretches vertically) ---
gui.sheetPanel = uipanel(impGrid,'Title','', 'BorderType','none');
gui.sheetPanel.Layout.Row    = 4 ;        % row 4 only
gui.sheetPanel.Layout.Column = [1 3];

sheetGrid = uigridlayout(gui.sheetPanel,[1 1]);
sheetGrid.RowHeight   = {'fit'};         % keep control height natural
sheetGrid.ColumnWidth = {'1x'};
sheetGrid.Padding     = [0 0 0 0];
sheetGrid.RowSpacing  = 0;

% --- Arrow panel (spans rows 4–5, keeps buttons a constant height) ---
gui.arrowPanel = uipanel(impGrid, 'Title','', 'BorderType','none');
gui.arrowPanel.Layout.Row    = [4 5];
gui.arrowPanel.Layout.Column = 4;

arrowGrid = uigridlayout(gui.arrowPanel, [3 1]);
arrowGrid.RowHeight   = {'fit','fit','1x'};   % two fixed-height rows + filler
arrowGrid.ColumnWidth = {'1x'};
arrowGrid.RowSpacing  = 6;
arrowGrid.Padding     = [6 6 6 6];

% Sheet controls
gui.sheetDropdown = uidropdown(sheetGrid,'Items',{},'ValueChangedFcn',@saveImportParams);
gui.sheetDropdown.Layout.Row    = 1;
gui.sheetDropdown.Layout.Column = 1;

gui.sheetTable = uitable(impGrid, ...
  'Data', table(false(0,1), strings(0,1), strings(0,1), ...
                'VariableNames', {'Use','Sheet','Domain'}), ...
  'ColumnName',     {'Use','Sheet','Domain'}, ...
  'ColumnEditable', [true  false  true], ...
  'ColumnWidth',    {50, '1x', 160}, ...
  'Visible', false, ...
  'CellEditCallback',     @sheetTableEdited, ...
  'CellSelectionCallback',@sheetTableSelected);
gui.sheetTable.Layout.Row    = [4 5];        % single-table mode
gui.sheetTable.Layout.Column = [1 3];

% Move Up
gui.upBtn = uibutton(arrowGrid, ...
    'Text','↑', ...
    'Tooltip','Move selected item up', ...
    'ButtonPushedFcn', @moveUp);
gui.upBtn.Layout.Row = 1; gui.upBtn.Layout.Column = 1;

% Move Down
gui.downBtn = uibutton(arrowGrid, ...
    'Text','↓', ...
    'Tooltip','Move selected item down', ...
    'ButtonPushedFcn', @moveDown);
gui.downBtn.Layout.Row = 2; gui.downBtn.Layout.Column = 1;

% Feature/Score/Domain (add labels above the dropdowns)
featGrid = uigridlayout(impGrid,[2 3]);
featGrid.RowHeight    = {'fit','fit'};
featGrid.ColumnWidth  = {'1x','1x','1x'};
featGrid.Layout.Row    = 6;
featGrid.Layout.Column = [1 4];

% Row 1: labels  (create then place)
lblFeat = uilabel(featGrid, ...
    'Text','Feature column', ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');
lblFeat.Layout.Row = 1; lblFeat.Layout.Column = 1;

lblScore = uilabel(featGrid, ...
    'Text','Score column', ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');
lblScore.Layout.Row = 1; lblScore.Layout.Column = 2;

lblDomain = uilabel(featGrid, ...
    'Text','Modality / domain name', ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');
lblDomain.Layout.Row = 1; lblDomain.Layout.Column = 3;

% Row 2: controls (unchanged handles so the rest of your code still works)
gui.featColDropdown  = uidropdown(featGrid,'Items',{}, ...
    'Placeholder','Feature Column Name','ValueChangedFcn',@saveImportParams);
gui.featColDropdown.Layout.Row = 2; 
gui.featColDropdown.Layout.Column = 1;

gui.scoreColDropdown = uidropdown(featGrid,'Items',{}, ...
    'Placeholder','Score Column Name','ValueChangedFcn',@saveImportParams);
gui.scoreColDropdown.Layout.Row = 2; 
gui.scoreColDropdown.Layout.Column = 2;

gui.domainField = uieditfield(featGrid,'text','Value','Modality name', ...
    'Placeholder','Modality Name','ValueChangedFcn',@saveImportParams);
gui.domainField.Tooltip = 'Domain name for the selected sheet (first if multiple are selected)';
gui.domainField.Layout.Row = 2; 
gui.domainField.Layout.Column = 3;

%% Domain & Class Names Panel
gui.dcPanel = uipanel(gl,'Title','Expression Direction Names (names for positive and negative values)');
dcGrid = uigridlayout(gui.dcPanel,[1 1]);
dcGrid.RowHeight = {'fit'};
gui.classesField = uieditfield(dcGrid,'text','Value','Pos,Neg','Placeholder','Class Names');
gui.dcPanel.Layout.Row = 3;

%% Plot Parameters Panel
gui.plotPanel = uipanel(gl,'Title','Plot Parameters');
plotGrid = uigridlayout(gui.plotPanel,[4 4]);
plotGrid.RowHeight    = {15,'fit',15,'fit'};
plotGrid.ColumnWidth = {'1x','1x','1x','1x'}; 
gui.lbCbrangeField= uilabel(plotGrid,"Text","Colorbar min & max"); 
gui.lbCbrangeField.Layout.Row=1; gui.lbCbrangeField.Layout.Column=1;
gui.cbrangeField  = uieditfield(plotGrid,'text','Value','[-20 20]','Placeholder','Colorbar Range');
gui.cbrangeField.Layout.Row=2; gui.cbrangeField.Layout.Column=1;

gui.lbRgbPosField= uilabel(plotGrid,"Text","Positive range color"); 
gui.lbRgbPosField.Layout.Row=1; gui.lbRgbPosField.Layout.Column=2;

gui.lbRgbNegField= uilabel(plotGrid,"Text","Negative range color"); 
gui.lbRgbNegField.Layout.Row=1; gui.lbRgbNegField.Layout.Column=3;

gui.lbBackField= uilabel(plotGrid,"Text","Background plot color"); 
gui.lbBackField.Layout.Row=1; gui.lbBackField.Layout.Column=4;

% Positive‑range colour
posCell = uigridlayout(plotGrid,[1 2],'RowHeight',{'fit'});
posCell.Layout.Row = 2; posCell.Layout.Column = 2;
[gui.rgbPosField,gui.posChip] = addColorChooser( ...
        posCell,'Crimson','Positive Colour',@pickColour);

% Negative‑range colour
negCell = uigridlayout(plotGrid,[1 2],'RowHeight',{'fit'});
negCell.Layout.Row = 2; negCell.Layout.Column = 3;
[gui.rgbNegField,gui.negChip] = addColorChooser( ...
        negCell,'DarkBlue','Negative Colour',@pickColour);

% Background colour
backCell = uigridlayout(plotGrid,[1 2],'RowHeight',{'fit'});
backCell.Layout.Row = 2; backCell.Layout.Column = 4;
[gui.rgbBackField,gui.backChip] = addColorChooser( ...
        backCell,'WhiteSmoke','Background Colour',@pickColour);

gui.lbSortByField= uilabel(plotGrid,"Text","Sort mode"); 
gui.lbSortByField.Layout.Row=3; gui.lbSortByField.Layout.Column=1;
gui.sortByField   = uidropdown(plotGrid,'Items',{'absolute','original'},'Value','absolute'); 
gui.sortByField.Layout.Row=4; gui.sortByField.Layout.Column=1;

gui.lbOrderField= uilabel(plotGrid,"Text","Sort direction"); 
gui.lbOrderField.Layout.Row=3; gui.lbOrderField.Layout.Column=2;
gui.orderField    = uidropdown(plotGrid,'Items',{'ascending','descending'},'Value','ascending'); 
gui.orderField.Layout.Row=4; gui.orderField.Layout.Column=2;

gui.lbHoldField= uilabel(plotGrid,"Text","Hold-out cutoff/range"); 
gui.lbHoldField.Layout.Row=3; gui.lbHoldField.Layout.Column=3;
gui.holdoutRange   = uieditfield(plotGrid,'text','Value','[0 0]','Placeholder','Hold-out cutoff');
gui.holdoutRange.Layout.Row=4; gui.holdoutRange.Layout.Column=3;

gui.showColors   = uibutton(plotGrid,'Text','Show colors...','ButtonPushedFcn',@rgbchart);
gui.showColors.Layout.Row = 4;
gui.showColors.Layout.Column = 4;   

%% Export Parameters Panel
gui.expPanel = uipanel(gl,'Title','Export Parameters');
expGrid = uigridlayout(gui.expPanel,[1 3]);
expGrid.RowHeight    = {'fit'};
expGrid.ColumnWidth  = {'1x','1x','1x'};
gui.filenameField = uieditfield(expGrid,'text','Value','MyPlot','Placeholder','Filename Prefix');
gui.resolField    = uieditfield(expGrid,'numeric','Value',300,'Limits',[1 600],'Placeholder','Resolution');
gui.ftypeField    = uidropdown(expGrid,'Items',{'png','pdf','eps'},'Value','png');
gui.expPanel.Layout.Row = 5;

%% Generate Plot Button
gui.runBtn = uibutton(gl,'Text','Generate Plot','BackgroundColor', rgb('SkyBlue'),'FontWeight','bold','ButtonPushedFcn',@runCallback);
gui.runBtn.Layout.Row = 6;
updateAddButtonState()

%% Nested callback functions
function applyImportGridLayout()
    impGrid.RowSpacing = 6;
    impGrid.Padding    = [6 6 6 6];

    if gui.rbMultiTables.Value
        % rows: 1..3 small, row 4 tall (arrows), row 5 small, row 6 'fit'
        impGrid.RowHeight = {22, 22, 22, 70, 22, 'fit'};
        % arrowPanel should span [4 5]; sheetDropdown lives in row 4 (left columns)
    else
        % single-table: big table area (row 4), fixed arrow buffer (row 5)
        impGrid.RowHeight = {22, 22, 22, '1x', 60, 'fit'};
    end
end

function updateAddButtonState()
    if gui.rbMultiTables.Value
        gui.addBtn.Enable = 'on';                % always allowed
    else
        items   = gui.fileList.Items;
        hasFile = ~isempty(items) && ~strcmp(items{1},'No table selected');
        gui.addBtn.Enable = ternary(hasFile,'off','on');
    end
end

function modeChanged(~,event)
    multiline = (event.NewValue == gui.rbMultiTables);

    gui.fileList.Multiselect  = ternary(multiline,'on','off');
    gui.sheetPanel.Visible    = multiline;     % multi-table sheet dropdown panel
    gui.sheetTable.Visible    = ~multiline;    % single-table sheet table

    % domain field behavior
    if multiline
        gui.domainField.Enable = 'on';         % user types domain once (used for all files)
        gui.domainField.Tooltip = 'Domain name used for all files (combined with filename).';
    else
        gui.domainField.Enable = 'off';
        gui.domainField.Tooltip = 'Edit the Domain directly in the table.';
    end

    applyImportGridLayout();
    clearControls();

    if multiline, updateGlobalSelectors();
    else,          fileSelectionChanged();
    end
    updateAddButtonState()
end

function pickColour(edField, chipBtn)
    try
        [cTriplet, cName] = rgb('pick');  % opens modal picker
    catch ME
        uialert(gui.F, "Color picker failed: "+ME.message, 'Picker error');
        bringToFront(gui.F);
        return
    end
    if isempty(cTriplet), bringToFront(gui.F); return; end

    % prefer CSS name in the text field; fallback to hex if empty
    if ~isempty(cName)
        edField.Value = cName;
    else
        edField.Value = sprintf('#%02X%02X%02X', round(cTriplet(1)*255), round(cTriplet(2)*255), round(cTriplet(3)*255));
    end
    chipBtn.BackgroundColor = cTriplet;

    bringToFront(gui.F);
end

    function sheetTableEdited(src, evt)
    if isempty(evt.Indices), return; end
    r = evt.Indices(1); c = evt.Indices(2);
    T = src.Data;

    % normalize logical vector (old MATLAB may return cell)
    if iscell(T.Use), T.Use = cell2mat(T.Use); end

    switch c
        case 1  % Use checkbox toggled
            % Renumber only the default-style domains among SELECTED rows
            mask = logical(T.Use);
            sel  = find(mask);
            k = 1;
            for i = 1:numel(sel)
                rr = sel(i);
                if isDefaultDomain(T.Domain(rr))
                    T.Domain(rr) = {sprintf('domain %d', k)};
                end
                k = k + 1;
            end
            src.Data = T;

        case 3  % Domain edited
            % Trim; if empty and row is selected, assign default based on selected index
            val = strtrim(string(T.Domain(r)));
            if val == ""
                if r <= height(T) && r >= 1
                    if logical(T.Use(r))
                        selIndex = sum(T.Use(1:r)); % position among selected
                        val = sprintf('domain %d', selIndex);
                    else
                        val = sprintf('domain %d', r);
                    end
                else
                    val = "domain 1";
                end
            end
            T.Domain(r) = val;
            src.Data = T;
    end

    enableRunIfValid();
end

function sheetTableSelected(~, evt)
    % optional: mirror the selected row's domain into the side field (read-only)
    if gui.rbMultiTables.Value, return; end
    T = gui.sheetTable.Data;
    if ~istable(T) || height(T)==0, gui.domainField.Value = ''; return; end
    if nargin >= 2 && isfield(evt,'Indices') && ~isempty(evt.Indices)
        gui.lastSheetRow = evt.Indices(1);
    elseif isempty(gui.lastSheetRow)
        gui.lastSheetRow = 1;
    end
    r = min(max(1, gui.lastSheetRow), height(T));
    dom = T.Domain(r);
    if iscell(dom), dom = dom{1}; end
    gui.domainField.Value = char(dom);
end

function populateSheetTable(filePath)
    % get sheet names
    try
        [~,~,ext] = fileparts(filePath);
        if any(strcmpi(ext,{'.xls','.xlsx','.xlsm'}))
            sh = string(sheetnames(filePath));
        else
            sh = "1";
        end
    catch
        sh = "1";
    end

    n  = numel(sh);
    Use    = false(n,1);
    Sheet  = sh(:);
    Domain = strings(n,1);
    for i = 1:n, Domain(i) = sprintf('domain %d', i); end

    gui.sheetTable.Data = table(Use, Sheet, Domain, ...
                                'VariableNames', {'Use','Sheet','Domain'});
    gui.sheetTable.Visible = true;
    gui.lastSheetRow = min(1,n);

    % show the first row’s domain in the side field (disabled in single-table)
    sheetTableSelected();
    enableRunIfValid();
end

function [sheets, domains] = getSelectedSheetsAndDomains()
    T = gui.sheetTable.Data;
    if ~istable(T) || height(T)==0
        sheets = {}; domains = {}; return
    end
    mask = T.Use; if iscell(mask), mask = cell2mat(mask); end

    % normalize to cellstr
    sCol = T.Sheet(mask);
    dCol = T.Domain(mask);
    if isa(sCol,'string'),  sheets  = cellstr(sCol); else, sheets  = sCol; end
    if isa(dCol,'string'),  domains = cellstr(dCol); else, domains = dCol; end

    % fill empties with defaults "domain j" based on selected order
    for j = 1:numel(domains)
        if isempty(strtrim(domains{j}))
            domains{j} = sprintf('domain %d', j);
        end
    end
end

% ------------------------------------------------------------------------
function [ed,chip] = addColorChooser(parent,initName,placeholder,pickFcn)
    % parent    uigridlayout (1×2) that already lives in the main grid
    % initName  initial CSS colour name, e.g. 'Crimson'
    % placeholder text for the edit‑field
    % pickFcn   handle that runs rgb('pick') and updates both widgets

    % column widths: stretch + fixed 22 px
    parent.Padding        = [0 0 0 0];   % no outer margin
    parent.RowSpacing     = 0;           % no vertical gap (1 row anyway)
    parent.ColumnSpacing  = 2;           % tiny gap between field & chip
    parent.ColumnWidth    = {'1x',22};   % stretch + 22‑px chip

    % edit‑field
    ed = uieditfield(parent,'text','Value',initName,'Placeholder',placeholder);
    ed.Layout.Row = 1; ed.Layout.Column = 1;

    % colour chip
    chip = uibutton(parent,'Text',' ', ...
        'BackgroundColor',rgb(initName), ...
        'Tooltip','Pick colour…');
    chip.Layout.Row = 1; chip.Layout.Column = 2;

    % link the button to the picker
    chip.ButtonPushedFcn = @(~,~) pickFcn(ed,chip);
end

function addFile(~,~)
    % Choose one or many based on mode
    multiFlag = ternary(gui.rbMultiTables.Value,'on','off');
    [sel, path] = uigetfile({'*.xlsx;*.xls;*.csv','Tables (*.xlsx, *.xls, *.csv)'}, ...
                             ternary(gui.rbMultiTables.Value,'Select feature table(s)','Select feature table'), ...
                             'MultiSelect', multiFlag);
    if isequal(sel,0), updateAddButtonState(); return; end

    % Normalize to a cell array of fullpaths
    if ischar(sel), sel = {sel}; end
    fps = cellfun(@(f) fullfile(path,f), sel, 'UniformOutput', false);

    % Append (skip duplicates, drop the placeholder)
    items = gui.fileList.Items;
    if any(strcmp(items,'No table selected')), items = {}; end
    for k = 1:numel(fps)
        if ~ismember(fps{k}, items)
            items{end+1} = fps{k};
            gui.ImportParamsList{end+1} = struct('Sheet','', ...
                'FeaturesColumnName','', 'ScoreColumnName','', ...
                'HoldOutRange',[0 0], 'DomainName','');
        end
    end
    gui.fileList.Items = items;

    % Refresh UI according to mode
    if gui.rbMultiTables.Value
        updateGlobalSelectors();
    else
        fileSelectionChanged();   % repopulate single-table widgets
    end
    updateAddButtonState();
    bringToFront(gui.F);
end


function replaceFile(~,~)
    sel = firstSel(gui.fileList.Value);

    if isempty(sel) || strcmp(sel,'No table selected')
        uialert(gui.F,'Select a valid file first.','No valid file');
        bringToFront(gui.F);
        return
    end
    % Value can be a display string not the full path if you ever change ItemsDisplay.
    % Here we assume Items are full paths; still coerce to char/string scalar:
    if ~(ischar(sel) || (isstring(sel) && isscalar(sel)))
        uialert(gui.F,'Internal selection error. Try selecting one file again.','Selection error');
        bringToFront(gui.F);
        return
    end

    if exist(sel,'file') ~= 2
        uialert(gui.F,'Selected entry is not a file on disk.','No valid file');
        bringToFront(gui.F);
        return
    end

    [file,path] = uigetfile({'*.xlsx;*.xls;*.csv', 'Tables (*.xlsx, *.xls, *.csv)'}, ...
                            'Select replacement table');
    bringToFront(gui.F);
    if isequal(file,0),  return;  end
    fp = fullfile(path,file);

    idx = find(strcmp(gui.fileList.Items, sel), 1);
    if isempty(idx)
        uialert(gui.F,'Could not locate selected item in the list.','Internal error');
        bringToFront(gui.F);
        return
    end

    gui.fileList.Items{idx}   = fp;
    gui.ImportParamsList{idx} = struct( ...
        'Sheet','', 'FeaturesColumnName','', ...
        'ScoreColumnName','', 'HoldOutRange',[0 0], ...
        'DomainName',{{}});

    fileSelectionChanged();
    if gui.rbMultiTables.Value, updateGlobalSelectors(); end

end

function removeFile(~,~)
    sel = firstSel(gui.fileList.Value);

    if isempty(sel) || strcmp(sel,'No table selected') || exist(sel,'file')~=2
        uialert(gui.F,'Select a valid file first.','No valid file');
        bringToFront(gui.F);
        return
    end

    idx = find(strcmp(gui.fileList.Items, sel), 1);
    if isempty(idx), return; end

    gui.fileList.Items(idx) = [];
    gui.ImportParamsList(idx) = [];

    clearControls();
    fileSelectionChanged();
    if gui.rbMultiTables.Value, updateGlobalSelectors(); end
    updateAddButtonState()
end

function clearDropDown(dd)
    % Empties Items and sets a compatible empty Value across releases.
    dd.Items = {};
    % Try the two legal empties in different MATLAB versions
    try
        dd.Value = {};           % some releases require empty cell
    catch
        try dd.Value = ''; end   % others accept empty char/string
    end
end

function fileSelectionChanged(~,~)

    % No files at all?
    noFiles = isempty(gui.fileList.Items) || ...
              strcmp(gui.fileList.Items{1}, 'No table selected');

    if gui.rbMultiTables.Value
        % ------------- MULTI-TABLES MODE -------------
        if noFiles
            % clear dependent UI and disable Run
            setDropDownItems(gui.sheetDropdown, {});
            setDropDownItems(gui.featColDropdown, {});
            setDropDownItems(gui.scoreColDropdown, {});
            enableRunIfValid();
            return
        end

        % We compute intersections across files; nothing to index into ImportParamsList here
        updateGlobalSelectors();   % this populates sheetDropdown, feat/score items
        enableRunIfValid();
        return

    else
        % ------------- SINGLE-TABLE MODE -------------
        if noFiles
            % show empty sheet table, clear columns, and bail safely
            if isfield(gui,'sheetTable') && isvalid(gui.sheetTable)
                gui.sheetTable.Data = table(false(0,1), strings(0,1), ...
                    'VariableNames', {'Use','Sheet'});
                gui.sheetTable.Visible = true;
            end
            gui.lastSheetRow = [];
            gui.domainField.Value = '';
            setDropDownItems(gui.featColDropdown, {});
            setDropDownItems(gui.scoreColDropdown, {});
            enableRunIfValid();
            return
        end

        % There is at least one file: pick it (first selection or first item)
        sel = firstSel(gui.fileList.Value);
        if isempty(sel) || strcmp(sel,'No table selected')
            sel = gui.fileList.Items{1};
        end

        % Populate the 2-col sheet table for that file
        populateSheetTable(sel);

        % Pick a sheet (first row) and preview its vars into the dropdowns
        try
            Tst = gui.sheetTable.Data;
            if istable(Tst) && height(Tst)>0
                firstSheet = Tst.Sheet(1);
                if isa(firstSheet,'string'), sheetVal = firstSheet; else, sheetVal = string(firstSheet); end
                vars = getVarsForSheet(sel, sheetVal);
            else
                % fallback: first sheet name if available
                vars = getVarsForSheet(sel, "1");
            end
        catch
            vars = string.empty(0,1);
        end

        setDropDownItems(gui.featColDropdown, cellstr(vars));
        setDropDownItems(gui.scoreColDropdown, cellstr(vars));

        % Select first sheet row visually & sync domain field
        try
            gui.lastSheetRow = 1;
            sheetTableSelected();
        catch
        end

        enableRunIfValid();
        return
    end
end


function sheets = getSelectedSheets()
    T = gui.sheetTable.Data;
    if istable(T)
        mask = T.Use;
        if iscell(mask), mask = cell2mat(mask); end
        sheets = cellstr(string(T.Sheet(mask)));
    else
        sheets = {};
    end
end

function updateFields(~,~)
    sel = firstSel(gui.fileList.Value);
    if isempty(sel), return; end
    f = sel;

    if gui.rbMultiTables.Value
        s = gui.sheetDropdown.Value;
    else
        % if multiple selected, take the first for previewing column names
        sVal = gui.sheetList.Value;
        if iscell(sVal) && ~isempty(sVal), s = sVal{1};
        elseif ischar(sVal) || (isstring(sVal) && ~isempty(sVal)), s = sVal;
        else, s = 1; % default to first sheet/index
        end
    end

    try
        opts = detectImportOptions(f,'Sheet',s);
        vars = opts.VariableNames;
    catch
        vars = {};
    end
    gui.featColDropdown.Items = vars;
    gui.scoreColDropdown.Items = vars;
end

function saveImportParams(~,~)
    selFile = firstSel(gui.fileList.Value);
    if isempty(selFile), return; end
    idx = find(strcmp(gui.fileList.Items, selFile), 1);
    if isempty(idx), return; end

    ip = gui.ImportParamsList{idx};

    if gui.rbMultiTables.Value
        ip.Sheet = gui.sheetDropdown.Value;
    else
        [sheets, domains] = getSelectedSheetsAndDomains();
        ip.Sheet      = sheets;
        ip.DomainName = domains; 
    end

    ip.FeaturesColumnName = gui.featColDropdown.Value;
    ip.ScoreColumnName    = gui.scoreColDropdown.Value;

    gui.ImportParamsList{idx} = ip;
    enableRunIfValid();
end

function clearControls()
    % dropdowns
    setDropDownItems(gui.sheetDropdown, {});      % multi-tables mode
    setDropDownItems(gui.featColDropdown, {});
    setDropDownItems(gui.scoreColDropdown, {});

    % sheet selector:
    if isfield(gui,'sheetTable') && isvalid(gui.sheetTable)
        % empty 2-col table: Use=false, Sheet=""
        gui.sheetTable.Data = table(false(0,1), strings(0,1), ...
            'VariableNames', {'Use','Sheet'});
        gui.lastSheetRow = [];
    end

    % (only if there is STILL a legacy listbox in the code)
    if isfield(gui,'sheetList') && isvalid(gui.sheetList) ...
            && isa(gui.sheetList,'matlab.ui.control.ListBox')
        setListBoxItems(gui.sheetList, {});
    end

    % misc
    gui.holdoutRange.Value = '[0 0]';
end
function moveUp(~,~)
    if gui.rbMultiTables.Value
        % === FILE order ===
        sel   = firstSel(gui.fileList.Value);
        items = gui.fileList.Items;
        i = find(strcmp(items, sel), 1);
        if isempty(i) || i==1, return; end

        % swap files
        [items{i-1}, items{i}] = deal(items{i}, items{i-1});
        gui.fileList.Items = items;

        % keep ImportParamsList in sync
        [gui.ImportParamsList{i-1}, gui.ImportParamsList{i}] = ...
            deal(gui.ImportParamsList{i}, gui.ImportParamsList{i-1});

        % restore selection
        gui.fileList.Value = {sel};

        % refresh sheet/column fields for the now-selected file
        fileSelectionChanged();
    else
        % Move selected table row up
        T = gui.sheetTable.Data;
        if isempty(T) || isempty(gui.lastSheetRow), return; end
        r = gui.lastSheetRow;
        if r <= 1, return; end
        % swap rows r-1 and r
        T([r-1 r], :) = T([r r-1], :);
        gui.sheetTable.Data = T;
        gui.lastSheetRow = r-1;
        renumberDefaultDomains();
        sheetTableSelected();
        saveImportParams();
    end
end

function moveDown(~,~)
    if gui.rbMultiTables.Value
        % === FILE order ===
        sel   = firstSel(gui.fileList.Value);
        items = gui.fileList.Items;
        i = find(strcmp(items, sel), 1);
        if isempty(i) || i==numel(items), return; end

        [items{i}, items{i+1}] = deal(items{i+1}, items{i});
        gui.fileList.Items = items;

        [gui.ImportParamsList{i}, gui.ImportParamsList{i+1}] = ...
            deal(gui.ImportParamsList{i+1}, gui.ImportParamsList{i});

        gui.fileList.Value = {sel};
        fileSelectionChanged();
    else
        T = gui.sheetTable.Data;
        if isempty(T) || isempty(gui.lastSheetRow), return; end
        r = gui.lastSheetRow;
        if r >= height(T), return; end
        T([r r+1], :) = T([r+1 r], :);
        gui.sheetTable.Data = T;
        gui.lastSheetRow = r+1;
        renumberDefaultDomains();
        sheetTableSelected();
        saveImportParams();
    end
end

function ensureDomainDefaults()
    % Ensure each SELECTED sheet has a domain; set defaults "domain 1..N"
    T = gui.sheetTable.Data;
    if isempty(T), return; end
    mask   = logical(T.Use);
    names  = string(T.Sheet(mask));
    for i = 1:numel(names)
        key = char(names(i));
        if ~isKey(gui.domainMap, key) || isDefaultDomain(gui.domainMap(key))
            gui.domainMap(key) = sprintf('domain %d', i);
        end
    end
end

function renumberDefaultDomains()
    % Renumber defaults for currently SELECTED rows, in table order
    T = gui.sheetTable.Data;
    if isempty(T), return; end
    mask  = logical(T.Use);
    names = string(T.Sheet(mask));
    for i = 1:numel(names)
        key = char(names(i));
        if ~isKey(gui.domainMap, key) || isDefaultDomain(gui.domainMap(key))
            gui.domainMap(key) = sprintf('domain %d', i);
        end
    end
end

function tf = isDefaultDomain(txt)
    if isstring(txt), txt = char(txt); end
    tf = ~isempty(regexp(strtrim(txt), '^domain\s*\d+\s*$', 'once'));
end

    function val = getDomainForSheet(sheetName)
    key = char(sheetName);
    if isKey(gui.domainMap, key)
        val = gui.domainMap(key);
    else
        % default index based on **selected** order; else "domain 1"
        T = gui.sheetTable.Data; mask = logical(T.Use);
        names = cellstr(string(T.Sheet(mask)));
        idx = find(strcmp(names, key), 1);
        if isempty(idx), idx = 1; end
        val = sprintf('domain %d', idx);
    end
end

function setDomainForSheet(sheetName, val)
    gui.domainMap(char(sheetName)) = char(val);
end

function sh = getSheetNames(fp)
% Return a string array of sheet names for Excel; for CSV, return "1"
    try
        [~,~,ext] = fileparts(fp);
        if any(strcmpi(ext,{'.xls','.xlsx','.xlsm'}))
            tmp = sheetnames(fp);
            sh  = string(tmp(:));
        else
            % CSV → emulate single "sheet" named "1". We'll read with numeric 1.
            sh = "1";
        end
    catch
        sh = "1";
    end
end

function vars = getVarsForSheet(fp, sheetSel)
% Return variable names (string array) for the given file/sheet
    try
        [~,~,ext] = fileparts(fp);
        useSheet = sheetSel;
        % If emulated CSV sheet "1", pass numeric 1
        if ~any(strcmpi(ext,{'.xls','.xlsx','.xlsm'}))
            useSheet = 1;
        end
        opts = detectImportOptions(fp,'Sheet',useSheet);
        vars = string(opts.VariableNames(:));
    catch
        vars = string.empty(0,1);
    end
end

function out = intersectStringsCellstrs(listOfStrArrays)
% listOfStrArrays is a cell: each cell holds string array
    if isempty(listOfStrArrays), out = string.empty(0,1); return; end
    out = listOfStrArrays{1};
    for i=2:numel(listOfStrArrays)
        % intersect is case-sensitive → normalize to lower for match, then
        % re-pick original casing from the first array
        a = lower(out); b = lower(listOfStrArrays{i});
        [~,ia] = intersect(a,b,'stable');
        out = out(ia);
        if isempty(out), break; end
    end
end

function enableRunIfValid()
    ok = true;
    if gui.rbMultiTables.Value
        ok = ok && ~isempty(gui.fileList.Items) && ~strcmp(gui.fileList.Items{1},'No table selected');
        ok = ok && ~isempty(gui.sheetDropdown.Items) && any(strcmp(gui.sheetDropdown.Items, gui.sheetDropdown.Value));
        ok = ok && ~isempty(gui.featColDropdown.Items) && any(strcmp(gui.featColDropdown.Items, gui.featColDropdown.Value));
        ok = ok && ~isempty(gui.scoreColDropdown.Items) && any(strcmp(gui.scoreColDropdown.Items, gui.scoreColDropdown.Value));
    else
        % single-table mode
        T = gui.sheetTable.Data;
        sel = false;
        if istable(T) && height(T)>0
            m = T.Use; if iscell(m), m = cell2mat(m); end
            sel = any(m);
        end
        ok = ok && sel ...
               && ~isempty(gui.featColDropdown.Items) && any(strcmp(gui.featColDropdown.Items, gui.featColDropdown.Value)) ...
               && ~isempty(gui.scoreColDropdown.Items) && any(strcmp(gui.scoreColDropdown.Items, gui.scoreColDropdown.Value));
    end
    gui.runBtn.Enable = ternary(ok,'on','off');
end
function updateGlobalSelectors()
% For Multi-Tables mode: compute common sheets, then common vars for chosen sheet,
% and populate the 3 dropdowns accordingly.

    if ~gui.rbMultiTables.Value, return; end

    files = gui.fileList.Items;
    if isempty(files) || strcmp(files{1},'No table selected')
        clearDropDown(gui.sheetDropdown);
        clearDropDown(gui.featColDropdown);
        clearDropDown(gui.scoreColDropdown);
        enableRunIfValid();
        return
    end

    % 1) Common sheets across all files
    perFileSheets = cellfun(@getSheetNames, files, 'UniformOutput', false); % -> cell of string arrays
    commonSheets  = intersectStringsCellstrs(perFileSheets);                % -> string array (may be empty)

    if isempty(commonSheets)
        clearDropDown(gui.sheetDropdown);
        clearDropDown(gui.featColDropdown);
        clearDropDown(gui.scoreColDropdown);
        gui.runBtn.Enable = 'off';
        uialert(gui.F, 'No common sheet exists across all tables. Choose files that share a sheet name.', 'No common sheet');
        return
    end

    % helper: keep previous selection if still in options, else first
    function val = keepOrFirst(optionsCell, prevVal)
        if isempty(optionsCell), val = ''; return; end
        if nargin < 2 || isempty(prevVal), val = optionsCell{1}; return; end
        if iscell(prevVal),   prevVal = prevVal{1}; end
        if isstring(prevVal), prevVal = char(prevVal(1)); end
        if any(strcmpi(optionsCell, prevVal)), val = prevVal; else, val = optionsCell{1}; end
    end

    % Populate sheet dropdown (as cellstr)
    commonSheetsCell = cellstr(commonSheets);
    gui.sheetDropdown.Items = commonSheetsCell;
    gui.sheetDropdown.Value = keepOrFirst(commonSheetsCell, gui.sheetDropdown.Value);

    % 2) Common variables (columns) for the selected common sheet
    selSheet = string(gui.sheetDropdown.Value);
    perFileVars = cellfun(@(fp) getVarsForSheet(fp, selSheet), files, 'UniformOutput', false); % -> cell of string arrays
    commonVars  = intersectStringsCellstrs(perFileVars);                                       % -> string array

    if isempty(commonVars)
        clearDropDown(gui.featColDropdown);
        clearDropDown(gui.scoreColDropdown);
        gui.runBtn.Enable = 'off';
        uialert(gui.F, sprintf(['Sheet "%s" exists in all files, but there are no common column names.\n' ...
                                'Pick another sheet or adjust your inputs.'], selSheet), 'No common columns');
        return
    end

    % Populate feature/score dropdowns (as cellstr)
    commonVarsCell = cellstr(commonVars);
    gui.featColDropdown.Items  = commonVarsCell;
    gui.scoreColDropdown.Items = commonVarsCell;

    newFeat  = keepOrFirst(gui.featColDropdown.Items,  gui.featColDropdown.Value);
    newScore = keepOrFirst(gui.scoreColDropdown.Items, gui.scoreColDropdown.Value);

    % Avoid identical defaults if possible
    if strcmp(newScore, newFeat) && numel(gui.scoreColDropdown.Items) >= 2
        diffs = setdiff(gui.scoreColDropdown.Items, {newFeat}, 'stable');
        if ~isempty(diffs), newScore = diffs{1}; end
    end

    gui.featColDropdown.Value  = newFeat;
    gui.scoreColDropdown.Value = newScore;

    enableRunIfValid();
end

function setDropDownItems(dd, items)
    if isstring(items), items = cellstr(items); end
    if isempty(items)
        clearDropDown(dd);
    else
        dd.Items = items;
        dd.Value = items{1};
    end
end

function setListBoxItems(lb, items)
    if ~isvalid(lb) || ~isa(lb,'matlab.ui.control.ListBox')
        % Not a listbox (likely your new uitable) → ignore safely
        return
    end
    lb.Items = items;
    if isempty(items)
        if strcmp(lb.Multiselect,'on')
            lb.Value = {};
        else
            try lb.Value = ''; catch, lb.Value = {}; end
        end
    else
        if strcmp(lb.Multiselect,'on')
            lb.Value = {items{1}};
        else
            lb.Value = items{1};
        end
    end
end

function runCallback(~,~)

    % -------- Build ImportParams & assemble Features/Scores ---------------
    if gui.rbMultiTables.Value
        % ====================== MULTI-TABLES: one sheet across files ======================
        files = gui.fileList.Items;
        n     = numel(files);

        selSheet = string(gui.sheetDropdown.Value);
        featVar  = gui.featColDropdown.Value;
        scoreVar = gui.scoreColDropdown.Value;

        Features    = cell(n,1);
        Scores      = cell(n,1);
        DomainNames = cell(n,1);

        for k = 1:n
            [~,~,ext] = fileparts(files{k});
            useSheet = selSheet;
            if ~any(strcmpi(ext,{'.xls','.xlsx','.xlsm'}))
                useSheet = 1; % CSV → single "sheet"
            end

            T = readtable(files{k}, 'Sheet', useSheet);

            if ~ismember(featVar,  T.Properties.VariableNames)
                uialert(gui.F, sprintf('Feature column "%s" not found in "%s" (sheet %s).', ...
                        featVar, files{k}, string(selSheet)), 'Missing column'); bringToFront(gui.F); return
            end
            if ~ismember(scoreVar, T.Properties.VariableNames)
                uialert(gui.F, sprintf('Score column "%s" not found in "%s" (sheet %s).', ...
                        scoreVar, files{k}, string(selSheet)), 'Missing column'); bringToFront(gui.F); return
            end

            Features{k} = T.(featVar);
            Scores{k}   = T.(scoreVar);

            % Domain label: "<Domain> [<filename>]"
            dom = strtrim(string(gui.domainField.Value)); if dom=="", dom="Domain"; end
            [~,bn] = fileparts(files{k});
            DomainNames{k} = { sprintf('%s [%s]', char(dom), bn) };
        end

        nSets = numel(Features);
        ImportParams.FeaturesColumnName = featVar;
        ImportParams.ScoreColumnName    = scoreVar;
        ImportParams.DomainNames        = DomainNames;
        ImportParams.ClassName          = repmat({strtrim(strsplit(gui.classesField.Value,','))},1,nSets);

    else
        files = gui.fileList.Items;  f = files{1};
        [sheets, domains] = getSelectedSheetsAndDomains();
        if isempty(sheets)
            uialert(gui.F,'Tick one or more sheets to plot.','No sheets'); bringToFront(gui.F); return
        end
        nSheets = numel(sheets);
        
        featVar  = gui.featColDropdown.Value;
        scoreVar = gui.scoreColDropdown.Value;
        if isempty(featVar) || isempty(scoreVar)
            uialert(gui.F,'Choose Feature and Score columns first.','Columns required'); bringToFront(gui.F); return
        end
        
        Features    = cell(nSheets,1);
        Scores      = cell(nSheets,1);
        DomainNames = cell(nSheets,1);
        
        [~,~,ext] = fileparts(f);
        isExcel = any(strcmpi(ext,{'.xls','.xlsx','.xlsm'}));
        
        for i = 1:nSheets
            sheet = sheets{i};
            try
                if isExcel, T = readtable(f,'Sheet',sheet);
                else,       T = readtable(f);
                end
            catch ME
                uialert(gui.F, sprintf('Failed to read sheet "%s" from "%s":\n%s', ...
                        char(string(sheet)), f, ME.message), 'Read error');
                bringToFront(gui.F); return
            end
        
            if ~ismember(featVar,  T.Properties.VariableNames)
                uialert(gui.F, sprintf('Feature column "%s" not found in sheet "%s".', featVar, sheet), ...
                        'Missing column'); bringToFront(gui.F); return
            end
            if ~ismember(scoreVar, T.Properties.VariableNames)
                uialert(gui.F, sprintf('Score column "%s" not found in sheet "%s".', scoreVar, sheet), ...
                        'Missing column'); bringToFront(gui.F); return
            end
        
            Features{i} = T.(featVar);
            Scores{i}   = T.(scoreVar);
        
            dom = strtrim(domains{i});
            if isempty(dom), dom = sprintf('domain %d', i); end
            DomainNames{i} = { dom };
        end

        nSets = numel(Features);
        ImportParams.FeaturesColumnName = featVar;
        ImportParams.ScoreColumnName    = scoreVar;
        ImportParams.DomainNames        = DomainNames;
        ImportParams.ClassName          = repmat({strtrim(strsplit(gui.classesField.Value,','))},1,nSets);
    end

    % ------------------------------ PlotParams ----------------------------
    tok = regexp(gui.holdoutRange.Value, '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match');
    PlotParams.HoldOutRange = str2double(tok);
    if any(isnan(PlotParams.HoldOutRange))
        uialert(gui.F,'Invalid Hold-out range. Use a number or [neg pos].','Input error'); bringToFront(gui.F); return
    end
    tok = regexp(gui.cbrangeField.Value, '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match');
    PlotParams.ColorBarRange = str2double(tok);
    if any(isnan(PlotParams.ColorBarRange))
        uialert(gui.F,'Invalid colorbar range. Use a number or [min max].','Input error'); bringToFront(gui.F); return
    end
    PlotParams.RGBposneg = [rgb(gui.rgbPosField.Value); rgb(gui.rgbNegField.Value)];
    PlotParams.RGBback   = rgb(gui.rgbBackField.Value);
    PlotParams.SortBy    = gui.sortByField.Value;
    PlotParams.Order     = gui.orderField.Value;

    % ------------------------------ ExportParams --------------------------
    ExportParams.figfilename = gui.filenameField.Value;
    ExportParams.resolution  = gui.resolField.Value;
    ExportParams.filetype    = gui.ftypeField.Value;

    % ------------------ FILTER FEATURES & SCORES by HoldOutRange ----------
    for i = 1:numel(Features)
        fset = Features{i};
        sset = Scores{i};
        hr   = PlotParams.HoldOutRange;

        % Normalize hr
        if numel(hr)==2
            if ~((hr(1)<0 && hr(2)>0) || (hr(2)<0 && hr(1)>0))
                error('HoldOutRange for set %d must contain one negative and one positive value.', i);
            end
            hr = sort(hr); lo = hr(1); hi = hr(2);
        elseif isscalar(hr)
            if hr > 0, lo = []; hi = hr;
            elseif hr < 0, lo = hr; hi = [];
            else, error('HoldOutRange for set %d cannot be zero.', i);
            end
        else
            error('HoldOutRange for set %d must have one or two elements.', i);
        end

        % Mask & apply
        if ~isempty(lo) && ~isempty(hi)
            mask = (sset <= lo) | (sset >= hi);
        elseif ~isempty(hi)
            mask = (sset >= hi);
        elseif ~isempty(lo)
            mask = (sset <= lo);
        else
            mask = true(size(sset));
        end
        Features{i} = fset(mask);
        Scores{i}   = sset(mask);
    end

    % --------------------------- Plot + layout ----------------------------
    ClassNames    = ImportParams.ClassName;
    DomainNames   = ImportParams.DomainNames;
    ScoreName     = ImportParams.ScoreColumnName;
    FigureName    = gui.filenameField.Value;
    HoldOutRange  = PlotParams.HoldOutRange;
    ColorbarRange = PlotParams.ColorBarRange;
    RGBposneg     = PlotParams.RGBposneg;
    RGBback       = PlotParams.RGBback;
    SortBy        = PlotParams.SortBy;
    Order         = PlotParams.Order;
    RectangleHeightMode = 'constant';
    MinAlpha = 0.1;

    [axes_handles, cb_ax] = nk_PrintFeatRelev25D(Features, ...
        Scores, ClassNames, DomainNames, ScoreName, FigureName, ...
        HoldOutRange, ColorbarRange, RGBposneg, RGBback, ...
        SortBy, Order, RectangleHeightMode, MinAlpha);

    if nSets > 5
        errordlg(sprintf('Too many domains (%d). Maximum supported is 5.', nSets));
        return
    end

    % Layout
    n           = nSets;
    left_margin = 0.02; spacing = 0.01; bottom = 0.06; height = 0.90;
    cbWidth     = 0.01; cbMargin = 0.02; tickMargin = 0.01;
    protected_right = cbWidth + cbMargin + tickMargin;
    available_width = 1 - left_margin - protected_right;
    width = (available_width - spacing*(n-1)) / n;

    for i = 1:n
        x0 = left_margin + (i-1)*(width + spacing);
        axes_handles{i}.Position          = [x0, bottom, width, height];
        axes_handles{i}.Legend.Visible    = "off";
        axes_handles{i}.XLabel.String     = 'absolute CVR score';
        axes_handles{i}.XLabel.FontWeight = 'bold';
    end

    cb_x = left_margin + available_width + cbMargin;
    cb_ax.Position = [cb_x - 0.015, bottom, cbWidth, height];

    % ------------------------------ Export --------------------------------
    filename = sprintf('FeatureRelevancePlot_%s.%s', FigureName, ExportParams.filetype);
    % Export the plotting figure rather than the app window
    try
        plotFig = ancestor(axes_handles{1}, 'figure');
        exportgraphics(plotFig, filename, 'Resolution', ExportParams.resolution);
    catch
        exportgraphics(gcf, filename, 'Resolution', ExportParams.resolution);
    end
end

% Helper: ternary operator
function out = ternary(cond,valTrue,valFalse)
    if cond, out = valTrue; else, out = valFalse; end
end
end

function s = firstSel(val)
    % Return a single char/string path from listbox Value
    if isempty(val), s = ''; return; end
    if iscell(val)
        if isempty(val{1}), s = ''; else, s = val{1}; end
    else
        s = val; % string scalar or char
    end
    if isstring(s), s = s(1); end
    if iscell(s),  s = s{1}; end
end

function bringToFront(fig)
%BRINGTOFRONT Raise a uifigure to the front (works on Windows/macOS/Linux)
%   Safe to call for both UIFigures and classic figures.

    if ~ishandle(fig) || ~isvalid(fig), return; end

    % Strategy A: toggle visibility (reliably bumps z-order for UIFigure)
    try
        oldVis = fig.Visible;
        fig.Visible = 'off';
        drawnow; pause(0.01);
        fig.Visible = oldVis;
        drawnow;
    catch
    end

    % Strategy B: classic figure raise (no-op for UIFigure; safe in try/catch)
    try
        figure(fig);
        drawnow;
    catch
    end

    % Strategy C: tiny position nudge (last resort on some window managers)
    try
        p = fig.Position;
        fig.Position = [p(1)+1 p(2) p(3) p(4)];
        drawnow;
        fig.Position = p;
        drawnow;
    catch
    end
end

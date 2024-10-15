function nk_FeatureRelevanceGUI()
    % Create the main figure window
    fig = figure('Name', 'Feature Relevance Visualization', ...
                 'NumberTitle', 'off', ...
                 'MenuBar', 'none', ...
                 'ToolBar', 'none', ...
                 'HandleVisibility', 'on', ...
                 'Position', [100, 100, 1200, 700]);
    
    % Store data and parameters in the figure's UserData property
    data = struct();
    data.Features = {};
    data.Scores = {};
    data.ClassNames = {};
    data.ModelNames = {};
    data.ScoreName = 'Score';
    data.HoldOutRange = [0, 0];
    data.ColorbarRange = [];
    data.SortBy = 'absolute';
    data.Order = 'descending';
    data.RectangleHeightMode = 'constant';
    data.MinAlpha = 0.3; % Default minimum alpha value
    guidata(fig, data);
    
    % Proceed to create UI controls and axes
    createUIControls(fig);
end

function createUIControls(fig)
    % Get the data structure from the figure
    data = guidata(fig);
    
    % Set positions for UI controls
    leftPanelWidth = 250;
    controlHeight = 25;
    spacing = 10;
    panelStartY = 650;
    
    % Create a panel for controls
    uipanel('Parent', fig, 'Title', 'Controls', ...
            'Units', 'pixels', ...
            'Position', [10, 10, leftPanelWidth - 20, panelStartY]);
    
    % Position variable
    posY = panelStartY - 50;
    
    % Load Data Buttons
    uicontrol('Parent', fig, 'Style', 'pushbutton', 'String', 'Load Features', ...
        'Position', [20, posY, leftPanelWidth - 40, controlHeight], ...
        'Callback', @(src, event)loadFeaturesCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    uicontrol('Parent', fig, 'Style', 'pushbutton', 'String', 'Load Scores', ...
        'Position', [20, posY, leftPanelWidth - 40, controlHeight], ...
        'Callback', @(src, event)loadScoresCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    % ... (Add buttons for ClassNames and ModelNames similarly)
    
    % SortBy Dropdown
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Sort By:', ...
        'Position', [20, posY, 80, controlHeight], 'HorizontalAlignment', 'left');
    data.SortByPopup = uicontrol('Parent', fig, 'Style', 'popupmenu', ...
        'String', {'absolute', 'original'}, ...
        'Position', [100, posY, leftPanelWidth - 120, controlHeight], ...
        'Callback', @(src, event)sortByCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    % Order Dropdown
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Order:', ...
        'Position', [20, posY, 80, controlHeight], 'HorizontalAlignment', 'left');
    data.OrderPopup = uicontrol('Parent', fig, 'Style', 'popupmenu', ...
        'String', {'ascending', 'descending'}, ...
        'Position', [100, posY, leftPanelWidth - 120, controlHeight], ...
        'Callback', @(src, event)orderCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    % Rectangle Height Mode Dropdown
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Rectangle Height Mode:', ...
        'Position', [20, posY, 150, controlHeight], 'HorizontalAlignment', 'left');
    data.HeightModePopup = uicontrol('Parent', fig, 'Style', 'popupmenu', ...
        'String', {'constant', 'proportional'}, ...
        'Position', [170, posY, leftPanelWidth - 190, controlHeight], ...
        'Callback', @(src, event)heightModeCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    % HoldOutRange Inputs
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'HoldOutRange Min:', ...
        'Position', [20, posY, 120, controlHeight], 'HorizontalAlignment', 'left');
    data.HoldOutMinEdit = uicontrol('Parent', fig, 'Style', 'edit', ...
        'String', num2str(data.HoldOutRange(1)), ...
        'Position', [150, posY, leftPanelWidth - 170, controlHeight], ...
        'Callback', @(src, event)holdOutMinCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'HoldOutRange Max:', ...
        'Position', [20, posY, 120, controlHeight], 'HorizontalAlignment', 'left');
    data.HoldOutMaxEdit = uicontrol('Parent', fig, 'Style', 'edit', ...
        'String', num2str(data.HoldOutRange(2)), ...
        'Position', [150, posY, leftPanelWidth - 170, controlHeight], ...
        'Callback', @(src, event)holdOutMaxCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    % ColorbarRange Inputs
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'ColorbarRange Min:', ...
        'Position', [20, posY, 120, controlHeight], 'HorizontalAlignment', 'left');
    data.ColorbarMinEdit = uicontrol('Parent', fig, 'Style', 'edit', ...
        'String', '', ...
        'Position', [150, posY, leftPanelWidth - 170, controlHeight], ...
        'Callback', @(src, event)colorbarMinCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'ColorbarRange Max:', ...
        'Position', [20, posY, 120, controlHeight], 'HorizontalAlignment', 'left');
    data.ColorbarMaxEdit = uicontrol('Parent', fig, 'Style', 'edit', ...
        'String', '', ...
        'Position', [150, posY, leftPanelWidth - 170, controlHeight], ...
        'Callback', @(src, event)colorbarMaxCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    % Minimum Alpha Slider
    uicontrol('Parent', fig, 'Style', 'text', 'String', 'Minimum Alpha Value:', ...
        'Position', [20, posY, 150, controlHeight], 'HorizontalAlignment', 'left');
    data.MinAlphaSlider = uicontrol('Parent', fig, 'Style', 'slider', ...
        'Min', 0, 'Max', 1, 'Value', data.MinAlpha, ...
        'Position', [20, posY - 20, leftPanelWidth - 40, controlHeight], ...
        'Callback', @(src, event)minAlphaCallback(fig));
    posY = posY - (controlHeight + spacing + 20);
    
    % Update Plot Button
    uicontrol('Parent', fig, 'Style', 'pushbutton', 'String', 'Update Plot', ...
        'Position', [20, posY, leftPanelWidth - 40, controlHeight], ...
        'Callback', @(src, event)updatePlotCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    % Save Plot Button
    uicontrol('Parent', fig, 'Style', 'pushbutton', 'String', 'Save Plot', ...
        'Position', [20, posY, leftPanelWidth - 40, controlHeight], ...
        'Callback', @(src, event)savePlotCallback(fig));
    posY = posY - (controlHeight + spacing);
    
    % Store updated data
    guidata(fig, data);
    
    % Create axes for plotting
    createPlotAxes(fig);
end

function createPlotAxes(fig)
    % Position the axes to the right of the control panel
    axesPosition = [300, 50, 850, 600]; % Adjust as needed
    data = guidata(fig);
    data.PlotAxes = axes('Parent', fig, 'Units', 'pixels', 'Position', axesPosition);
    guidata(fig, data);
end

function loadFeaturesCallback(fig)
    data = guidata(fig);
    [file, path] = uigetfile({'*.mat;*.csv'}, 'Select Features File');
    if isequal(file, 0)
        return; % User canceled
    end
    fullPath = fullfile(path, file);
    [~, ~, ext] = fileparts(fullPath);
    switch ext
        case '.mat'
            temp = load(fullPath);
            if isfield(temp, 'Features')
                data.Features = temp.Features;
            else
                errordlg('Selected file does not contain ''Features'' variable.', 'Error');
                return;
            end
        case '.csv'
            data.Features = readcell(fullPath);
        % Add more cases if needed
    end
    guidata(fig, data);
    disp('Features loaded successfully.');
end

function loadScoresCallback(fig)
    data = guidata(fig);
    [file, path] = uigetfile({'*.mat;*.csv'}, 'Select Scores File');
    if isequal(file, 0)
        return; % User canceled
    end
    fullPath = fullfile(path, file);
    [~, ~, ext] = fileparts(fullPath);
    switch ext
        case '.mat'
            temp = load(fullPath);
            if isfield(temp, 'Scores')
                data.Scores = temp.Scores;
            else
                errordlg('Selected file does not contain ''Scores'' variable.', 'Error');
                return;
            end
        case '.csv'
            data.Scores = readmatrix(fullPath);
        % Add more cases if needed
    end
    guidata(fig, data);
    disp('Scores loaded successfully.');
end

function sortByCallback(fig)
    data = guidata(fig);
    items = get(data.SortByPopup, 'String');
    index = get(data.SortByPopup, 'Value');
    data.SortBy = items{index};
    guidata(fig, data);
end

function orderCallback(fig)
    data = guidata(fig);
    items = get(data.OrderPopup, 'String');
    index = get(data.OrderPopup, 'Value');
    data.Order = items{index};
    guidata(fig, data);
end

function heightModeCallback(fig)
    data = guidata(fig);
    items = get(data.HeightModePopup, 'String');
    index = get(data.HeightModePopup, 'Value');
    data.RectangleHeightMode = items{index};
    guidata(fig, data);
end

function holdOutMinCallback(fig)
    data = guidata(fig);
    value = str2double(get(data.HoldOutMinEdit, 'String'));
    if isnan(value)
        errordlg('Please enter a valid number for HoldOutRange Min.', 'Invalid Input');
    else
        data.HoldOutRange(1) = value;
        guidata(fig, data);
    end
end

function holdOutMaxCallback(fig)
    data = guidata(fig);
    value = str2double(get(data.HoldOutMaxEdit, 'String'));
    if isnan(value)
        errordlg('Please enter a valid number for HoldOutRange Max.', 'Invalid Input');
    else
        data.HoldOutRange(2) = value;
        guidata(fig, data);
    end
end

function colorbarMinCallback(fig)
    data = guidata(fig);
    value = str2double(get(data.ColorbarMinEdit, 'String'));
    if isnan(value)
        errordlg('Please enter a valid number for ColorbarRange Min.', 'Invalid Input');
    else
        if isempty(data.ColorbarRange)
            data.ColorbarRange = [value, value]; % Initialize
        else
            data.ColorbarRange(1) = value;
        end
        guidata(fig, data);
    end
end

function colorbarMaxCallback(fig)
    data = guidata(fig);
    value = str2double(get(data.ColorbarMaxEdit, 'String'));
    if isnan(value)
        errordlg('Please enter a valid number for ColorbarRange Max.', 'Invalid Input');
    else
        if isempty(data.ColorbarRange)
            data.ColorbarRange = [value, value]; % Initialize
        else
            data.ColorbarRange(2) = value;
        end
        guidata(fig, data);
    end
end

function minAlphaCallback(fig)
    data = guidata(fig);
    value = get(data.MinAlphaSlider, 'Value');
    data.MinAlpha = value;
    guidata(fig, data);
end

function updatePlotCallback(fig)
    data = guidata(fig);
    % Validate that necessary data is loaded
    if isempty(data.Features) || isempty(data.Scores)
        errordlg('Please load both Features and Scores data.', 'Data Missing');
        return;
    end
    % Call the modified plotting function
    axes_handles = nk_PrintFeatRelev25DGUI(data, data.PlotAxes);
    % Optionally, store axes_handles if needed
end

function savePlotCallback(fig)
    [file, path] = uiputfile({'*.png'; '*.jpg'; '*.pdf'}, 'Save Plot As');
    if isequal(file, 0)
        return; % User canceled
    end
    fullPath = fullfile(path, file);
    % Save the plot displayed in the axes
    data = guidata(fig);
    exportgraphics(data.PlotAxes, fullPath);
    disp(['Plot saved to ', fullPath]);
end

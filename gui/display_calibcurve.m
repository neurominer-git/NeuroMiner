function display_calibcurve(y_true, y_probs, title)
    % plotInteractiveCalibrationCurve Creates an interactive plot for calibration curve
    %   y_true - True binary labels (0 or 1)
    %   y_probs - Predicted probabilities

    % Create figure with normalized units
    f = figure('Name', 'Interactive Calibration Curve', 'NumberTitle', 'off', 'Units', 'normalized');

    % Positioning constants
    controlHeight = 0.05;
    controlSpacing = 0.02;
    textWidth = 0.17;
    sliderWidth = 0.2;
    checkboxWidth = 0.17;
    axesHeight = 0.7;
    dropdownWidth = 0.2;
    minBins = 3;
    maxBins = 20;
    defaultBins = 10;
    totalControlsWidth = textWidth + sliderWidth + checkboxWidth + dropdownWidth + 4 * controlSpacing;

    % Starting X position for controls to center them
    startX = (1 - totalControlsWidth) / 2;

    hBins = uicontrol(f, 'Style', 'slider', 'Units', 'normalized', ...
                       'Min', minBins, 'Max', maxBins, 'Value', defaultBins, ...
                      'Position', [startX + textWidth + controlSpacing, 0.97 - controlHeight, sliderWidth, controlHeight], ...
                      'SliderStep', [1/(maxBins-minBins) 1/(maxBins-minBins)], ...
                      'Callback', @(es,ed) updatePlot());
    
    hBinText = uicontrol(f, 'Style', 'text', 'Units', 'normalized', ...
              'Position', [startX, 0.9625 - controlHeight, textWidth, controlHeight], ...
              'String', sprintf('Number of Bins: %g',hBins.Value));

    % UI control for smoothing
    hSmooth = uicontrol(f, 'Style', 'checkbox', 'Units', 'normalized', ...
                        'Position', [startX + textWidth + sliderWidth + 3 * controlSpacing, 0.97 - controlHeight, checkboxWidth, controlHeight], ...
                        'String', 'Smooth Curve', 'Callback', @(es,ed) updatePlot());

     % Dropdown menu for metric selection
    hMetricDropdown = uicontrol(f, 'Style', 'popupmenu', 'Units', 'normalized', ...
                               'Position', [startX + textWidth + sliderWidth + checkboxWidth + 4 * controlSpacing, 0.97 - controlHeight, textWidth, controlHeight], ...
                               'String', {'ECE', 'Brier Score'}, 'Callback', @(es,ed) updatePlot());


    % Axes for plot, positioned below the controls
    ax = axes(f, 'Units', 'normalized', 'Position', [controlSpacing+0.1, controlSpacing+0.1, 1 - 2 * controlSpacing-0.15, axesHeight]);


    % Function to update the plot
    function updatePlot()
        numBins = round(get(hBins, 'Value'));
        smoothCurve = get(hSmooth, 'Value');
        metric = hMetricDropdown.String{hMetricDropdown.Value};
        hBinText.String = sprintf('Number of Bins: %g',round(hBins.Value));

        % Clear current axes
        cla(ax);

        % Plot the calibration curve with the specified number of bins
        nk_PerfCalibrationAnalysis(ax, y_true, y_probs, numBins, smoothCurve, metric, title);
    end

    % Initial plot
    updatePlot();

end
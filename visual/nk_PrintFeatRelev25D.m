function [axes_handles, cb_ax] = nk_PrintFeatRelev25D(Features, ...
                        Scores, ClassNames, DomainNames, ScoreName, FigureName, ...
                        HoldOutRange, ColorbarRange, RGBposneg, RGBback, ...
                        SortBy, Order, RectangleHeightMode, MinAlpha)
% nk_PrintFeatRelev25D - Visualizes feature relevance with scaled rectangles.
% ==================================================================================
% Supports multiple feature sets displayed side by side, each within their own axes.
%
% Syntax:
%  [axes_handles, cb_ax] = nk_PrintFeatRelev25D(Features, ...
%                        Scores, ClassNames, DomainNames, ScoreName, FigureName, ...
%                        HoldOutRange, ColorbarRange, RGBposneg, RGBback, ...
%                        SortBy, Order, RectangleHeightMode, MinAlpha)
%
% Inputs:
%   Features            - Cell array of feature name arrays.
%   Scores              - Cell array of score arrays.
%   ClassNames          - Cell array of class name pairs.
%   DomainNames          - Cell array of model titles.
%   ScoreName           - String representing the name of the score (e.g., 'Score').
%   HoldOutRange        - Two-element vector specifying the transparent score range [min, max].
%   FigureName          - (Optional) Name of the figure
%   RGBposneg           - (Optional) 2x3 array with RGBposneg(1,:)
%                           containing the RGB color triplet for the
%                           positive range and RGBposneg(2,:) and
%                           containing the RGB color triplet for the negative range.
%   RGBback             - (Optional) rgb triplet specifying the background
%                           color of the each axis object
%   ColorbarRange       - (Optional) Two-element vector specifying [min, max] of the colorbar.
%   SortBy              - (Optional) String specifying whether to sort by 'absolute' or 'original' scores. Default is 'absolute'.
%   Order               - (Optional) String specifying 'ascending' or 'descending' order. Default is 'descending'.
%   RectangleHeightMode - (Optional) String specifying rectangle height mode ('proportional', 'constant'). Default is 'constant'.
%   MinAlpha            - (Optional) maximum alpha level for positive and
%                         negative colorbar areas
% Outputs:
%   axes_handles        - Cell array of axes handles for each subplot.
%   cb_ax               - handle of colorbar

% Handle default inputs
if ~exist('SortBy', 'var') || isempty(SortBy)
    SortBy = 'absolute';
end
if ~exist('Order', 'var') || isempty(Order)
    Order = 'descending';
end
if ~exist('RectangleHeightMode', 'var') || isempty(RectangleHeightMode)
    RectangleHeightMode = 'constant';
end
if ~exist('FigureName', 'var') || isempty(FigureName)
    FigureName = 'Ranked feature plot';
end
if ~exist('RGBposneg', 'var') || isempty(RGBposneg)
    rgb_pos = rgb("red");
    rgb_neg = rgb("blue");
else
    rgb_pos = RGBposneg(1,:);
    rgb_neg = RGBposneg(2,:);
end
if ~exist('RGBback', 'var') || isempty(RGBback)
    rgb_back = [1 1 1];
else
    rgb_back = RGBback;
end

% Provide default values for ColorbarRange and HoldOutRange if not provided
if ~exist('ColorbarRange', 'var') || isempty(ColorbarRange)
    % Calculate default ColorbarRange based on the data
    allScores = cell2mat(Scores(:));
    global_min_score = min(allScores);
    global_max_score = max(allScores);
    rounded_min_score = floor(global_min_score);
    rounded_max_score = ceil(global_max_score);
    ColorbarRange = [rounded_min_score, rounded_max_score];
end

if ~exist('HoldOutRange', 'var') || isempty(HoldOutRange)
    HoldOutRange = [0, 0];
end

% Ensure inputs are cell arrays
if ~iscell(Features); Features = {Features}; end
if ~iscell(Scores); Scores = {Scores}; end
if ~iscell(ClassNames); ClassNames = {ClassNames}; end
if ~iscell(DomainNames); DomainNames = {DomainNames}; end

numSets = length(Features);

% Ensure that ClassNames, DomainNames, and Scores have the correct lengths
if length(ClassNames) ~= numSets
    error('The number of ClassNames entries must match the number of feature sets in Features and Scores.');
end
if length(DomainNames) ~= numSets
    error('The number of DomainNames entries must match the number of feature sets in Features and Scores.');
end
if length(Scores) ~= numSets
    error('The number of Scores entries must match the number of feature sets in Features.');
end

% Determine maximum number of features across all sets
max_nFeatures = max(cellfun(@length, Features));

% Calculate font size based on the maximum number of features
minFontSize = 7;
maxFontSize = 12;
maxFeaturesForScaling = 15;
if max_nFeatures <= maxFeaturesForScaling
    fontSize = maxFontSize - ((max_nFeatures - 1) * (maxFontSize - minFontSize) / (maxFeaturesForScaling - 1));
else
    fontSize = minFontSize;
end
fontSize = max(minFontSize, fontSize);

% Create figure
% Get the screen size
%screenSize = get(0, 'screensize');

% Create a figure with screen size dimensions
fig = figure('Name', FigureName, 'Color', 'w', 'Units', 'normalized');%,'Position', [0 0 screenSize(3) screenSize(4)]);

% Create temporary, invisible axes for text extent calculation
temp_ax = axes('Parent', fig, 'Visible', 'off');

% Initialize variables for computing maximum required axes width
max_required_width = 0;

% Calculate maximum absolute score beyond HoldOutRange
allScores = cell2mat(Scores(:));
scores_beyond_holdout = allScores(abs(allScores) > HoldOutRange(2));
if isempty(scores_beyond_holdout)
    max_abs_score = 1; % To avoid division by zero
else
    max_abs_score = max(abs(scores_beyond_holdout));
end

% First pass: Compute the maximum required width for the axes
for idx = 1:numSets
    FeaturesSet = Features{idx};
    ScoresSet = Scores{idx};

    % Replace underscores with spaces in feature descriptions
    FeaturesSet = strrep(FeaturesSet, '_', ' ');

    % Ensure features and scores are column vectors
    FeaturesSet = FeaturesSet(:);
    ScoresSet = ScoresSet(:);

    % Compute widths based on absolute score values
    Widths = abs(ScoresSet);
    %scaling_factor =  10 / max_abs_score; % Scale to a maximum width of 10
    %Widths = Widths * scaling_factor;

    % Calculate the required width for text labels
    for i = 1:length(FeaturesSet)
        % Create the text object in the temporary axes
        dummy_text = text(temp_ax, 0, 0, FeaturesSet{i}, 'FontSize', fontSize, 'Units', 'data', 'Visible', 'off');
        text_extent = get(dummy_text, 'Extent');
        delete(dummy_text);
        text_width = text_extent(3);
        x_position = Widths(i) + 0.05 + text_width;
        max_required_width = max(max_required_width, x_position + 0.5); % Extra padding
    end
end

% Delete the temporary axes
delete(temp_ax);

% Adjust axes positions and widths based on max_required_width
total_width = 0.7; % Total width allocated for subplots
subplot_spacing = 0.025; % Spacing between subplots
main_ax_width = (total_width - (numSets - 1) * subplot_spacing) / numSets;
axes_handles = cell(numSets, 1);

% Determine rectangle heights based on RectangleHeightMode
if strcmp(RectangleHeightMode, 'constant')
    % Use constant height for rectangles across subplots
    rect_height = 1;
    % Total height is determined by the subplot with the maximum number of features
    total_height = max_nFeatures * rect_height;
elseif strcmp(RectangleHeightMode, 'proportional')
    % Adjust rectangle heights so that they fill the axes height
    total_height = 1; % Normalized to 1
else
    error('Invalid RectangleHeightMode. Options are ''proportional'' or ''constant''.');
end

 % Set minimum alpha value
if ~exist('MinAlpha', 'var') || isempty(MinAlpha)
    min_alpha = 0.3; % Adjust this value as needed to improve visibility
else
    min_alpha = MinAlpha;
end

% Second pass: Plotting
for idx = 1:numSets

    % Adjust axes position to use the maximum required width
    left = 0.1 + (idx - 1) * (main_ax_width + subplot_spacing);
    ax_position = [left, 0.25, main_ax_width, 0.65]; % Adjusted bottom and height

    axes_handles{idx} = axes('Position', ax_position);
    main_ax = axes_handles{idx};
    hold(main_ax, 'on');

    % Processing data
    FeaturesSet = Features{idx};
    ScoresSet = Scores{idx};
    ClassNamesSet = ClassNames{idx};
    DomainNameset = DomainNames{idx};

    % Replace underscores with spaces in feature descriptions
    FeaturesSet = strrep(FeaturesSet, '_', ' ');

    FeaturesSet = FeaturesSet(:);
    ScoresSet = ScoresSet(:);

    % Determine FaceColors based on sign
    FaceColors = zeros(length(ScoresSet), 3);
    for i = 1:length(ScoresSet)
        if ScoresSet(i) >= 0
            FaceColors(i, :) = rgb_pos; % Red
        else
            FaceColors(i, :) = rgb_neg; % Blue
        end
    end

    % Compute widths based on absolute score values
    Widths = abs(ScoresSet);
    %scaling_factor = 10 / max_abs_score; % Scale to a maximum width of 10
    %Widths = Widths * scaling_factor;

    % Sorting features based on user options
    switch lower(SortBy)
        case 'absolute'
            SortValues = abs(ScoresSet);
        case 'original'
            SortValues = ScoresSet;
        otherwise
            error('Invalid SortBy option. Choose ''absolute'' or ''original''.');
    end

    switch lower(Order)
        case 'ascending'
            [~, sortIdx] = sort(SortValues, 'ascend');
        case 'descending'
            [~, sortIdx] = sort(SortValues, 'descend');
        otherwise
            error('Invalid Order option. Choose ''ascending'' or ''descending''.');
    end

    % Apply sorting
    FeaturesSet = FeaturesSet(sortIdx);
    FaceColors = FaceColors(sortIdx, :);
    ScoresSet = ScoresSet(sortIdx);
    Widths = Widths(sortIdx);

    % Calculate AlphaValues
    AlphaValues = zeros(size(ScoresSet));
    for i = 1:length(ScoresSet)
        score_abs = abs(ScoresSet(i));
        if score_abs >= HoldOutRange(2)
            AlphaValues(i) = min_alpha + (1 - min_alpha) * (score_abs - HoldOutRange(2)) / (max_abs_score - HoldOutRange(2));
        else
            AlphaValues(i) = 0; % Fully transparent if within HoldOutRange
        end
        AlphaValues(i) = max(0, min(1, AlphaValues(i)));
    end

    % Determine rectangle heights and y-positions
    numFeatures = length(FeaturesSet);
    if strcmp(RectangleHeightMode, 'constant')
        rect_height = 1;
        y_positions = (numFeatures - (1:numFeatures)) * rect_height;
        y_positions = y_positions + (max_nFeatures - numFeatures) * rect_height; % Align to top
    else % 'proportional'
        rect_height = total_height / numFeatures;
        y_positions = total_height - (1:numFeatures) * rect_height;
    end

    % 1) Set axis limits & lines before computing offsets
    xlim(main_ax, [0, max_required_width]);
    if HoldOutRange(2) > 0
        xline(main_ax, HoldOutRange(2), ':', 'Color', 'k');
    end
    if strcmp(RectangleHeightMode, 'constant')
        ylim(main_ax, [0, max_nFeatures * rect_height]);
    else % 'proportional'
        ylim(main_ax, [0, total_height]);
    end

    % 2) Compute a fixed pixel-based offset into data units
    oldUnits = main_ax.Units;
    main_ax.Units = 'pixels';
    axPosPx = main_ax.Position;            % [x y width height] in px
    main_ax.Units = oldUnits;
    ppdu = axPosPx(3) / diff(main_ax.XLim); % px per data unit
    offsetPx = 2;                          % 5 px constant gap
    offsetData = offsetPx / ppdu;          % convert to data units

    % Reference width for deciding inside vs outside text
    refWidth = max_required_width * 0.5;

    % 3) Draw rectangles and place text
    textHandles = zeros(1,numFeatures);
    for idxFeature = 1:numFeatures
        y_position = y_positions(idxFeature);
        width = Widths(idxFeature);
        if isnan(width), continue; end
        x_position = 0;

        % Draw bar
        rectangle(main_ax, 'Position', [x_position, y_position, width, rect_height], ...
            'FaceColor', FaceColors(idxFeature,:), 'EdgeColor', [0.5,0.5,0.5], 'FaceAlpha', AlphaValues(idxFeature));

        % Brightness for text color decision
        FinalColor = AlphaValues(idxFeature)*FaceColors(idxFeature,:) + (1-AlphaValues(idxFeature))*[1,1,1];
        Brightness = 0.299*FinalColor(1) + 0.587*FinalColor(2) + 0.114*FinalColor(3);

        % Determine text X based on fixed offset
        if width < refWidth
            textX = x_position + width + offsetData;
            alignment = 'left'; TextColor = [0,0,0];
        else
            textX = x_position + width - offsetData;
            alignment = 'right';
            TextColor = (Brightness<0.5)*[1,1,1] + (Brightness>=0.5)*[0,0,0];
        end

        % Place text at center vertically
        textY = y_position + rect_height/2;
        textHandles(idxFeature) = text(main_ax, textX, textY, strtrim(FeaturesSet{idxFeature}), ...
            'Units','data','HorizontalAlignment',alignment,'VerticalAlignment','middle', ...
            'FontSize',fontSize,'FontWeight','normal','Color',TextColor,'Clipping','on', 'Margin', 0.001);
    end
    % extents    = arrayfun(@(h)get(h,'Extent'), textHandles, 'UniformOutput', false);
    % maxLabelX  = max(cellfun(@(e)e(1)+e(3), extents));
    % origBarMax = max(Widths);
    % desiredMax = max_abs_score;
    % 
    % if maxLabelX <= desiredMax
    %     newXmax = desiredMax;
    %     % Apply final x-axis limits
    %     xlim(main_ax, [0, newXmax]);
    % else
    %     % Allow bars to shrink
    %     shrinkFloor = 0.8;
    %     capX = origBarMax / shrinkFloor;
    %     % Try extending to fit labels
    %     newXmax = maxLabelX + 0.1;
    %     % Apply final x-axis limits
    %     xlim(main_ax, [0, newXmax]);
    % 
    %     if newXmax > capX
    %         newXmax = capX;
    %         % Truncate any labels that still overhang
    %         for h = textHandles(:)'
    %             ext = get(h,'Extent');
    %             if ext(1) + ext(2) > newXmax
    %                 strOrig = get(h,'String');
    %                 avail   = newXmax - ext(1);
    %                 fullW   = ext(3);
    %                 % Estimate chars to fit, keep at least 3
    %                 frac     = avail / fullW;
    %                 minChars = min(3, numel(strOrig));
    %                 estChars = max(floor(frac * numel(strOrig)), minChars);
    %                 newStr   = [strOrig(1:estChars) '…'];
    %                 set(h,'String', newStr);
    %             end
    %         end
    %     end
    % end
    % 
    % % Remove any x-ticks beyond the original max score
    % xt = get(main_ax,'XTick');
    % xt(xt>max_abs_score) = [];
    % set(main_ax,'XTick',xt);

    if HoldOutRange(2) > 0
        xline(main_ax, HoldOutRange(2), ':', 'Color', 'k');
    end
    if strcmp(RectangleHeightMode, 'constant')
        ylim(main_ax, [0, max_nFeatures * rect_height]);
    else % 'proportional'
        ylim(main_ax, [0, total_height]);
    end

    % Show x-axis, hide y-axis
    set(main_ax, 'YColor', 'none', 'TickLength', [0 0], 'YTick', []);
    set(main_ax, 'XAxisLocation', 'bottom');
    
    % Set x-axis ticks and labels
    set(main_ax, 'FontSize', fontSize);

    % Add title
    title_handle = title(main_ax, DomainNameset, 'FontSize', fontSize + 2);

    % Set 'ActivePositionProperty' to prevent resizing
    set(main_ax, 'ActivePositionProperty', 'position');

    % Create legend within the main axes
    p1 = plot(main_ax, NaN, NaN, 's', 'MarkerFaceColor', [1, 0, 0], 'MarkerEdgeColor', [0.5, 0.5, 0.5]);
    p2 = plot(main_ax, NaN, NaN, 's', 'MarkerFaceColor', [0, 0, 1], 'MarkerEdgeColor', [0.5, 0.5, 0.5]);

    legend_handle = legend(main_ax, [p1, p2], ClassNamesSet, 'Orientation', 'horizontal');

    % Set legend text color to black
    set(legend_handle, 'TextColor', 'black');
    % Optionally adjust font size and weight
    set(legend_handle, 'FontSize', fontSize, 'FontWeight', 'normal');

    % Manually position the legend
    set(legend_handle, 'Units', 'normalized');
    legend_position = get(legend_handle, 'Position');
    legend_width = legend_position(3);
    legend_height = legend_position(4);

    % Position the legend below the axes, without affecting the axes size
    legend_left = ax_position(1) + (ax_position(3) - legend_width) / 2;
    legend_bottom = ax_position(2) - legend_height - 0.02; % Added extra space
    set(legend_handle, 'Position', [legend_left, legend_bottom, legend_width, legend_height]);

    % Ensure the legend does not resize the axes
    set(main_ax, 'ActivePositionProperty', 'position');

    % Hide the placeholder plots from the figure
    set(p1, 'Visible', 'off');
    set(p2, 'Visible', 'off');

    main_ax.Color = rgb_back; 
end

% Create a common colorbar as a single image object
cb_ax = axes('Position', [0.90, axes_handles{end}.Position(2), 0.02, axes_handles{end}.Position(4)]);
hold(cb_ax, 'on');
ylim(cb_ax, [ColorbarRange(1), ColorbarRange(2)]);
xlim(cb_ax, [0, 1]);
cb_ax.XAxis.Visible = 'off';
cb_ax.YAxisLocation = 'right';
set(cb_ax, 'YDir', 'normal');

% Colorbar data
n = 512;
scores = linspace(ColorbarRange(1), ColorbarRange(2), n)';

% Initialize colorbar image and alpha data
colorbarImage = zeros(n, 1, 3);
alphaData = zeros(n, 1);

for i = 1:n
    score = scores(i);
    score_abs = abs(score);
    if score_abs >= HoldOutRange(1) && score_abs <= HoldOutRange(2)
        % Within HoldOutRange: gray color
        alpha = 1;
        color = [0.7, 0.7, 0.7]; % Gray
    else
        alpha = min_alpha + (1 - min_alpha) * (score_abs - HoldOutRange(2)) / (max_abs_score - HoldOutRange(2));
        alpha = max(0, min(1, alpha));
        if score >= 0
            color = rgb_pos; 
        else
            color = rgb_neg; 
        end
    end
    colorbarImage(i, 1, :) = color;
    alphaData(i, 1) = alpha;
end

% Display the colorbar image
hImage = image(cb_ax, [0, 1], [ColorbarRange(1), ColorbarRange(2)], colorbarImage);
set(hImage, 'AlphaData', alphaData, 'HitTest', 'on', 'PickableParts', 'all');

% Adjust axes
ylim(cb_ax, [ColorbarRange(1), ColorbarRange(2)]);
xlim(cb_ax, [0, 1]);
cb_ax.XAxis.Visible = 'off';
cb_ax.YAxisLocation = 'right';

% Remove axes visibility but keep y-axis labels
set(cb_ax, 'Box', 'off', 'XColor', 'none');
set(cb_ax.YAxis, 'Visible', 'on');

% Set colorbar ticks and labels at integer values
colorbar_ticks = ColorbarRange(1):1:ColorbarRange(2);
colorbar_tick_labels = arrayfun(@(x) sprintf('%d', x), colorbar_ticks, 'UniformOutput', false);

set(cb_ax, 'YTick', colorbar_ticks, 'YTickLabel', colorbar_tick_labels, 'FontSize', fontSize);
ylabel(cb_ax, ScoreName, 'FontSize', fontSize, 'FontWeight','bold');

end

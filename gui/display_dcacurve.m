function display_dcacurve(y_true, y_probs, y_true_oocv, y_probs_oocv, titlestr)

    % Calculate initial max probability (training only)
    initialMaxProb = findInitialMaxProbability(y_true, y_probs);

    screenSize = get(0, 'ScreenSize');
    figWidth = screenSize(3) / 2;
    figHeight = screenSize(4) / 2;
    figX = (screenSize(3) - figWidth) / 2;
    figY = (screenSize(4) - figHeight) / 2;

    % Create figure
    f = figure('Name', 'Interactive Decision Curve Analysis', 'NumberTitle', 'off',...
               'Units', 'pixels', 'Position', [figX, figY, figWidth, figHeight]);

    % Control panel
    controlPanel = uipanel(f, 'Units', 'normalized', 'Position', [0.05 0.02 0.9 0.1]);
    hMaxProbText = uicontrol(controlPanel, 'Style', 'text', 'Units', 'normalized',...
                             'Position', [0.02, 0.26, 0.2, 0.35],...
                             'String', sprintf('Max Prob: %.2f', initialMaxProb), 'HorizontalAlignment','left');
    hMaxProb = uicontrol(controlPanel, 'Style', 'slider', 'Units', 'normalized',...
                         'Position', [0.2, 0.25, 0.25, 0.47],...
                         'Min', 0.1, 'Max', 1, 'Value', initialMaxProb, 'Callback', @(es,ed) updatePlot());
    stepSizeInitial = 0.05;
    hStepSizeText = uicontrol(controlPanel, 'Style', 'text', 'Units', 'normalized',...
                              'Position', [0.52, 0.26, 0.15, 0.35],...
                              'String', sprintf('Step Size: %.2f', stepSizeInitial), 'HorizontalAlignment','left');
    hStepSize = uicontrol(controlPanel, 'Style', 'slider', 'Units', 'normalized',...
                          'Position', [0.70, 0.25, 0.25, 0.47],...
                          'Min', 0.01, 'Max', 0.1, 'Value', stepSizeInitial, 'Callback', @(es,ed) updatePlot());

    % Axes for plot
    ax = axes(f, 'Units', 'normalized', 'Position', [0.1 0.25 0.85 0.7]);

    % Initial plot
    updatePlot();

    %=== findInitialMaxProbability ===%
    function initialMaxProb = findInitialMaxProbability(y_true, y_probs)
        stepSize = 0.01;
        maxProb = 1;
        [thresholds, netBenefits] = nk_DCA(y_true, y_probs, maxProb, stepSize);
        idxPosNB = find(netBenefits > 0);
        if ~isempty(idxPosNB)
            initialMaxProb = thresholds(max(idxPosNB));
        else
            initialMaxProb = maxProb;
        end
    end

    %=== updatePlot ===%
    function updatePlot()
        maxProb = get(hMaxProb, 'Value');
        stepSize = get(hStepSize, 'Value');
        set(hMaxProbText, 'String', sprintf('Max Prob: %.2f', maxProb));
        set(hStepSizeText, 'String', sprintf('Step Size: %.2f', stepSize));
        cla(ax);

        %--- Training data curves ---%
        [thr_tr, nb_tr, ta_tr, tn_tr] = nk_DCA(y_true, y_probs, maxProb, stepSize);
        plot(ax, thr_tr, nb_tr,   'b-',  'LineWidth', 2, 'DisplayName', 'Model (Train)');
        hold(ax, 'on');
        plot(ax, thr_tr, ta_tr,   'r--', 'LineWidth', 1.5, 'DisplayName', 'Treat All (Train)');
        plot(ax, thr_tr, tn_tr,   'k:',  'LineWidth', 1.5, 'DisplayName', 'Treat None (Train)');

        %--- OOCV data curves, if provided ---%
        if ~isempty(y_true_oocv) && ~isempty(y_probs_oocv)
            [thr_ooc, nb_ooc, ta_ooc, tn_ooc] = nk_DCA(y_true_oocv, y_probs_oocv, maxProb, stepSize);
            plot(ax, thr_ooc, nb_ooc, 'g-',  'LineWidth', 2, 'DisplayName', 'Model (OOCV)');
            plot(ax, thr_ooc, ta_ooc, 'm--', 'LineWidth', 1.5, 'DisplayName', 'Treat All (OOCV)');
            plot(ax, thr_ooc, tn_ooc, 'c:',  'LineWidth', 1.5, 'DisplayName', 'Treat None (OOCV)');
        end

        %--- Adjust y-limits dynamically, robust to constant/NaN data ---%
        allY = [nb_tr; ta_tr; tn_tr];
        if exist('nb_ooc','var')
            allY = [allY; nb_ooc; ta_ooc; tn_ooc];
        end
        % remove NaNs
        allY = allY(~isnan(allY));
        if isempty(allY)
            % no data—leave the default limits
        else
            yMin = min(allY) * 1.05;
            yMax = max(allY) * 1.05;
            if yMin >= yMax
                % all values the same—create a small buffer
                mid = mean(allY);
                delta = max(abs(mid)*0.05, 0.01);
                yMin = mid - delta;
                yMax = mid + delta;
            end
            ylim(ax, [yMin, yMax]);
        end

        %--- Final touches ---%
        box(ax, 'on');
        xlabel(ax, 'Probability Threshold');
        ylabel(ax, 'Net Benefit');
        title(ax, titlestr, 'Interpreter', 'none');
        legend(ax, 'Location', 'best');
    end

end

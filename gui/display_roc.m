% =========================================================================
% =                          ROC ANALYSIS                                 =
% =========================================================================
function [hroc, hroc_train, hroc_random] = display_roc( ...
        handles, ...
        targets, predictions, ...
        targets_train, predictions_train, ...
        axeshdl, clafl, linewidth)

    % Default argument handling
    if nargin < 8 || isempty(linewidth)
        linewidth = 2;
    end
    if nargin < 6 || isempty(clafl)
        clafl = true;
    end
    if nargin < 5
        predictions_train = [];
    end
    if nargin < 4
        targets_train = [];
    end
    if nargin < 7 || isempty(axeshdl)
        axeshdl = 'axes2';
    end

    % Transparency levels
    alpha_train = 0.1;   % very faint fill for training ROC
    alpha_main  = 0.20;   % stronger fill for main ROC

    % Prepare axes
    axes(handles.(axeshdl));
    if clafl
        cla(handles.(axeshdl));
    end
    hold(handles.(axeshdl), 'on');
    set(handles.(axeshdl), ...
        'XLim',  [0 1], ...
        'YLim',  [0 1], ...
        'XTick', 0:0.2:1, ...
        'YTick', 0:0.2:1);

    %----------------------------------------------------------------------
    % 1) Plot training‐set ROC curves, if provided
    %----------------------------------------------------------------------
    hroc_train = [];
    if ~isempty(targets_train)
        numTrainingClasses = size(targets_train, 2);
        hroc_train = zeros(1,numTrainingClasses);
        auc_train   = zeros(1,numTrainingClasses);
        for c = 1:numTrainingClasses
            % compute & plot
            [h_line, thisAUC] = plot_one_roc_with_auc( ...
                handles.(axeshdl), ...
                targets_train(:,c),     ...
                predictions_train(:,c), ...
                0.8,        ...  % fill gray
                alpha_train,...
                '-', ...
                [0.4 0.4 0.4], ...
                1);
            hroc_train(c) = h_line;
            auc_train(c)  = thisAUC;
        end
    end

    %----------------------------------------------------------------------
    % 2) Plot main ROC curves (test or held‐out data)
    %----------------------------------------------------------------------
    hroc = [];
    if ~isempty(targets)
        numTestClasses = size(targets, 2);
        hroc      = zeros(1,numTestClasses);
        auc_test  = zeros(1,numTestClasses);
        for c = 1:numTestClasses
            % choose colors (multi–class vs. single)
            if numTestClasses>1
                lc = handles.colptin(c,:);
                fc = handles.colptin(c,:);
            else
                lc = 'k';
                fc = 0.7;   % will become [0.7 0.7 0.7]
            end

            [h_line, thisAUC] = plot_one_roc_with_auc( ...
                handles.(axeshdl), ...
                targets(:,c),         ...
                predictions(:,c),     ...
                fc,         ...  % fill gray or class color
                alpha_main, ...
                '-',        ...  % solid line
                lc,         ...
                linewidth);

            hroc(c)    = h_line;   
            auc_test(c)= thisAUC;   
        end

    else
        %------------------------------------------------------------------
        % Classification/regression branches when no explicit targets
        %------------------------------------------------------------------
        if strcmp(handles.modeflag, 'classification')
            selectedClassIndex = get(handles.popupmenu1, 'Value');
            classList          = get(handles.popupmenu1, 'String');
            oneVsAllSelection  = get(handles.selOneVsAll_Info, 'Value');

            if strcmpi(classList{selectedClassIndex}, 'Multi-group classifier')
                numGroups = handles.ngroups;
                for groupIndex = 1:numGroups
                    if oneVsAllSelection == 1
                        patchColor = handles.colptin(groupIndex, :);
                        curClass   = groupIndex;
                    else
                        patchColor = handles.colptin(oneVsAllSelection - 1, :);
                        curClass   = oneVsAllSelection - 1;
                    end
                    Xgroup = handles.MultiClass.X{curClass};
                    Ygroup = handles.MultiClass.Y{curClass};

                    % Fill under multi‐class ROC
                    patch( ...
                        'XData',    [Xgroup; flipud(Xgroup)], ...
                        'YData',    [Ygroup; flipud(Xgroup)], ...
                        'FaceColor', patchColor, ...
                        'EdgeColor','none', ...
                        'FaceAlpha',alpha_main, ...
                        'Parent',   handles.(axeshdl));

                    % Plot multi‐class ROC line
                    hroc(groupIndex) = plot( ...
                        handles.(axeshdl), ...
                        Xgroup, Ygroup, ...
                        'Color',    patchColor, ...
                        'LineWidth',linewidth);
                end

            else
                Xbinary = handles.BinClass{selectedClassIndex}.X;
                Ybinary = handles.BinClass{selectedClassIndex}.Y;

                % Fill under binary‐class ROC
                patch( ...
                    'XData',    [Xbinary; flipud(Xbinary)], ...
                    'YData',    [Ybinary; flipud(Xbinary)], ...
                    'FaceColor', [0.7 0.7 0.7], ...
                    'EdgeColor','none', ...
                    'FaceAlpha',alpha_main, ...
                    'Parent',   handles.(axeshdl));

                % Plot binary‐class ROC line
                hroc = plot( ...
                    handles.(axeshdl), ...
                    Xbinary, Ybinary, ...
                    'Color',    'k', ...
                    'LineWidth',linewidth);
            end

        else
            % Regression branch
            Xregression = handles.curRegr.X;
            Yregression = handles.curRegr.Y;

            % Fill under regression "ROC"
            patch( ...
                'XData',    [Xregression; flipud(Xregression)], ...
                'YData',    [Yregression; flipud(Xregression)], ...
                'FaceColor', [0.7 0.7 0.7], ...
                'EdgeColor','none', ...
                'FaceAlpha',alpha_main, ...
                'Parent',   handles.(axeshdl));

            % Plot regression "ROC" line
            hroc = plot( ...
                handles.(axeshdl), ...
                Xregression, Yregression, ...
                'Color',    'k', ...
                'LineWidth',linewidth);
        end
    end

    %----------------------------------------------------------------------
    % 3) Plot diagonal reference line
    %----------------------------------------------------------------------
    hroc_random = plot( ...
        handles.(axeshdl), ...
        [0 1], [0 1], ...
        'Color', [0.5 0.5 0.5]);

    % 4) SIGNIFICANCE TEST & LEGEND (if TRAIN exists)
    %----------------------------------------
    if ~isempty(targets_train)
        p_values = zeros(size(auc_train));
        for c = 1:numel(auc_train)
            % counts of positives/negatives
            pos_train = nnz(targets_train(:,c)==1);
            neg_train = nnz(targets_train(:,c)==-1);
            pos_test  = nnz(targets(:,c)==1);
            neg_test  = nnz(targets(:,c)==-1);

            % Hanley & McNeil variances
            [se_tr] = auc_se_hanley(auc_train(c), pos_train, neg_train);
            [se_te] = auc_se_hanley(auc_test(c),  pos_test,  neg_test);
            se_diff = sqrt(se_tr^2 + se_te^2);

            z = (auc_test(c) - auc_train(c)) / se_diff;
            p_values(c) = erfc(abs(z)/sqrt(2));  % two-tailed
        end

        % assemble legend entries
        legendEntries = cell(1,numel(auc_train));
        for c = 1:numel(auc_train)
             legendEntries{c} = sprintf( [ ...
                                    'Class %d:\n'       , ...
                                    'AUC-diff = %.3f\n', ...
                                    'P value = %.3f'   ], ...
                                    c, auc_test(c)-auc_train(c), p_values(c) );
        end
        legend(handles.(axeshdl), hroc, legendEntries, 'Location','SouthEast','FontSize',6,'LineWidth',0.5);
    end


    %----------------------------------------------------------------------
    % 5) Labels and styling
    %----------------------------------------------------------------------
    ax = handles.(axeshdl);
    xlabel(ax, 'False positive rate', 'FontWeight', handles.RocAxisLabelWeight);
    ylabel(ax, 'True positive rate', 'FontWeight', handles.RocAxisLabelWeight);


end

% ----------------------------------------------------------------------------
% Helper function: compute ROC, fill area, plot curve, and return line handle
% ----------------------------------------------------------------------------
function [lineHandle, aucValue]  = plot_one_roc_with_auc( ...
        axisHandle, ...
        targetsVector, ...
        predictionVector, ...
        patchGrayValue, ...
        patchAlphaValue, ...
        lineStyleString, ...
        lineColorValue, ...
        lineWidthValue)

    % Compute ROC curve
    [Xvalues, Yvalues,~, aucValue] = perfcurve2(targetsVector, predictionVector, 1);

    % Build polygon to fill between ROC and diagonal
    xv = [Xvalues; flipud(Xvalues)];
    yv = [Yvalues; flipud(Xvalues)];
    
     % Convert scalar gray to RGB triplet if needed
    if isscalar(patchGrayValue)
        faceColor = repmat(patchGrayValue,1,3);
    else
        faceColor = patchGrayValue;
    end

    % Draw filled area
    patch( ...
        'XData',    xv, ...
        'YData',    yv, ...
        'FaceColor',faceColor, ...
        'EdgeColor','none', ...
        'FaceAlpha',patchAlphaValue, ...
        'Parent',   axisHandle);

    % Plot ROC curve line
    lineHandle = plot( ...
        axisHandle, ...
        Xvalues, Yvalues, ...
        'LineStyle',  lineStyleString, ...
        'Color',      lineColorValue, ...
        'LineWidth',  lineWidthValue);

end

% ----------------------------------------------------------------------------
% Hanley & McNeil approximate standard error of an AUC
% ----------------------------------------------------------------------------
function se = auc_se_hanley(auc, npos, nneg)
    Q1 = auc / (2 - auc);
    Q2 = 2*auc^2 / (1 + auc);
    var_auc = ( ...
        auc*(1-auc) + ...
        (npos-1)*(Q1 - auc^2) + ...
        (nneg-1)*(Q2 - auc^2) ...
    ) / (npos * nneg);
    se = sqrt(var_auc);
end
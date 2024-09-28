% =========================================================================
% =                   CONTINGENCY MATRIX INFO                             = 
% =========================================================================
function handles = display_contigmat(handles, contigmat)

contig = {};

% Define a fixed-width format for the numbers
formatSpec = '%-23s %s';

GraphType = get(handles.selYaxis,'Value');

if ~exist('contigmat','var') || isempty(contigmat)
    
    switch handles.modeflag

        case 'regression'

            contig{end+1} = sprintf(formatSpec, '\bf R^2 [%]: \rm', sprintf(' %.1f', handles.curRegr.R2(handles.curlabel)));
            contig{end+1} = sprintf(formatSpec, '\bf r (95%-CI): \rm', sprintf('%.2f (%.2f-%.2f)', handles.curRegr.r(handles.curlabel), handles.curRegr.r_95CI_low(handles.curlabel), handles.curRegr.r_95CI_up(handles.curlabel)));
            contig{end+1} = sprintf(formatSpec, '\bf P(T) value: \rm', sprintf('%.3f (%.2f)', handles.curRegr.p(handles.curlabel), handles.curRegr.t(handles.curlabel)));
            contig{end+1} = sprintf(formatSpec, '\bf MAE: \rm', sprintf('%.1f', handles.curRegr.MAE(handles.curlabel)));
            contig{end+1} = sprintf(formatSpec, '\bf MSE: \rm', sprintf('%.1f', handles.curRegr.MSE(handles.curlabel)));
            contig{end+1} = sprintf(formatSpec, '\bf NRMSD [%]: \rm', sprintf('%.1f', handles.curRegr.NRSMD(handles.curlabel)));
            contigmat = handles.curRegr.contigmat;

        case 'classification'
            
            h_class  = get(handles.popupmenu1,'Value');
            h_onevsall_val  = get(handles.selOneVsAll_Info,'Value');
            h_classlist     = get(handles.popupmenu1,'String');
            if strcmpi(h_classlist{h_class},'Multi-group classifier') && h_onevsall_val > 1
                contigmat = handles.MultiClass.class{h_onevsall_val-1};
            else
                switch GraphType
                    case {4,5,6}
                         contigmat = handles.BinClass{h_class}.prob_contingency;
                    otherwise
                        contigmat = handles.BinClass{h_class}.contingency;
                end
            end
    end
end
% Add formatted strings to the contig cell array using sprintf
contig{end+1} = sprintf(formatSpec, '\bf TP / TN:\rm', sprintf('%d / %d', contigmat.TP, contigmat.TN));
contig{end+1} = sprintf(formatSpec, '\bf FP / FN:\rm', sprintf('%d / %d', contigmat.FP, contigmat.FN));
contig{end+1} = sprintf(formatSpec, '\bf Accuracy [%]:\rm', sprintf('%.1f', contigmat.acc));
contig{end+1} = sprintf(formatSpec, '\bf Sensitivity [%]:\rm', sprintf('%.1f', contigmat.sens));
contig{end+1} = sprintf(formatSpec, '\bf Specificity [%]:\rm', sprintf('%.1f', contigmat.spec));
contig{end+1} = sprintf(formatSpec, '\bf BAC [%]:\rm', sprintf('%.1f', contigmat.BAC));

if isfield(contigmat, 'AUC') && isfield(contigmat, 'AUC_lower')
    contig{end+1} = sprintf(formatSpec, '\bf AUC (95%-CI):\rm', sprintf('%.2f (%.2f-%.2f)', ...
        contigmat.AUC, contigmat.AUC_lower, contigmat.AUC_upper));
elseif isfield(contigmat, 'AUC')
    contig{end+1} = sprintf(formatSpec, '\bf AUC:\rm', sprintf('%.2f', contigmat.AUC));
end

contig{end+1} = sprintf(formatSpec, '\bf MCC:\rm', sprintf('%.2f', contigmat.MCC));
contig{end+1} = sprintf(formatSpec, '\bf PPV [%]:\rm', sprintf('%.1f', contigmat.PPV));
contig{end+1} = sprintf(formatSpec, '\bf NPV [%]:\rm', sprintf('%.1f', contigmat.NPV));
contig{end+1} = sprintf(formatSpec, '\bf FPR:\rm', sprintf('%.1f', contigmat.FPR));
contig{end+1} = sprintf(formatSpec, '\bf +LR:\rm', sprintf('%.2f', contigmat.pLR));
contig{end+1} = sprintf(formatSpec, '\bf -LR:\rm', sprintf('%.2f', contigmat.nLR));
contig{end+1} = sprintf(formatSpec, '\bf PSI:\rm', sprintf('%.1f', contigmat.PSI));
contig{end+1} = sprintf(formatSpec, '\bf Youden''s J:\rm', sprintf('%.2f', contigmat.Youden));
contig{end+1} = sprintf(formatSpec, '\bf NNP / NND:\rm', sprintf('%.1f / %.1f', contigmat.NNP, contigmat.NND));
contig{end+1} = sprintf(formatSpec, '\bf DOR:\rm', sprintf('%.2f', contigmat.DOR));

% Combine all the strings into one multiline string using newline characters
contig_str = strjoin(contig, '\n');

if isfield(contigmat,'ECE') && handles.calibflag
    contig{end+1} = sprintf(formatSpec, '\bf ECE:\rm', sprintf('%.2f', contigmat.ECE));
    sta = 0.49;
    stp = 0.48;
else
    sta = 0.49;
    stp = 0.45;
end
if isfield(handles,'PermAnal')
    contig{end+1} = sprintf(formatSpec, '\bf Model P value:\rm', sprintf('%.3f', handles.PermAnal));
end

switch handles.modeflag
    case 'classification'
        y_start = sta;
        y_height = stp;
    case 'regression'
        y_start = 0.39;
        y_height = 0.58;
end

cla(handles.axes5);
delete(findall(handles.figure1,'Tag','AnnotPerfMeas'))

% Calculate the number of lines in the text
numLines = numel(contig);

% Get the height of the target annotation box
targetBoxHeight = handles.axes20.Position(4) + y_height;

% Define the initial font size and minimum font size
initialFontSize = 0.018;
minFontSize = 0.01;

% Estimate the font size based on the target box height and number of lines
% Assuming a rough average line height factor (this may need tweaking)
lineHeightFactor = 1.2; % This is an empirical value that might need adjustments
estimatedFontSize = targetBoxHeight / (numLines * lineHeightFactor);

% Ensure the estimated font size does not exceed the initial font size or go below the minimum font size
fontSize = max(min(estimatedFontSize, initialFontSize), minFontSize);

% Display the formatted text using annotation with the adjusted font size
handles.txtPerf = annotation(handles.pnContigCmds, ...
                        'textbox', [handles.axes20.Position(1)-0.15, y_start, handles.axes20.Position(3)+0.15, y_height], ...
                        'String', contig_str, ...
                        'FitBoxToText', 'off', ...
                        'FontUnits', 'normalized', ...
                        'FontName', 'Consolas', ... 
                        'FontSize', fontSize, ...
                        'Margin', 5, ...
                        'Units', 'normalized', ...
                        'LineWidth', 1.5, ...
                        'HorizontalAlignment', 'left', ...
                        'Tag', 'AnnotPerfMeas', ...
                        'Interpreter', 'tex');

end
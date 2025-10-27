% =========================================================================
% =                   CONTINGENCY MATRIX INFO                             =
% =========================================================================
function handles = display_contigmat(handles, contigmat)

    %% 1) Build labels & values (always in parallel)
    labels = {};
    values = {};
    cla(handles.axes5);
    GraphType = get(handles.selYaxis,'Value');
    
    if ~exist('contigmat','var') || isempty(contigmat)
        
        switch handles.modeflag
    
            case 'regression'
    
                labels{end+1} = 'R^2 [%]:';         values{end+1} = sprintf('%.1f', handles.curRegr.R2(handles.curlabel));
                labels{end+1} = 'r (95%-CI):';      values{end+1} = sprintf('%.2f (%.2f-%.2f)', handles.curRegr.r(handles.curlabel), ...
                                                            handles.curRegr.r_95CI_low(handles.curlabel), handles.curRegr.r_95CI_up(handles.curlabel));
                labels{end+1} = 'P(T) value:';      values{end+1} = sprintf('%.3f (%.2f)', handles.curRegr.p(handles.curlabel), handles.curRegr.t(handles.curlabel));
                labels{end+1} = 'MAE:';             values{end+1} = sprintf('%.1f', handles.curRegr.MAE(handles.curlabel));
                labels{end+1} = 'MSE:';             values{end+1} = sprintf('%.1f', handles.curRegr.MSE(handles.curlabel));
                labels{end+1} = 'NRMSD [%]:';       values{end+1} = sprintf('%.1f', handles.curRegr.NRSMD(handles.curlabel));
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

    % Mandatory binary‐classification fields
    labels{end+1} = 'TP / TN:';         values{end+1} = sprintf('%d / %d', contigmat.TP,  contigmat.TN);
    labels{end+1} = 'FP / FN:';         values{end+1} = sprintf('%d / %d', contigmat.FP,  contigmat.FN);
    labels{end+1} = 'Accuracy [%]:';    values{end+1} = sprintf('%.1f',   contigmat.acc);
    labels{end+1} = 'Sensitivity [%]:'; values{end+1} = sprintf('%.1f', contigmat.sens);
    labels{end+1} = 'Specificity [%]:'; values{end+1} = sprintf('%.1f', contigmat.spec);
    labels{end+1} = 'BAC [%]:';         values{end+1} = sprintf('%.1f', contigmat.BAC);

    % Optional AUC
    if isfield(contigmat,'AUC')
        if isfield(contigmat,'AUC_lower')
            labels{end+1} = 'AUC (95%-CI):';
            values{end+1} = sprintf('%.2f (%.2f-%.2f)', ...
                contigmat.AUC, contigmat.AUC_lower, contigmat.AUC_upper);
        else
            labels{end+1} = 'AUC:';
            values{end+1} = sprintf('%.2f', contigmat.AUC);
        end
    end

    % Other metrics
    labels{end+1} = 'MCC:';         values{end+1} = sprintf('%.2f', contigmat.MCC);
    labels{end+1} = 'PPV [%]:';     values{end+1} = sprintf('%.1f', contigmat.PPV);
    labels{end+1} = 'NPV [%]:';     values{end+1} = sprintf('%.1f', contigmat.NPV);
    labels{end+1} = 'FPR:';         values{end+1} = sprintf('%.1f', contigmat.FPR);
    labels{end+1} = '+LR:';         values{end+1} = sprintf('%.2f', contigmat.pLR);
    labels{end+1} = '-LR:';         values{end+1} = sprintf('%.2f', contigmat.nLR);
    labels{end+1} = 'PSI:';         values{end+1} = sprintf('%.1f', contigmat.PSI);
    labels{end+1} = 'Youden''s J:'; values{end+1} = sprintf('%.2f', contigmat.Youden);
    labels{end+1} = 'NNP / NND:';   values{end+1} = sprintf('%.1f / %.1f', contigmat.NNP, contigmat.NND);
    labels{end+1} = 'DOR:';         values{end+1} = sprintf('%.2f', contigmat.DOR);

    % Optional ECE
    if isfield(contigmat,'ECE') && handles.calibflag
        labels{end+1} = 'ECE:';      values{end+1} = sprintf('%.2f', contigmat.ECE);
    end

    % Optional permutation P‐value
    if isfield(handles,'PermAnal')
        if handles.PermAnal < 0.001
            pvStr = '<0.001';
        else
            pvStr = sprintf('%.3f', handles.PermAnal);
        end
        labels{end+1} = 'Model P value:'; values{end+1} = pvStr;
    end

    %% Build and place a uitable
    tblData = values(:);
    fullData = [labels' tblData];

    % Decide whether to use legacy HTML (pre-R2025a) or not
    useLegacyHTML = isBeforeRelease('2025a');
    
    if useLegacyHTML
        % Old behavior: HTML bold in column 1
        for i = 1:size(fullData,1)
            fullData{i,1} = ['<html><b>' fullData{i,1} '</b></html>'];
        end
    else
        % R2025a+: leave plain text (HTML shows verbatim)
        % (Optionally keep labels unchanged)
    end

    % Check if the table already exists & is valid
    if isfield(handles, 'tblPerf') && isvalid(handles.tblPerf)
        % Just update its contents
        set(handles.tblPerf, 'Data', fullData,'Visible','on');
    else
        % Create it for the first time
        handles.tblPerf = uitable( ...
            'Parent',       handles.pnContigCmds, ...
            'Data',         fullData, ...
            'RowName',      [], ...
            'ColumnName',   {'Metric', 'Value'}, ...
            'ColumnWidth',  {120,150}, ...
            'Units',        'normalized', ...
            'Position',     [0.04, 0.50, 0.84, 0.485], ...
            'FontName',     'Consolas', ...
            'FontSize',     8, ...
            'Tag',          'PerfMetricsTable' ...
        );
    end

    % Return updated handles struct
    guidata(handles.pnContigCmds, handles);

end

function tf = isBeforeRelease(targetRelease)
% Return true if current MATLAB is before targetRelease, e.g. '2025a'
cur = version('-release');     % e.g., '2024b'
tf  = compareReleases(cur, targetRelease) < 0;
end

function c = compareReleases(a, b)
% Compare 'YYYYa'/'YYYYb' strings: returns -1 if a<b, 0 if equal, 1 if a>b
ay = str2double(a(1:4)); ax = lower(a(5));
by = str2double(b(1:4)); bx = lower(b(5));
if ay ~= by
    c = sign(ay - by);
else
    % 'a' < 'b'
    order = @(ch) (ch == 'a') * 1 + (ch == 'b') * 2;
    c = sign(order(ax) - order(bx));
end
end
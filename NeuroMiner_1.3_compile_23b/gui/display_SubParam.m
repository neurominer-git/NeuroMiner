function [ handles, contfl] = display_SubParam(handles, caller)

curclass = handles.popupmenu1.Value;
if strcmp(handles.popupmenu1.String{curclass},'Multi-group classifier'), curclass=1; end
param = char(strsplit(handles.selSubParam.String{handles.selSubParam.Value},'_'));
Pind = contains( handles.ModelParamsDesc{curclass}, deblank(param(1,:)));
if size(param,1)>1
    fPind = find(Pind);
    Pind = false(1,numel(Pind)); 
    if numel(fPind)>1
        if contains(param(2,:),'{')
            idx = extractNumber(param(2,:));
        else
            idx = str2double(deblank(param(2,:)));
        end
        Pind(fPind(idx)) = true;
    else
        Pind(fPind) = true;
    end
end
contfl = true;
if ~any(Pind)
    if exist('caller','var') && ~isempty(caller)
        return
    else
        handles = display_modelperf(handles);
    end
else
    if size(handles.currmeas,2)>1
        [mPerf, sdPerf,~,bars]=extract_subparam_performance(handles.ModelParams{curclass}, ...
                            handles.currmeas, Pind, [], 1, handles.axes17);
    else
        [mPerf, sdPerf,~,bars]=extract_subparam_performance(handles.ModelParams, ...
                            handles.currmeas, Pind, curclass, 1, handles.axes17);
    end
    handles.axes17.XLabel.String = sprintf('Parameter subspace selection: %s', handles.selSubParam.String{handles.selSubParam.Value});
    if size(handles.currmeas)>1
        bars(1).FaceColor='b';
        bars(2).FaceColor='r';
        handles.legend_modelperf.String =  {'CV1 performance','CV2 performance'};
        handles.legend_modelperf.Visible='on';
    else
        bars(1).FaceColor=rgb('green');
        handles.legend_modelperf.Visible = 'off';
    end
    contfl=false;
    assignin('base', 'nm_viewer_data_mean', mPerf);
    assignin('base', 'nm_viewer_data_sd', sdPerf);
end

function number = extractNumber(inputString)
    % Define the regular expression pattern to match {M<number>}
    pattern = '\{M(\d+)\}';
    
    % Search for the pattern in the input string and extract the number
    tokens = regexp(inputString, pattern, 'tokens');
    
    % Check if tokens are found
    if ~isempty(tokens)
        % Convert the extracted number (which is a string) to a numeric value
        number = str2double(tokens{1}{1});
    else
        % Return empty if no match is found
        number = [];
    end

function param = nk_TFDEEP_config(prog, param, defaultsfl, framework)
global EXPERT
if ~exist('defaultsfl','var') || isempty(defaultsfl), defaultsfl = true; end
param.options = nk_matLearn_getopts_config([], 'get_learner_params', prog, param, framework);
ind = 1;
if ~defaultsfl
    while ~isempty(ind)
        if EXPERT
            %All. 
            [mn_str, mn_act] = nk_matLearn_BuildMenu_config(param, param.options);
            nk_PrintLogo; 
            ind = nk_input('Select parameter to modify',0,'mq',mn_str, mn_act);
            if ~ind, break; end
            [out, param] = nk_matLearn_IO_config(param.options, param, ind);
            param.Params(ind).range = out;
            param.Params(ind).name = param.options.name{ind};  
        else
            %Default to NM inputs and set files to none. 
            param.Params(end).range = 'none';
            param.options.def(end) = {'none'};

            %Show the rest of the parameters.
            nParams = length(param.Params) - 1;
            param_reduced.Params = param.Params(1:nParams);
            fields = fieldnames(param.options);
            for i=1:numel(fields)
                param_reduced.options.(fields{i}) = param.options.(fields{i})(1:nParams);
            end
            [mn_str, mn_act] = nk_matLearn_BuildMenu_config(param_reduced, param_reduced.options);
            nk_PrintLogo; 
            ind = nk_input('Select parameter to modify',0,'mq',mn_str, mn_act);
            if ~ind, break; end
            [out, param_reduced] = nk_matLearn_IO_config(param_reduced.options, param_reduced, ind);
            param.Params(ind).range = out;
            param.Params(ind).name = param_reduced.options.name{ind}; 
        end
    end
else
    for ind = 1:numel(param.options.name)
        param.Params(ind).range = param.options.def{ind};
        param.Params(ind).name = param.options.name{ind};
    end
end



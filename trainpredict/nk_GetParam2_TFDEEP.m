% ==========================================================================
% FORMAT [param, model] = nk_GetParam_TFDEEP(Y, label, SlackParam, ~, ...
%                                           ModelOnly)
% ==========================================================================
% Train TF NN models in python and evaluate their performance using Y & label, 
% SlackParam,
% if ModelOnly = 1, return only model
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Sergio Mena Ortega, 2025
function [param, model] = nk_GetParam2_TFDEEP(Y, label, ModelOnly, Param)
global MODEFL GRD EVALFUNC TENSORFLOW

param = [];

% ================= Convert to Python arrays =================
Y_py = py.numpy.array(Y).astype('float32');
label_py = py.numpy.array(reshape(label, [], 1)).astype('float32');


if length(Param)>2
%%%%%% ---- DEFAULT MODE ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % ================= Extract layer structure =================
    struc = GRD.TFDEEP.Params(1).range(Param{1}, :);
    layers_sizes = int64(struc(struc ~= 0));
    Param{1} = layers_sizes;  
    
    % ================= Adjust batch size =================
    Param{5} = min(int32(Param{5}), int32(length(label)));
    
    % ================= Layers to Python arrays =================
    if isscalar(layers_sizes)
        layers_sizes_py = py.list({int64(layers_sizes)});
    else
        layers_sizes_py = py.list(num2cell(int64(layers_sizes)));
    end
    
    % ================= Python call to train model =================
    model =TENSORFLOW.modules{1}.tf_model_fit( ...
        Y_py, ...
        label_py, ...
        layers_sizes_py, ...
        pyargs( ...
            'activation',           Param{2}, ...
            'optimizer_name',       Param{3}, ...
            'l2reg',                double(Param{4}), ...
            'lr',                   double(Param{6}), ...
            'batch_size',           int32(Param{5}), ...
            'epochs',               int32(Param{7}), ...
            'seed',                 int32(Param{8}), ...
            'class_weighting',      Param{9} == 1, ...
            'use_early_stop',       Param{10} == 1, ...
            'patience',             int32(Param{11}), ...
            'validation',           Param{13} == 1, ...
            'validation_fraction',  double(Param{14}), ...
            'loss',                 Param{12}, ...
            'NM_perf_criterion',    func2str(EVALFUNC), ...
            'task',                 MODEFL ...
        ));
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

else
%%%%%% ---- FILE MODE ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % ================= Get python module with model ===========
    module = TENSORFLOW.modules{Param};

    % ================= Python call to train model =============
    model = module.tf_model(Y_py, label_py);
end
end


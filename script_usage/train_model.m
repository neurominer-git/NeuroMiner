function NM_out = train_model(NM, analind, ovrwrtfl, CV2x1, CV2x2, CV2y1, CV2y2, preprocmaster)
% TRAIN_MODEL Performs NeuroMiner model training with given configurations
%
% This function initializes the NeuroMiner environment and executes the training
% process based on provided parameters, supporting preprocessed data.
%
% INPUTS:
%   NM              - NeuroMiner structure with data and analysis parameters.
%   analind         - Index of the analysis to be executed within NM.
%   ovrwrtfl        - Flag to overwrite previous results (1: yes, 0: no).
%   CV2x1, CV2x2    - Dimensions for the cross-validation grid (number of CV partitions).
%   CV2y1, CV2y2    - (Optional) Not used currently; reserved for potential future cross-validation settings.
%   preprocmaster   - (Optional) Filename of preprocessed data to load. If not provided, preprocessing is computed from scratch.
%
% OUTPUT:
%   NM_out - Updated NeuroMiner structure containing the trained model results.
%
% USAGE:
%   NM_out = train_model(NM, 1, 1, 10, 10);
%   NM_out = train_model(NM, 1, 0, 5, 5, [], [], 'preprocessed_data.mat');

% Initialize NeuroMiner environment
if ischar(preprocmaster) && exist(preprocmaster,'file')
    preprocmat = load(preprocmaster); lfl = 2; preprocmat = preprocmat.featmat;
else
    preprocmat = []; lfl = 1;
end

action = struct('addrootpath',1, ...
                'addDRpath',1, ...
                'addMIpath',1, ...
                'addLIBSVMpath',1, ...
                'addLIBLINpath',1, ...
                'addMikeRVMpath',1, ...
                'all',1);

nk_Initialize(action)

% Set up training parameters
inp = struct('analind', analind, ...
             'lfl', lfl, ...
             'gdmat', [], ...
             'gdanalmat', [], ...
             'varstr', [], ...
             'concatfl', [], ...
             'ovrwrt', ovrwrtfl, ...
             'update', true, ...
             'HideGridAct', false, ...
             'batchflag', false);

inp.GridAct = true(CV2x1,CV2x2);
inp.preprocmat = preprocmat;
inp = nk_GetAnalModalInfo_config(NM, inp);

% Execute NeuroMiner training
NM_out = nm_train(NM, analind, inp);

end

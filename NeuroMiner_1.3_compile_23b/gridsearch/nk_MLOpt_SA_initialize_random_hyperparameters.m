function [config, config_desc] = nk_MLOpt_SA_initialize_random_hyperparameters(Ps, Params_desc)
    % Randomly select one hyperparameter configuration from the possible sets
    idx = randi(height(Ps{1})); % Assume combcell is a cell array of possible configs
    config = Ps{1}{idx}; % Select one configuration randomly
    config_desc = Params_desc{1}{idx};
end
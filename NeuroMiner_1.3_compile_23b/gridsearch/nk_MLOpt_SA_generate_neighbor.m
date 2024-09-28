function neighbor = nk_MLOpt_SA_generate_neighbor(Ps, curclass, best_config_index)
    num_combinations = height(Ps{curclass});  % Get the number of hyperparameter combinations
    % Define the range of selection based on the current temperature
    deviation = max(1, round(temperature * num_combinations / 2));  % Reduce range as temperature decreases

    % Calculate the start and end index for selection, ensuring they remain within valid bounds
    start_index = max(1, best_config_index - deviation);
    end_index = min(num_combinations, best_config_index + deviation);

    % Select a random index within the defined range
    random_index = randi([start_index, end_index]);

    neighbor = Ps{curclass}(random_index, :);
end



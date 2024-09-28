function [best_GD, best_MD] = nk_MLOptimizer_SimulatedAnnealing(GD, MD, DISP, Ps, ...
                            Params_desc, mapY, algostr, f, d, npreml, ...
                            nclass, ngroups, batchflag, PsSel, combcell)

    % Define initial parameters for the simulated annealing process
    initial_temperature = 1.0;
    cooling_rate = 0.95;
    stopping_temperature = 0.001;
    max_iterations = 100;

    % Initialize random configuration based on parameter indices
    curPsPos = initialize_random_hyperparameters(Ps);
    curPsPosScore = objective_function( GD, MD, Ps, Params_desc, combcell, curPsPos, visitedPsPos, mapY, algostr, f, d, npreml, nclass, ngroups);

    % Track the best configuration
    bestPsPos = curPsPos ;
    bestPsPosScore = curPsPosScore ;

    % Main optimization loop
    temperature = initial_temperature;
    while temperature > stopping_temperature
        for iteration = 1:max_iterations
            neighPsPos = nk_MLOpt_SA_generate_neighbor(Ps, 1, bestPsPos);
            neighPsPosScore = nk_MLOpt_SA_objective_function( GD, MD, Ps, Params_desc, combcell, curPsPos, visitedPsPos, mapY, algostr, f, d, npreml, nclass, ngroups);

            if accept_solution(current_score, neighPsPosScore , temperature)
                current_config = neighbor_config;
                current_score = neighbor_score;

                % Update the best configuration
                if neighbor_score > best_score
                    bestPsPos = neighbor_config;
                    bestPsPosScore = neighbor_score;
                end
            end
        end
        % Reduce the temperature
        temperature = temperature * cooling_rate;
    end

    % Update the GD and MD with the best configuration found
    best_GD = update_GD_with_config(best_config, GD);
    best_MD = update_MD_with_config(best_config, MD);
end

function GD = update_GD_with_config(config, GD)
    % Update global data structure GD based on the optimal hyperparameter configuration
    % Implementation details depend on the specific structure of GD
    GD.optimal_config = config; % Example of updating GD
end

function MD = update_MD_with_config(config, MD)
    % Update model data structure MD based on the optimal hyperparameter configuration
    % Implementation details depend on the specific structure of MD
    MD.optimal_config = config; % Example of updating MD
end
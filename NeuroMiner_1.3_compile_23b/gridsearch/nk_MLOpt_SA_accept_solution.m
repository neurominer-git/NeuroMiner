function accept = nk_MLOpt_SA_accept_solution(current_score, neighbor_score, temperature)
    % Determine if the new solution should be accepted
    if neighbor_score < current_score
        accept = true; % Always accept if the neighbor solution is better
    else
        % Calculate the probability of accepting worse solution
        delta = neighbor_score - current_score;
        probability = exp(-delta / temperature); % Boltzmann factor
        accept = rand() < probability; % Accept with a probability that decreases with delta and temperature
    end
end
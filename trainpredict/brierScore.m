function score = brierScore(y_true, y_probs)
    % Compute the Brier Score
    score = mean((y_probs - y_true).^2);
end
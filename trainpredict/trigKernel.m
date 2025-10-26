function K = trigKernel(X, Y, gamma, omega)
    % Trigonometric Kernel Function
    % 
    % Inputs:
    %   X: Input matrix of size (n_samples1 x n_features)
    %   Y: Input matrix of size (n_samples2 x n_features)
    %   gamma: Scaling parameter (controls the spread of the kernel)
    %          Recommended range: [0.01, 1.0] 
    %          Lower values result in broader kernels; higher values result in sharper kernels.
    %   omega: Frequency parameter (controls the oscillation of the kernel)
    %          Recommended range: [0.1, 10.0]
    %          Lower values produce smoother oscillations; higher values result in finer oscillations.
    %
    % Output:
    %   K: Kernel matrix of size (n_samples1 x n_samples2)
    %
    % Description:
    %   This kernel combines a trigonometric (cosine) term with an exponential decay to
    %   model periodic and local data patterns effectively.
    %
    % Example Usage:
    %   gamma = 0.1;  % Scale parameter
    %   omega = 1.0;  % Frequency parameter
    %   K = trigKernel(X, Y, gamma, omega);
    %
    % Note:
    %   The choice of hyperparameters `gamma` and `omega` should be guided by 
    %   cross-validation or a grid search to find optimal values for specific datasets.
    
    % Compute the squared Euclidean distance matrix
    sqDist = pdist2(X, Y, 'euclidean').^2;

    % Apply the trigonometric kernel formula
    K = cos(omega * sqrt(sqDist)) .* exp(-gamma * sqDist);
end

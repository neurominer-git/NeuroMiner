function [aligned_target, aligned_targetval] = nk_AlignPCAModels(reference, target, targetval)
% =========================================================================
% function [aligned_target, aligned_targetval] = nk_AlignPCAModels(reference, target, targetval)
% =========================================================================
%   aligned_target = nk_AlignPCAmodel(reference, target) aligns the
%   target matrix to the reference matrix by trimming or padding the target
%   matrix, performing Procrustes analysis, and correcting the signs of the
%   eigenvectors if necessary.
%
%   Inputs:
%       reference    - (n x m) matrix representing the reference PCA transformation
%                      (e.g., n samples, m components)
%       target       - (n x p) matrix representing the target PCA transformation
%                      (e.g., n samples, p components)
%   Output:
%       aligned_target - (n x n_components) matrix representing the aligned
%                        version of the target matrix, with dimensions and signs
%                        adjusted to match the reference matrix
%
%   Example:
%       reference = rand(100, 10); % Reference PCA transformation matrix
%       target = rand(100, 15);    % Target PCA transformation matrix
%       aligned_target = align_pca(reference, target);
%
%   The function performs the following steps:
%   1. Checks if the number of components in the target matrix exceeds the number
%      in the reference matrix. If so, it selects the target components with the
%      highest similarity to the reference components.
%   2. Adjusts the dimensions of the target matrix by padding with zeros if there
%      are fewer components than in the reference matrix.
%   3. Uses Procrustes analysis to align the trimmed or padded target matrix to
%      the reference matrix.
%   4. Corrects the signs of the eigenvectors in the aligned target matrix to match
%      the signs of the corresponding eigenvectors in the reference matrix.
%
%   This function is particularly useful for aligning PCA transformation matrices
%   across different datasets or cross-validation folds, ensuring consistent
%   eigenvector orientation and dimensionality.
% ________________________________________________________________________________
% (c) Nikolaos Koutsouleris, 06/2024

    % Check the number of components in the target matrix
    n_components = size(reference,2);
    num_target_components = size(target, 2);
    
    if num_target_components > n_components
        % Compute similarities between reference and target eigenvariates
        % using Cosine distance
        similarities = zeros(n_components, num_target_components);
        for i = 1:n_components
            for j = 1:num_target_components
                similarities(i, j) = abs(dot(reference(:, i), target(:, j)) / (norm(reference(:, i)) * norm(target(:, j))));
            end
        end
        
        % Select the target components with the highest similarity to each reference component
        selected_indices = zeros(1, n_components);
        for i = 1:n_components
            [~, max_idx] = max(similarities(i, :));
            selected_indices(i) = max_idx;
            similarities(:, max_idx) = -inf; % Ensure the same component is not selected again
        end
        
        % Create the trimmed target matrix with selected components
        trimmed_target = target(:, selected_indices);
        selected_eigenvalues = targetval(selected_indices);

    elseif num_target_components < n_components
        % If the number of target components is less than or equal to the reference, use as is
        trimmed_target = target;
        selected_eigenvalues = targetval;
        % Pad with zeros if there are fewer components
        if num_target_components < n_components
            padding = zeros(size(target, 1), n_components - num_target_components);
            trimmed_target = [trimmed_target, padding];
            selected_eigenvalues = [selected_eigenvalues; zeros(n_components - num_target_components, 1)];
        end
    else
        trimmed_target = target;
        selected_eigenvalues = targetval;
    end
    
    % Align the (trimmed) target matrix to the reference using Procrustes analysis
    [~, target_aligned, ~] = procrustes(reference, trimmed_target);
    % Flip signs of eigenvectors if necessary
    for j = 1:n_components
        if sign(sum(reference(:, j))) ~= sign(sum(target_aligned(:, j)))
            target_aligned(:, j) = -target_aligned(:, j);
        end
    end
    aligned_target = target_aligned;
    aligned_targetval = selected_eigenvalues;
end
function [mappedX, mapping] = lle_allcomp(X, no_dims, k, eig_impl)
% LLE_ALLCOMP Runs the locally linear embedding algorithm with a modification to
% handle multiple connected components and pad with NaNs.
%
%   mappedX = lle_allcomp(X, no_dims, k, eig_impl)
%
% Runs the local linear embedding algorithm on dataset X to reduce its
% dimensionality to no_dims. In the LLE algorithm, the number of neighbors
% can be specified by k. 
% The function returns the embedded coordinates in mappedX.
%

    if ~exist('no_dims', 'var')
        no_dims = 2;
    end
    if ~exist('k', 'var')
        k = 12;
    end
    if ~exist('eig_impl', 'var')
        eig_impl = 'Matlab';
    end

    % Get dimensionality and number of dimensions
    [n, d] = size(X);

    % Compute pairwise distances and find nearest neighbors (vectorized implementation)
    disp('Finding nearest neighbors...');    
    [distance, neighborhood] = find_nn(X, k);
    
    % Identify all connected components of the neighborhood graph
    blocks = components(distance)';
    unique_blocks = unique(blocks);

    % Initialize mappedX with NaNs to ensure the correct shape
    mappedX = nan(n, no_dims);

    % Iterate over each connected component
    for block_id = unique_blocks'
        % Get current connected component
        conn_comp = find(blocks == block_id);
        num_conn_comp = numel(conn_comp);
        
        % Skip small components that cannot be embedded
        if num_conn_comp <= no_dims
            warning(['Skipping block ' num2str(block_id) ' because it is too small for the target dimensionality.']);
            continue;
        end

        % Update the neighborhood relations for the current component
        X_block = X(conn_comp,:)';
        neighborhood_block = neighborhood(conn_comp, :)';
        max_k = size(neighborhood_block, 1);

        % Find reconstruction weights for all points by solving the MSE problem
        disp('Compute reconstruction weights...');
        W = zeros(max_k, num_conn_comp);
        if k > d
            tol = 1e-5;
        else
            tol = 0;
        end
        
        for i = 1:num_conn_comp
            nbhd = neighborhood_block(:, i);
            nbhd = nbhd(nbhd ~= 0);  % Remove zero entries
            
            % Ensure nbhd is not empty and within valid bounds
            if isempty(nbhd) || any(nbhd > num_conn_comp)
                warning(['Point ' num2str(i) ' in connected component ' num2str(block_id) ' has no valid neighbors or out-of-bound neighbors.']);
                continue;
            end
            
            % Compute local covariance
            z = bsxfun(@minus, X_block(:, nbhd), X_block(:, i));  % Shift point to origin
            C = z' * z;                                           % Compute local covariance
            C = C + eye(size(C)) * tol * trace(C);                % Regularization of covariance
            
            % Solve the system
            wi = C \ ones(numel(nbhd), 1);
            wi = wi / sum(wi);
            W(1:numel(nbhd), i) = wi;
        end

        % Construct sparse cost matrix M for this block
        M_block = sparse(num_conn_comp, num_conn_comp);
        for i = 1:num_conn_comp
            w = W(:,i);
            nbhd = neighborhood_block(:,i);
            j = nbhd(nbhd ~= 0);  % Remove zero entries from neighborhood
            indices = find(~isnan(w));
            j = j(indices);
            w = w(indices);
            
            % Check if the indices are valid before updating M_block
            if isempty(j)
                warning(['Skipping point ' num2str(i) ' in connected component ' num2str(block_id) ' due to invalid neighbors.']);
                continue;
            end
            
            % Ensure indices are within bounds
            if any(j > num_conn_comp) || any(i > num_conn_comp)
                warning(['Out-of-bound neighbors detected for point ' num2str(i) ' in block ' num2str(block_id)]);
                continue;
            end

            M_block(i, j) = M_block(i, j) - w';
            M_block(j, i) = M_block(j, i) - w;
            M_block(j, j) = M_block(j, j) + w * w';
        end
        
        % Solve eigenproblem for this block
        disp('Compute embedding (solve eigenproblem)...');
        try
            if strcmp(eig_impl, 'JDQR')
                options.Disp = 0;
                options.LSolver = 'bicgstab';
                [mapped_block, eigenvals_block] = jdqr(M_block + eps * eye(num_conn_comp), no_dims + 1, 0, options);
            else
                options.disp = 0;
                options.isreal = 1;
                options.issym = 1;
                [mapped_block, eigenvals_block] = eigs(M_block + eps * eye(num_conn_comp), no_dims + 1, 0, options);
            end
            
            [eigenvals_block, ind_block] = sort(diag(eigenvals_block), 'ascend');
            
            % Ensure mapped_block has enough dimensions
            if size(mapped_block, 2) < no_dims + 1
                warning(['Target dimensionality reduced to ' num2str(size(mapped_block, 2) - 1) ' for block ' num2str(block_id)]);
                continue;
            end
            
            % Take the required dimensions (discard the first eigenvector)
            mapped_block = mapped_block(:, ind_block(2:no_dims + 1));
            
            % Store the results in the original matrix (fill NaNs for unmapped points)
            mappedX(conn_comp, :) = mapped_block;
            
        catch ME
            warning(['Eigenproblem failed for block ' num2str(block_id) ': ' ME.message]);
            % Skip this block and fill the corresponding part of mappedX with NaNs
            mappedX(conn_comp, :) = nan(num_conn_comp, no_dims);
            continue;
        end
    end

    % Save information on the mapping
    mapping.k = k;
    mapping.X = X;
    mapping.vec = mappedX;
    
    % Handle eigenvalue mapping in case of skipped components
    if exist('eigenvals_block', 'var') && numel(eigenvals_block) >= no_dims + 1
        mapping.val = eigenvals_block(2:no_dims + 1);
    else
        mapping.val = nan(no_dims, 1);  % Fill with NaNs if eigenvals_block is not valid
    end

    mapping.conn_comp = blocks;
    mapping.nbhd = distance;

    % Warning if any points remain NaN
    if any(isnan(mappedX(:)))
        warning('Some points could not be embedded properly. NaNs have been used for missing values.');
    end
end

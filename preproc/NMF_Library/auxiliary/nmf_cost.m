function f = nmf_cost(V, W, H, R, varargin)
%NMF_COST Compute the cost function for non-negative matrix factorization (NMF).
%
%   f = nmf_cost(V, W, H, R) computes the Euclidean (Frobenius norm)
%   cost for the NMF model:
%
%       V ≈ W * H + R,
%
%   where V is the non-negative data matrix, W is the basis matrix,
%   H is the coefficient matrix, and R is an optional outlier matrix.
%   If R is empty, it is replaced by a zero matrix of the same size as V.
%
%   f = nmf_cost(V, W, H, R, metric) computes the cost based on the
%   specified divergence metric, where 'metric' can be:
%
%       'EUC'      - Euclidean distance (default):
%                    f = 1/2 * ||V - (W*H + R)||_F^2.
%
%       'KL'       - Kullback-Leibler divergence:
%                    f = sum(V .* log(V./(W*H + R)) - V + (W*H + R)).
%
%       'ALPHA-D'  - Alpha-divergence. In this case, an additional parameter
%                    alpha must be provided as the next input:
%                    f = sum(V(:).^alpha .* (W*H + R)(:)^(1-alpha) - ...
%                        alpha*V(:) + (alpha-1)*(W*H + R)(:)) / (alpha*(alpha-1)).
%
%       'BETA-D'   - Beta-divergence. In this case, an additional parameter
%                    beta must be provided as the next input. For beta values:
%                         0: f = sum(V(:)./(W*H + R)(:) - log(V(:)./(W*H + R)(:)) - 1),
%                         1: f = sum(V(:).*log(V(:)./(W*H + R)(:)) - V(:) + (W*H + R)(:)),
%                         2: f = sum(sum((V - W*H).^2)),
%                    and for other values:
%                         f = sum(V(:).^beta + (beta-1)*(W*H + R)(:).^beta - ...
%                             beta*V(:).*(W*H + R)(:).^(beta-1)) / (beta*(beta-1)).
%
%   INPUTS:
%       V       : (m x n) non-negative data matrix to be factorized.
%       W       : (m x r) non-negative basis matrix.
%       H       : (r x n) non-negative coefficient matrix.
%       R       : (m x n) non-negative outlier matrix. If empty, it is replaced
%                 by a zero matrix of size(V).
%       varargin: Optional arguments specifying the divergence metric and its
%                 associated parameter (if required). If not provided, or if
%                 'EUC' is specified, the Euclidean cost is computed.
%
%   OUTPUT:
%       f       : Scalar value representing the computed cost.
%
%   EXAMPLES:
%       % Compute Euclidean cost (default):
%       cost_val = nmf_cost(V, W, H, []);
%
%       % Compute KL divergence cost:
%       cost_val = nmf_cost(V, W, H, [], 'KL');
%
%       % Compute Alpha-divergence cost with alpha = 0.5:
%       cost_val = nmf_cost(V, W, H, [], 'ALPHA-D', 0.5);
%
%       % Compute Beta-divergence cost with beta = 1:
%       cost_val = nmf_cost(V, W, H, [], 'BETA-D', 1);
%
%   See also: fro_mu_nmf, als_nmf, display_graph.
%
%   This file is part of NMFLibrary.
%
%   Created by H.Kasai on Feb. 21, 2017.
%   Modified by H.Kasai on Jul. 23, 2018.
%

    if isempty(R)
        R = zeros(size(V));
    end

    Vhat = W * H + R;

    if isempty(varargin) || strcmp(varargin{1}, 'EUC')
        
        f = norm(V - Vhat,'fro')^2 / 2 ;
        %f = sum(sum((V - Vhat).^2)) / 2; 
        
    elseif strcmp(varargin{1}, 'KL')
        
        Vhat = W * H + R;
        Vhat = Vhat + (Vhat<eps) .* eps;
        
        temp = V.*log(V./Vhat);
        temp(temp ~= temp) = 0; % NaN ~= NaN
        f = sum(sum(temp - V + Vhat)); 
        
    elseif strcmp(varargin{1}, 'ALPHA-D')
        
        alpha = varargin{2};
        
        f = sum(V(:).^alpha .* Vhat(:).^(1-alpha) - alpha*V(:) + ...
                  (alpha-1)*Vhat(:)) / (alpha*(alpha-1));
    
    elseif strcmp(varargin{1}, 'BETA-D')
        
        beta = varargin{2};
        
        switch beta
            case 0
                f = sum(V(:)./Vhat(:) - log(V(:)./Vhat(:)) - 1);     
            case 1
                f = sum(V(:).*log(V(:)./Vhat(:)) - V(:) + Vhat(:));
            case 2
                f = sum(sum((V-W*H).^2));
            otherwise
                f = sum(V(:).^beta + (beta-1)*Vhat(:).^beta - beta*V(:).*Vhat(:).^(beta-1)) / ...
                          (beta*(beta-1));
        end
    
    else
        % use 'EUC'
        f = norm(V - Vhat,'fro')^2 / 2 ;
    end
    
end

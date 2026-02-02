function adjust = itSol_new(sdat, g_hat, d_hat, g_bar, t2, a, b, conv)
    g_old = g_hat;
    d_old = d_hat;
    change = 1;
    count = 0;
    n = size(sdat,2);
    max_iter = 1000;
    abs_tol = 1e-6;  % Absolute tolerance
    
    while change > conv && count < max_iter
        g_new = postmean(g_hat,g_bar,n,d_old,t2);
        sum2  = sum(((sdat-g_new'*ones(1,size(sdat,2))).^2)');
        d_new = postvar(sum2,n,a,b);
        
        % Check for numerical issues
        if any(isnan(g_new(:))) || any(isinf(g_new(:))) || ...
           any(isnan(d_new(:))) || any(isinf(d_new(:)))
            warning('itSol: Numerical issues detected at iteration %d', count);
            adjust = [g_old; d_old];
            return;
        end
        
        % Combined absolute and relative tolerance
        g_abs_change = max(abs(g_new - g_old));
        d_abs_change = max(abs(d_new - d_old));
        g_rel_change = g_abs_change / (max(abs(g_old)) + eps);
        d_rel_change = d_abs_change / (max(abs(d_old)) + eps);
        
        % Convergence if both absolute AND relative changes are small
        change = max(g_rel_change, d_rel_change);
        abs_change = max(g_abs_change, d_abs_change);
        
        if abs_change < abs_tol && change < conv
            break;
        end
        
        g_old = g_new;
        d_old = d_new;
        count = count + 1;
    end
    
    if count >= max_iter
        warning('itSol: Did not converge after %d iterations (change=%.2e)', max_iter, change);
    end
    
    adjust = [g_new; d_new];
end
function t = infer_covtype(v)
    % Infer basic measurement scale from a covariate vector v (numeric).
    v = v(:);
    v = v(~isnan(v));
    u = unique(v);
    k = numel(u);
    
    if k <= 1
        t = 'continuous';
        return;
    end
    
    if k == 2 
        t = 'binary';
        return;
    end
    
    allInt = all(mod(u,1) == 0);
    
    if allInt && k <= 7
        t = 'ordinal';
        return;
    end
    
    if k <= 7
        t = 'categorical';
        return;
    end
    
    t = 'continuous';
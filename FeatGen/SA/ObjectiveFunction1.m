function y = ObjectiveFunction1(n, c, L, T, tL, tY, Ps, criterion)
global TRAINFUNC RFE

[~, model] = feval(TRAINFUNC, tY, tL, 1, Ps);   
switch RFE.Wrapper.datamode
    case 1
        param = nk_GetTestPerf(tY, tL, [], model, tY);
    case 2
        param = nk_GetTestPerf(T, L, [], model, tY);
    case 3
        param = nk_GetTestPerf([T; tY], [L; tL], [], model, tY);
end
rF = size(T,2)/n;

% Criterion-aware scaling
switch criterion
    case {'MAE', 'MSE', 'RMSE', 'GMEAN', 'CC', 'MCC', 'nLR', 'pLR', 'ECE', 'NNP', 'NND'}
        % These are already in proper scale, no division needed
        y = param - c*rF;
    otherwise
        % These are typically 0-100, so normalize
        y = param/100 - c*rF;
end



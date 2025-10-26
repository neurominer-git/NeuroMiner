function [rT, L_tr] = probtransform(L_tr, tr, ts, method)

L_tr(L_tr==-1 | L_tr==2)=0;

if ~exist('ts','var') || isempty(ts)
    if all(tr >= 0 & tr <= 1)
        rT = ts; return
    end
    rT = zeros(size(tr));
    nC = size(tr,1);
    fprintf('\nCalibrate scores in LOO mode\n')
    % Run in LOO mode
    for i=1:nC
        fprintf('.')
        idx = true(nC,1); idx(i) = false;
        L_tr_i = L_tr(idx);
        tr_i = tr(idx);
    
        switch method
            case 'platt'
                % Compute weights to adjust for unbalanced label scenarios
                numPositive = sum(L_tr_i); numNegative = numel(L_tr_i) - numPositive;
                weightPositive = numNegative / numPositive; weightNegative = 1;
                
                % Use logistic regression with class weights to fit the Platt scaling model
                model = fitglm(tr_i, L_tr_i, 'Distribution', 'binomial', 'Link', 'logit', 'Weights', L_tr_i.*weightPositive + (1-L_tr_i).*weightNegative);
                rT(i) = model.predict(tr(i));

            case 'isotonic'
                % get the FULL PAV mapping (length N)
                rT(i) = calibIsotonicEnsemble(tr_i, L_tr_i, tr(i), 5, true);  % 5‐fold ensemble

            case 'bbq'
                PTR = exp(tr_i)./(1+exp(tr_i)); 
                model = buildBBQ(PTR,L_tr_i,[]);
                PTE = exp(tr(i))./(1+exp(tr(i))); 
                rT(i) = predictBBQ(model, PTE, 0); 
        end
    end
else
    if all(ts >= 0 & ts <= 1)
        rT = ts; return
    end
    switch method
        case 'platt'
            numPositive = sum(L_tr); numNegative = numel(L_tr) - numPositive;
            weightPositive = numNegative / numPositive; weightNegative = 1;
            model = fitglm(tr, L_tr, 'Distribution', 'binomial', 'Link', 'logit', 'Weights', L_tr.*weightPositive + (1-L_tr).*weightNegative);
            rT = model.predict(ts);
        case 'isotonic'
            rT = calibIsotonicEnsemble(tr, L_tr, ts, 5, true);
        case 'bbq'
            PTR = exp(tr)./(1+exp(tr)); 
            BBQ = buildBBQ( PTR, L_tr,[]);
            PTE =exp(ts)./(1+exp(ts)); 
            rT = predictBBQ(BBQ,PTE,1); 
    end
end


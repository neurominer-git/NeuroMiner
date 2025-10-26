% ==========================================================================
% FORMAT [featImp] = nk_GetGradientWeight(model, tXtest)
% ==========================================================================
% Inputs 
%   model: Python sklearn or TF model with predict/predict_proba method
%   tXtest: Test data matrix [N x D]
% 
% Outputs
%   featImp: Feature importance vector (1 x D) based on gradient difference
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Sergio Mena Ortega, 2024

function [featImp] = nk_GetGradientWeight(model, tXtest)
    global MODEFL SVM

    % Initialize the feature importance array
    featImp = zeros(1, size(tXtest, 2));

    % Select program
    switch SVM.prog
        case 'RNDFOR'
            for i = 1:size(tXtest, 2)
                tXtest_copy = tXtest;
                min_val = min(tXtest(:, i));
                max_val = max(tXtest(:, i));
                tXtest_copy(:, i) = min_val;
                [~, pred_min] = nk_GetTestPerf_RNDFOR([], tXtest_copy, [], model, [], []);
                tXtest_copy(:, i) = max_val;
                [~, pred_max] = nk_GetTestPerf_RNDFOR([], tXtest_copy, [], model, [], []);
                featImp(i) = mean(pred_max - pred_min) / (max_val - min_val);
            end
        case 'GRDBST'
            for i = 1:size(tXtest, 2)
                tXtest_copy = tXtest;
                min_val = min(tXtest(:, i));
                max_val = max(tXtest(:, i));
                tXtest_copy(:, i) = min_val;
                [~, pred_min] = nk_GetTestPerf_GRDBST([], tXtest_copy, [], model, [], []);
                tXtest_copy(:, i) = max_val;
                [~, pred_max] = nk_GetTestPerf_GRDBST([], tXtest_copy, [], model, [], []);
                featImp(i) = mean(pred_max - pred_min) / (max_val - min_val);
            end

        case 'MLPERC'
            for i = 1:size(tXtest, 2)
                tXtest_copy = tXtest;
                min_val = min(tXtest(:, i));
                max_val = max(tXtest(:, i));
                tXtest_copy(:, i) = min_val;
                [~, pred_min] = nk_GetTestPerf_MLPERC([], tXtest_copy, [], model, [], []);
                tXtest_copy(:, i) = max_val;
                [~, pred_max] = nk_GetTestPerf_MLPERC([], tXtest_copy, [], model, [], []);
                featImp(i) = mean(pred_max - pred_min) / (max_val - min_val);
            end

        case 'TFDEEP'
            for i = 1:size(tXtest, 2)
                tXtest_copy = tXtest;
                min_val = min(tXtest(:, i));
                max_val = max(tXtest(:, i));
                tXtest_copy(:, i) = min_val;
                [~, pred_min] = nk_GetTestPerf_TFDEEP([], tXtest_copy, [], model, [], []);
                tXtest_copy(:, i) = max_val;
                [~, pred_max] = nk_GetTestPerf_TFDEEP([], tXtest_copy, [], model, [], []);
                featImp(i) = mean(pred_max - pred_min) / (max_val - min_val);
            end

        case 'BAYLIN'
            for i = 1:size(tXtest, 2)
                tXtest_copy = tXtest;
                min_val = min(tXtest(:, i));
                max_val = max(tXtest(:, i));
                tXtest_copy(:, i) = min_val;
                [~, pred_min] = nk_GetTestPerf_BAYLIN([], tXtest_copy, [], model, [], []);
                tXtest_copy(:, i) = max_val;
                [~, pred_max] = nk_GetTestPerf_BAYLIN([], tXtest_copy, [], model, [], []);
                featImp(i) = mean(pred_max - pred_min) / (max_val - min_val);
            end



    end
end
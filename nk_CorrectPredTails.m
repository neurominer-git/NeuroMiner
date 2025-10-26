function [ sY, Y, IN ] = nk_CorrectPredTails( Y, X, IN )
%   [sY, Y, IN] = nk_CorrectPredTails(Y, X, IN) corrects for systematic prediction
%   errors, which tend to be larger at the tails of the label distribution.
%   The function computes a linear correction based on the relationship between
%   labels and prediction errors from a reference dataset and applies this
%   correction to the predictions of a target sample.
%
%   INPUTS:
%     Y   - Target sample predictions. When Y is empty, the function
%           operates in a Leave-One-Out (LOO) mode on the reference dataset.
%
%     X   - Label data for Y, if Y is provided.
%
%     IN  - A structure that must include the following fields:
%             .TrPred : Reference sample predictions 
%                        (e.g., NM.analysis{1}.GDdims{1}.Regr.mean_predictions)
%             .TrObs  : True labels for the reference sample 
%                        (e.g., NM.label)
%
%           It can optionally include:
%             .beta   : Pre-computed correction slopes. If absent, they are computed.
%             .p      : Additional parameters associated with the correction.
%
%   OUTPUTS:
%     sY  - Corrected predictions for the target sample.
%
%     Y   - The original target predictions (or the reference predictions 
%           in LOO mode, if Y was originally empty).
%
%     IN  - The updated structure with the computed correction parameters:
%             .beta and .p.
%
%   OPERATION MODES:
%     1. Leave-One-Out (LOO) Mode:
%          When Y is empty, the function iterates through the reference sample,
%          excluding one sample at a time, computes correction parameters (slope and
%          intercept) for that sample using the remaining data, and then applies the
%          correction to obtain a corrected prediction.
%
%     2. Reference Modeling Mode:
%          When Y is provided, the function computes the correction parameters once
%          from the entire reference set (IN.TrPred and IN.TrObs) and applies them to Y.
%
%   EXAMPLE USAGE:
%     % Define the reference sample predictions and observations:
%     IN.TrPred = NM.analysis{1}.GDdims{1}.Regr.mean_predictions;
%     IN.TrObs  = NM.label;
%
%     % Define the target sample predictions:
%     Y = NM.analysis{1}.OOCV{1}.RegrResults{1}.Group{1}.MeanCV2PredictedValues;
%
%     % Apply the correction:
%     [sY, Y, IN] = nk_CorrectPredTails(Y, [], IN);
% =========================================================================
% (c) Nikolaos Koutsouleris, 02/2021

flag = false;
if exist('IN','var') && ~isempty(IN) 
    if ~isfield(IN,'beta') || ~isfield(IN,'p')
        if ~isfield(IN,'TrObs') || ~isfield(IN,'TrPred')
            error('Please provide the reference sample''s labels and predictions so that I can compute correction parameters!')
        else
            if isempty(Y)
                % LOO mode, if no target sample has been provided with Y
                flag = true;
                nTr = numel(IN.TrPred);
                Y = IN.TrPred;
                sY = zeros(nTr,1);
                IN.beta = zeros(2,nTr);
                IN.p =zeros(nTr,2);
                fprintf('\nLOO mode')
                for i=1:nTr
                    fprintf('.')
                    I_train = true(nTr,1); I_train(i)=false;
                    [~, IN.beta(:,i), IN.p(i,:)] = nk_DetrendPredictions2([],[], Y(I_train), IN.TrObs(I_train));
                    sY(i) = nk_DetrendPredictions2(IN.beta(:,i),IN.p(i,:), Y(i));
                end
                fprintf('\n')
            else
                % Reference modelling mode
                [~, IN.beta, IN.p] = nk_DetrendPredictions2([],[], IN.TrPred, IN.TrObs);
            end
        end
    end
else
    error('Please provide a valid IN structure for the function!')
end
if ~exist("X", "var"), X=[]; end
if ~flag, sY = nk_DetrendPredictions2(IN.beta, IN.p, Y, X); end

function rT = calibIsotonicEnsemble(tr, L_tr, ts, M, useJitter)
% calibIsotonicEnsemble  Ensemble‐averaged, optionally jittered isotonic calibration
%
% rT = calibIsotonicEnsemble(tr, L_tr, ts, M)
% rT = calibIsotonicEnsemble(tr, L_tr, ts, M, useJitter)
%
% Inputs:
%   tr         : N×1 training decision scores
%   L_tr       : N×1 binary labels (0/1)
%   ts         : T×1 test decision scores (or N×1 in LOO mode)
%   M          : number of folds / ensemble members
%   useJitter  : (optional) logical; if true, adds tiny Gaussian noise
%                to tr on each fold to break ties (default = false)
%
% Output:
%   rT         : 1×T calibrated probabilities in [0,1]

    if nargin < 5
        useJitter = false;
    end

    N     = numel(tr);
    T     = numel(ts);
    preds = zeros(M, T);

    % Build a random M‐fold split without stats toolbox
    idxPerm   = randperm(N);
    baseSize  = floor(N/M);
    extra     = mod(N, M);
    foldSizes = baseSize + ([1:M] <= extra);
    starts    = [1, cumsum(foldSizes(1:end-1))+1];

    % Precompute jitter scale if needed
    if useJitter
        jitterScale = (max(tr) - min(tr)) * 1e-6;
    else
        jitterScale = 0;
    end

    for k = 1:M
        % Determine train/test indices
        foldIdx  = idxPerm(starts(k) : starts(k)+foldSizes(k)-1);
        idxTest  = sort(foldIdx);
        idxTrain = setdiff(1:N, idxTest);

        % Optionally jitter the training scores
        if useJitter
            trj = tr + jitterScale * randn(N,1);
        else
            trj = tr;
        end

        % Weighted isotonic fit on the training split
        [~,~, x_bp, y_bp] = weightedIsotonicFit(trj(idxTrain), L_tr(idxTrain));

        % Smooth (PCHIP) interpolation back to test scores
        p = interp1(x_bp, y_bp, ts, 'pchip', 'extrap');

        % Clamp into [0,1]
        preds(k,:) = min(max(p, 0), 1);
    end

    % Average across all M fits
    rT = mean(preds, 1);
end

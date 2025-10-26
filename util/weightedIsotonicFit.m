function [x_full, y_full, x_unique, y_levels] = weightedIsotonicFit(scores, labels)
%WEIGHTEDISOTONICFIT  Weighted PAV isotonic regression (0/1 labels).
% [x_full, y_full, x_unique, y_levels] = weightedIsotonicFit(scores, labels)
%
% Inputs:
%   scores : Nx1 vector of real decision scores (unsorted OK)
%   labels : Nx1 vector of binary labels (0 or 1)
%
% Outputs:
%   x_full   : N×1 sorted `scores`
%   y_full   : N×1 PAV‐fitted step levels at each sorted score
%   x_unique : K×1 unique breakpoints (one per PAV block)
%   y_levels : K×1 level at each breakpoint

    % ensure col‑vectors
    scores = scores(:);
    labels = labels(:);

    % 1) class‐imbalance weights
    numPos  = sum(labels==1);
    numNeg  = sum(labels==0);
    wPos    = numNeg / max(numPos,1);
    wNeg    = 1;
    weights = labels * wPos + (1 - labels) * wNeg;

    % 2) sort
    [x_s, I] = sort(scores);
    y_s      = labels(I);
    w_s      = weights(I);

    % 3) init blocks
    blk_y = num2cell(y_s);
    blk_w = num2cell(w_s);
    blk_n = num2cell(ones(size(y_s)));

    % 4) weighted PAV merge
    j = 1;
    while j < numel(blk_y)
      if blk_y{j} > blk_y{j+1}
        W        = blk_w{j} + blk_w{j+1};
        Y        = (blk_y{j}*blk_w{j} + blk_y{j+1}*blk_w{j+1}) / W;
        N        = blk_n{j} + blk_n{j+1};
        blk_y{j} = Y;
        blk_w{j} = W;
        blk_n{j} = N;
        blk_y(j+1) = [];
        blk_w(j+1) = [];
        blk_n(j+1) = [];
        j = max(j-1,1);
      else
        j = j + 1;
      end
    end

    % 5) expand blocks back to each point
    y_full = repelem(cell2mat(blk_y), cell2mat(blk_n));

    % 6) block‐start indices
    block_starts = cumsum([1; cell2mat(blk_n(1:end-1))]);

    % 7) compressed breakpoints
    x_unique = x_s(block_starts);
    y_levels = y_full(block_starts);

    % 8) full sorted x
    x_full = x_s;
end
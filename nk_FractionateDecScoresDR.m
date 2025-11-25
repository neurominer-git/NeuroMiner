function [D, f_total] = nk_FractionateDecScoresDR(Z, w, bias)
% nk_FractionateDecScoresDR
%   Fractionate linear model decision scores into per-component contributions
%   in a discriminative PCA / DR space.
%
%   Inputs:
%     Z     : [nSubj x K] subject scores in DR (PCA) space
%     w     : [K x 1]     model weights in the same space (single label)
%     bias  : scalar      intercept term (can be [] or 0)
%
%   Outputs:
%     D       : [nSubj x K] fractionated decision scores
%               D(s,k) = w(k) * Z(s,k)
%     f_total : [nSubj x 1] total decision scores
%               f_total = sum(D,2) + bias
%
%   Note:
%     For multiclass / multilabel, call this once per label with the
%     corresponding column of w.

    if nargin < 3 || isempty(bias), bias = 0; end

    % ensure column vector
    w = w(:);                  % K x 1
    K = numel(w);

    if size(Z,2) ~= K
        error('Z has %d columns but w has %d elements.', size(Z,2), K);
    end

    % fractionated contributions: subject x component
    % D(s,k) = Z(s,k) * w(k)
    D = bsxfun(@times, Z, w.');     % nSubj x K

    % total decision value per subject
    f_total = sum(D,2) + bias;
end

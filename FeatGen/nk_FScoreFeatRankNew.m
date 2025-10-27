% nk_FScoreFeatRank ranks features by their (optionally weighted) F-score,
%              with optional bootstrap stability estimation.
% ========================================================================
% [F, Fstd, Fci] = nk_FScoreFeatRankNew(Y, L, N, meanfun, varfun, decomp, weightMode, W, B, alpha)
% ------------------------------------------------------------------------
% Computes an F-score for each feature (column of Y) based on class
% separability. Supports nuisance labels, sample weighting, and
% optional bootstrap estimation of score stability.
%
% INPUTS:
%   Y           - [nSamples x nFeatures] data matrix.
%   L           - [nSamples x 1] primary class labels.
%   N           - [nSamples x nNuisance] nuisance labels (optional).
%   meanfun     - 'wNanMean' or 'wNanMedian'. Default: 'wNanMean'.
%   varfun      - 'wNanStd' or 'wNanIQR'.    Default: 'wNanStd'.
%   decomp      - 0=one-vs-all, 1=one-vs-one. Default: 0 (overridden by RAND.Decompose).
%   weightMode  - 'none','auto','manual'.   Default: 'none'.
%   W           - [nSamples x 1] weight vector if weightMode='manual'.
%   B           - # bootstrap iterations.   Default: 0 (no bootstrapping).
%   alpha       - confidence level for intervals. Default: 0.05 (95% CI).
%
% OUTPUTS:
%   F    - [nFeatures x 1] F-scores (mean if bootstrapped).
%   Fstd - [nFeatures x 1] std of bootstrap F-scores (empty if B=0).
%   Fci  - [nFeatures x 2] [lower upper] CI bounds (empty if B=0).
%
% USAGE EXAMPLE:
%   [F,~,~] = nk_FScoreFeatRank(X,labels);
%   [F,Fstd,Fci] = nk_FScoreFeatRank(X,labels,[],...,'auto',[],100,0.05);
%
% NOTES:
%   - Bootstrapping resamples rows of Y/L/N with replacement.
%   - Weighted helpers for mean/std and Median/IQR computations.
%   - When W=ones(n,1), weighted funcs reduce to unweighted behavior.
%   - Requires nm_nansum for aggregation and global RAND for decomp.
%
% (c) Nikolaos Koutsouleris, 05/2025
% ========================================================================
function [F, Fstd, Fci] = nk_FScoreFeatRankNew(Y, L, N, meantype, decomp, weightMode, W, B, alpha)
    global RAND;
    % ---- Set defaults ----
    if nargin < 3, N = []; end
    if ~exist('meantype','var') || isempty(meantype),    meantype = 1; end
    if ~exist('decomp','var') || isempty(decomp),      decomp  = [];        end
    if ~exist('weightMode','var') || isempty(weightMode), weightMode = 'none'; end
    if ~exist('W','var'),                              W       = [];        end
    if ~exist('B','var') || isempty(B),                B       = 0;         end
    if ~exist('alpha','var') || isempty(alpha),        alpha   = 0.05;      end

    n = size(Y,1);
    % ---- Build weights ----
    switch lower(weightMode)
        case 'none'
            W = ones(n,1);
        case 'auto'
            cls    = unique(L);
            counts = histc(L,cls);
            invf   = 1./counts;
            idx    = arrayfun(@(x)find(cls==x,1), L);
            W      = invf(idx);
            W      = W / mean(W);
        case 'manual'
            assert(~isempty(W) && numel(W)==n, 'Manual weights must match samples');
        otherwise
            error('Unknown weightMode: %s', weightMode);
    end

    % ---- Determine decomposition ----
    classes    = unique(L);
    numClasses = numel(classes);
    if numClasses > 2
        if isfield(RAND,'Decompose') && ~isempty(RAND.Decompose)
            decomp = RAND.Decompose;
        elseif isempty(decomp)
            decomp = 0;
        end
    else
        decomp = 0;
    end

    % ---- Full-score calculator ----
    function f = calcF(Ysub, Lsub, Nsub, Wsub)
        f = computeCoreF(Ysub, Lsub, Wsub, decomp, meantype);
        if ~isempty(Nsub)
            D = zeros(size(Ysub,2), size(Nsub,2));
            for jj = 1:size(Nsub,2)
                D(:,jj) = computeCoreF(Ysub, Nsub(:,jj), Wsub, decomp, meantype);
            end
            f = f ./ nm_nansum(D,2);
        end
    end

    % ---- Compute initial F ----
    F    = calcF(Y, L, N, W);
    Fstd = [];
    Fci  = [];

    % ---- Bootstrapping ----
    if B > 0
        Fs  = zeros(numel(F), B);
        useN = ~isempty(N);
        for b = 1:B
            idx = randsample(n, n, true);
            Yb  = Y(idx,:);
            Lb  = L(idx);
            Wb  = W(idx);
            if useN, Nb = N(idx,:); else, Nb = []; end
            Fs(:,b) = calcF(Yb, Lb, Nb, Wb);
        end
        F    = mean(Fs,2);
        Fstd = std(Fs,0,2);
        lo   = quantile(Fs, alpha/2, 2);
        hi   = quantile(Fs, 1-alpha/2, 2);
        Fci  = [lo, hi];
    end
end

% -------------------------------------------------------------------------
function f = computeCoreF(Ysub, Lsub, Wsub, decomp, meantype)
% computeCoreF: computes aggregated F-score across class decompositions
    classes = unique(Lsub);
    K       = numel(classes);
    if K > 2
        switch decomp
            case 0 % one-vs-all
                A = zeros(size(Ysub,2), K);
                for k = 1:K
                    indP = Lsub == classes(k);
                    indM = ~indP;
                    A(:,k) = computeF(Ysub, indP, indM, Wsub, meantype);
                end
                f = nm_nansum(A,2);
            case 1 % one-vs-one
                P = K*(K-1)/2;
                A = zeros(size(Ysub,2), P);
                cnt = 1;
                for i = 1:K-1
                    for j = i+1:K
                        A(:,cnt) = computeF(Ysub, Lsub==classes(i), Lsub==classes(j), Wsub, meantype);
                        cnt = cnt + 1;
                    end
                end
                f = nm_nansum(A,2);
            otherwise
                error('Unknown decomp mode: %d', decomp);
        end
    else
        f = computeF(Ysub, Lsub==classes(1), Lsub~=classes(1), Wsub, meantype);
    end
end

% -------------------------------------------------------------------------
function F = computeF(Y, indP, indM, W, meantype)
% computeF: evaluates weighted F-score for a binary split

    YP = Y(indP,:); YM = Y(indM,:);
    wP = W(indP);   wM = W(indM);
    if meantype == 1
        [mP, sP] = wNanMoments(YP, wP);
        [mM, sM] = wNanMoments(YM, wM);
    else
        [mP, sP] = wNanMedianIQR(YP, wP);
        [mM, sM] = wNanMedianIQR(YM, wM);
    end
    F  = (mP - mM).^2 ./ (sP + sM);
end

function [m, s] = wNanMoments(X, w)
% % wNanMoments  Compute weighted mean & std ignoring NaNs in one go.
% %   [m, s] = wNanMoments(X, w) returns 1×p vectors of means and
% %   standard deviations for the n×p data matrix X, with n×1 weights w.
% %
% %   Any NaN in X is simply dropped (zeroed) and its weight is removed
% %   from the denominator.
% 
[m, s] = mexWnanMoments(X, w);
end

function [med, iq] = wNanMedianIQR(X, w)
    w = w(:);
    [n, p] = size(X);
    med = nan(1,p);
    iq  = nan(1,p);
    nanMask = isnan(X);
    for j = 1:p
        valid = ~nanMask(:,j);
        xj = X(valid,j);  wj = w(valid);
        if isempty(xj), continue; end
        [xj, idx] = sort(xj);  wj = wj(idx);
        cw = cumsum(wj);  total = cw(end);
        pick = @(fq) xj(find(cw>=fq*total,1,'first'));
        med(j) = pick(0.5);
        iq(j)  = pick(0.75) - pick(0.25);
    end
end
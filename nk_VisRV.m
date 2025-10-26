function [Vmean, V] = nk_VisRV(MD, X, Label)
% nk_VisRV
% Computes a linear approximation of per-feature weights from an RVM model.
% For classification: like nk_VisSV, use min-difference vectors between RVs
% of the two classes (over L1).
% For regression: return a |a|-weighted mean of RVs (a = expansion coeffs).
%
% INPUTS
%   MD    : RVM model with fields MD.P.Relevant (RVs), MD.P.Value (coeffs)
%   X     : training data (N x p), rows correspond to training cases
%   Label : vector of labels/targets used for training (N x 1)
%
% OUTPUTS
%   V     : matrix of min-diff vectors (one per positive-class RV)  [cls]
%           or a single row for regression
%   Vmean : mean of V across rows (1 x p), your linearised "feature weights"

    N = size(X,1); p = size(X,2);
    if ~isfield(MD,'P') || ~isfield(MD.P,'Relevant') || ~isfield(MD.P,'Value')
        error('nk_VisRV: MD.P.Relevant / MD.P.Value not found.');
    end
    RVidx = MD.P.Relevant(:);
    coeff = MD.P.Value(:);

    % Try to detect classification vs regression from labels:
    u = unique(Label(~isnan(Label)));
    isClass = numel(u) == 2;

    if isClass
        % Robustly map to two classes (handles {-1,+1} or {1,2} etc.)
        cneg = min(u); cpos = max(u);
        Lrv  = Label(RVidx);
        posMask = (Lrv == cpos);
        negMask = (Lrv == cneg);

        Xpos = X(RVidx(posMask), :);
        Xneg = X(RVidx(negMask), :);

        oSV = size(Xpos,1);
        iSV = size(Xneg,1);

        if oSV == 0 || iSV == 0
            warning('nk_VisRV: one class has zero RVs; returning zeros.');
            V = zeros(max(oSV,1), p);
            Vmean = mean(V,1);
            return;
        end

        % Compute min-diff vector for each positive-class RV
        V = zeros(oSV, p);
        for j = 1:oSV
            xj = Xpos(j,:);
            % L1 distance to all negative-class RVs
            diffs = bsxfun(@minus, xj, Xneg);        % iSV x p
            L1sum = sum(abs(diffs), 2);              % iSV x 1
            [~, kmin] = min(L1sum);
            V(j,:) = diffs(kmin,:);                  % min-diff vector
        end

        Vmean = mean(V,1);

    else
        % Regression / one-class: |a|-weighted mean of RVs (row vector)
        wabs = abs(coeff);
        wabs = wabs / max(sum(wabs), eps);
        Xrv  = X(RVidx, :);
        V = (wabs(:)'.*ones(1, size(Xrv,1))) * Xrv; % 1 x p, but keep name V
        Vmean = V;  % single-row output
    end
end

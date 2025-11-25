function Dx_sorted = nk_ApplyAlignmentToDx(Dx, groupsPerRef, sign_pair)
% nk_ApplyAlignmentToDx
%   Apply component alignment/sign flips to per-component decision scores Dx.
%
%   Inputs:
%     Dx          : [nSubj x K_src_max] fractionated decision scores
%                   (rows = subjects, columns = shared source j)
%     groupsPerRef: 1 x K_ref cell; for each ref i, list of source indices j
%     sign_pair   : [K_ref x K_src_max] per-pair sign matrix (-1,0,+1)
%
%   Output:
%     Dx_sorted   : [nSubj x K_ref] subject × ref-component decision scores,
%                   aligned to the global ref space and sign-corrected.
%                   Rows with no contributing source remain NaN.

    [nSubj, K_src_max] = size(Dx);
    K_ref = numel(groupsPerRef);

    % start with all-NaN; fill only where we have contributions
    Dx_sorted = nan(nSubj, K_ref, 'like', Dx);

    for i = 1:K_ref
        js = groupsPerRef{i};
        if isempty(js), continue; end

        % keep only in-range indices
        js = js(js >= 1 & js <= K_src_max);
        if isempty(js), continue; end

        % signs for this ref and its sources
        sgn = sign_pair(i, js);          % 1 × #js

        % drop zero-sign pairs (no valid orientation)
        valid = (sgn ~= 0);
        if ~any(valid), continue; end
        js  = js(valid);
        sgn = sgn(valid);

        % extract and sign-correct
        cols = Dx(:, js);                % nSubj × #js
        cols = bsxfun(@times, cols, sgn);% apply sign to each column

        % which subjects have at least one finite value in these columns?
        hasData = any(isfinite(cols), 2);     % nSubj × 1

        if ~any(hasData)
            % no subject has any usable Dx for this ref => leave column NaN
            continue;
        end

        % NaN-safe sum only for subjects with data
        contrib = nan(nSubj, 1, 'like', Dx);
        contrib(hasData) = sum(cols(hasData, :), 2, 'omitnan');

        Dx_sorted(:, i) = contrib;
    end
end

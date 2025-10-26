function nk_VisReportGlobalRefStats(I, I1, h, ilh, sigfl, isInter, n)
% Print corr(ref) and presence only for components that already appeared
% before (i.e., have any finite p in earlier CV1 models of this CV2 fold).

    % --- pull current columns (defensive) ---
    corrNow = []; pvalNow = [];
    if isInter
        if isfield(I1,'VCV1WCORRREF') && numel(I1.VCV1WCORRREF) <= h && ...
           iscell(I1.VCV1WCORRREF{h}) && numel(I1.VCV1WCORRREF{h}) <= n && ...
           ~isempty(I1.VCV1WCORRREF{h}{n})
            corrNow = I1.VCV1WCORRREF{h}{n}(:, ilh);
        end
        if isfield(I1,'VCV1WPERMREF') && numel(I1.VCV1WPERMREF) <= h && ...
           iscell(I1.VCV1WPERMREF{h}) && numel(I1.VCV1WPERMREF{h}) <= n && ...
           ~isempty(I1.VCV1WPERMREF{h}{n})
            pvalNow = I1.VCV1WPERMREF{h}{n}(:, ilh);
        end
    else
        if isfield(I1,'VCV1WCORRREF') && numel(I1.VCV1WCORRREF) >= h && ~isempty(I1.VCV1WCORRREF{h})
            corrNow = I1.VCV1WCORRREF{h}(:, ilh);
        end
        if isfield(I1,'VCV1WPERMREF') && numel(I1.VCV1WPERMREF) >= h && ~isempty(I1.VCV1WPERMREF{h})
            pvalNow = I1.VCV1WPERMREF{h}(:, ilh);
        end
    end

    % --- nothing to report? ---
    nRef = max([numel(corrNow), numel(pvalNow), 0]);
    if nRef == 0
        if isInter
            fprintf('\n\t\t\t(no global reference components to report for modality #%g)', n);
        else
            fprintf('\n\t\t\t(no global reference components to report)');
        end
        return
    end

    % --- CV2 history (presence %) ---
    Wagg  = [];
    if isInter
        haveCV2 = isfield(I,'VCV2WCORRREF') && numel(I.VCV2WCORRREF) >= h && ...
                  iscell(I.VCV2WCORRREF{h}) && numel(I.VCV2WCORRREF{h}) >= n && ...
                  ~isempty(I.VCV2WCORRREF{h}{n});
        if haveCV2, Wagg = I.VCV2WCORRREF{h}{n}; end
    else
        haveCV2 = isfield(I,'VCV2WCORRREF') && numel(I.VCV2WCORRREF) >= h && ~isempty(I.VCV2WCORRREF{h});
        if haveCV2, Wagg = I.VCV2WCORRREF{h}; end
    end
    nCols = size(Wagg,2);

    % --- entry vector (first appearance index per component) ---
    entryV = [];
    if isInter
        if isfield(I,'VCV1ENTRY') && numel(I.VCV1ENTRY) >= h && ...
           iscell(I.VCV1ENTRY{h}) && numel(I.VCV1ENTRY{h}) >= n && ...
           ~isempty(I.VCV1ENTRY{h}{n})
            entryV = I.VCV1ENTRY{h}{n}(:);
        end
    else
        if isfield(I,'VCV1ENTRY') && numel(I.VCV1ENTRY) >= h && ~isempty(I.VCV1ENTRY{h})
            entryV = I.VCV1ENTRY{h}(:);
        end
    end

    % --- gate on prior finite p (any earlier CV1 model in this CV2 fold) ---
    permMat = [];
    if isInter
        hasPermMat = isfield(I1,'VCV1WPERMREF') && numel(I1.VCV1WPERMREF) >= h && ...
                     iscell(I1.VCV1WPERMREF{h}) && numel(I1.VCV1WPERMREF{h}) >= n && ...
                     ~isempty(I1.VCV1WPERMREF{h}{n});
        if hasPermMat, permMat = I1.VCV1WPERMREF{h}{n}; end
    else
        hasPermMat = isfield(I1,'VCV1WPERMREF') && numel(I1.VCV1WPERMREF) >= h && ~isempty(I1.VCV1WPERMREF{h});
        if hasPermMat, permMat = I1.VCV1WPERMREF{h}; end
    end

    for kl = 1:nRef
        % Require ANY finite p-value in columns 1:(ilh-1)
        hasPriorFiniteP = false;
        if ~isempty(permMat) && ilh > 1 && kl <= size(permMat,1)
            prevCols = 1:(ilh-1);
            prevCols = prevCols(prevCols <= size(permMat,2));
            if ~isempty(prevCols)
                hasPriorFiniteP = any(isfinite(permMat(kl, prevCols)));
            end
        end

        % If no prior finite p exists, skip reporting for this component
        if ~hasPriorFiniteP
            continue
        end
        if kl==1
            if exist("n","var") || ~isempty(n)
                fprintf('\n\t\t\tModality #%g - Component summary:', n)
            end
        end
        % Current corr (may be NaN if seed/new-tail)
        ckl = NaN;
        if ~isempty(corrNow) && kl <= numel(corrNow)
            ckl = corrNow(kl);
        end

        % Presence text (optional)
        presTxt = '';
        if haveCV2 && kl <= size(Wagg,1) && nCols > 0
            if ~isempty(entryV) && numel(entryV) >= kl && isfinite(entryV(kl)) && entryV(kl) > 0
                entry = min(max(1, entryV(kl)), nCols);
            else
                entry = 1;
            end
            rng  = entry:nCols;
            if ~isempty(rng)
                kHit    = sum(isfinite(Wagg(kl, rng)));
                kDen    = numel(rng);
                presPct = 100 * (kHit / max(1,kDen));
                presTxt = sprintf(' | pres=%.1f%% (%d/%d CV2)', presPct, kHit, kDen);
            end
        end

        % Print line
        if sigfl && ~isempty(pvalNow) && kl <= numel(pvalNow) && isfinite(pvalNow(kl))
            fprintf('\n\t\t\tComp %3g: p=%.3f | corr(ref)=%s%s', ...
                kl, pvalNow(kl), num2str_or_na(ckl), presTxt);
        else
            if isfinite(ckl)
                fprintf('\n\t\t\tComp %3g: corr(ref)=%.3f%s', kl, ckl, presTxt);
            else
                % Both p and corr missing/NaN → skip (already gated by prior p)
            end
        end
    end
end

function s = num2str_or_na(x)
    if isfinite(x), s = sprintf('%.3f', x); else, s = 'NaN'; end
end

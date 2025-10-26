function [IN, optD, optCrit] = nk_OptPredSeq_v2(D, L, PredGroups, IN, C, nCutOff, Lims, OPTCRIT, Ddesc, CFG)
% =====================================================================================
% FORMAT:
%   [IN, optD, optCrit] = nk_OptPredSeq_v2(D, L, PredGroups, IN, C, nCutOff, Lims, OPTCRIT, Ddesc, CFG)
%
% PURPOSE:
%   Learn or apply a sequential deferral policy over a chain of predictive models.
%   - TRAIN (when IN is [] or missing): learn node order (from C), and per-node
%     propagation bands (percentiles + absolute thresholds).
%   - APPLY (when IN is a trained model): apply learned sequence to new D (optionally
%     with labels L for evaluation).
%
% KEY UPGRADES vs v1:
%   * NaN-safe anchoring & thresholding with robust fallbacks (degenerate anchors handled)
%   * Numeric-only metrics; keep metric name separately for logging only
%   * Config struct (no globals), early stopping (Patience), clearer mode names
%   * Apply-time percentile recalibration (robust to shifts)
%   * Skip empty nodes (no backtracking), vectorized where convenient
%
% INPUTS (differences from v1 in CAPS):
%   D           : [m x p] predictive score matrix (columns = models).
%   L           : [m x 1] labels (optional in APPLY).
%   PredGroups  : [1 x p] or [p x 1] mapping column->node id (e.g., 1..K).
%   IN          : [] for TRAIN; trained model struct for APPLY (see OUTPUTS).
%   C           : [q x r] candidate sequences (rows). Each entry refers to a node id present in PredGroups.
%   nCutOff     : # of steps for each side (lower/upper) w.r.t. anchor (default 5).
%   Lims        : [lower, upper] percentile offsets (default [10 10]).
%   OPTCRIT     : function handle @(y,yhat) -> scalar double (maximized).
%   Ddesc       : cellstr descriptors of models (length = p). Optional.
%   CFG         : struct with fields (all optional; defaults set below):
%                 .Verbose          (true)
%                 .SEQOPT.AnchorType (1=flexible via decision boundary, 2=fixed around median)
%                 .SEQOPT.Aggregation ('replace'|'mean')      % how to combine when deferring
%                 .SEQOPT.OptimizeScope ('local'|'global')    % optimize on band or whole pop
%                 .SEQOPT.Patience (integer, default 3)       % early-stop patience per node
%                 .ApplyMode ('percentile'|'absolute')        % how to threshold at apply
%
% OUTPUTS:
%   IN          : TRAIN: rich result struct + learned model fields (see below).
%                 APPLY: the passed-in model enriched with test-time info.
%   optD        : Final per-case prediction vector after sequential deferral.
%   optCrit     : Final scalar performance (if L provided), else [].
%
% TRAINED MODEL FIELDS (stored in IN):
%   IN.AnalSeq      : learned node sequence (indices into unique nodes in C row).
%   IN.optlvec/optuvec : learned lower/upper percentile locations per node (bands).
%   IN.optlthr/optuthr : corresponding absolute thresholds (computed on training).
%   IN.vecneg/vecpos   : step vectors per node (for debugging/auditing).
%   IN.SEQOPT, IN.ApplyMode, IN.OPTCRIT_name
%   IN.Ddesc, IN.Sequence2Feats (logical mask into D columns), etc.
%
% NOTES:
%   * This is classification-oriented by default but is regression-ready if OPTCRIT is
%     a regression metric (e.g., @(y,yhat) -rmse(y,yhat)) and Aggregation='mean' is used.
%   * For regression, prefer ApplyMode='percentile' + uncertainty-aware selection
%     (extend with your uncertainty estimates where available).
% =====================================================================================

% ----------------------------- Defaults & validation ---------------------------------
if nargin < 3 || isempty(PredGroups), PredGroups = 1:size(D,2); else, PredGroups = PredGroups(:)'; end
if nargin < 4, IN = []; end
if nargin < 5 || isempty(C), C = 1; end
if nargin < 6 || isempty(nCutOff), nCutOff = 5; end
if nargin < 7 || isempty(Lims),    Lims = [10 10]; end
if nargin < 8 || isempty(OPTCRIT), OPTCRIT = @defaultBAC; end
if nargin < 9 || isempty(Ddesc),   Ddesc = cellstr([repmat('Model ', size(D,2),1) num2str((1:size(D,2))')]); end
if nargin < 10 || isempty(CFG),    CFG = struct; end

CFG = fillCFGDefaults(CFG);

if numel(Ddesc) ~= size(D,2)
    error('Ddesc length (%d) must match #columns of D (%d).', numel(Ddesc), size(D,2));
end

[m, p] = size(D);
optCrit = [];

% --------------------------------- APPLY branch --------------------------------------
if isstruct(IN) && isfield(IN,'AnalSeq')
    % Apply a trained model
    MODEL = IN; % alias
    % Select sequence columns
    colsMask = MODEL.Sequence2Feats;
    if isempty(colsMask) || numel(colsMask) ~= p
        % Fallback: rebuild from PredGroups & AnalSeq
        colsMask = false(1,p);
        unodes   = unique(PredGroups);
        for k = 1:numel(MODEL.AnalSeq)
            node = MODEL.AnalSeq(k);
            colsMask = colsMask | (PredGroups == unodes(node));
        end
    end
    Dapp = D(:, colsMask);
    nD   = size(Dapp,2);

    % Initialize apply-time containers
    Nremain = ones(m,1);
    optD    = Dapp(:,1);
    IN.optDh = nan(m, nD);
    IN.optDh(:,1) = optD;

    haveLabels = (nargin>=2) && ~isempty(L);
    if haveLabels
        IN.SeqPerfGain_test     = zeros(1, nD);
        IN.SeqPerfGain_test(1)  = OPTCRIT(L, optD);
    end

    % Node-by-node deferral
    for j = 1:nD-1
        fI   = find(Nremain == j);
        if isempty(fI), IN.optDh(:,j+1) = optD; continue; end

        DI = Dapp(:, j);
        % Thresholds: percentile recalibration (recommended) or absolute
        if strcmpi(CFG.ApplyMode,'percentile')
            lthr = prc_omitnan(DI, IN.optlvec(j));
            uthr = prc_omitnan(DI, IN.optuvec(j));
        else
            lthr = IN.optlthr(j);
            uthr = IN.optuthr(j);
        end
        if ~isfinite(lthr) || ~isfinite(uthr) || lthr > uthr
            IN.optDh(:,j+1) = optD; continue;
        end

        ind  = DI(fI) >= lthr & DI(fI) <= uthr;
        fII  = fI(ind);
        if isempty(fII), IN.optDh(:,j+1) = optD; continue; end

        % Aggregation
        switch lower(CFG.SEQOPT.Aggregation)
            case 'replace'
                optD(fII) = Dapp(fII, j+1);
            case 'mean'
                optD(fII) = nm_nanmean([Dapp(fII, j) Dapp(fII, j+1)], 2);
            otherwise
                error('Unknown Aggregation: %s', CFG.SEQOPT.Aggregation);
        end
        Nremain(fII) = j+1;
        IN.optDh(:,j+1) = optD;

        if haveLabels
            IN.SeqPerfGain_test(j+1) = OPTCRIT(L, optD);
        end
    end

    IN.Nremain_test = Nremain;
    if haveLabels, optCrit = IN.SeqPerfGain_test(end); end
    return;
end

% --------------------------------- TRAIN branch --------------------------------------
% Build candidate sequences over nodes indicated by C rows
nC = size(C,1);
best = [];
bestScore = -Inf;

for j = 1:nC
    Cj  = C(j, ~isnan(C(j,:)));      % row j, remove NaNs
    uC  = unique(Cj);                % unique node ids in this sequence row
    jC  = false(1, numel(PredGroups));
    for jj = 1:numel(uC)
        jC = jC | (PredGroups == uC(jj));
    end
    jD = D(:, jC);                  % models participating in this sequence
    nD = size(jD,2);

    if CFG.Verbose
        fprintf('\nSeq %d/%d: %s', j, nC, strjoin(Ddesc(jC), ', '));
    end

    % Build anchors & LL/UL bounds per model
    [Anchor, LL, UL] = build_anchor_bounds(jD, Lims, CFG.SEQOPT.AnchorType);

    % Build step vectors (robust, always non-empty)
    [vecneg, vecpos] = build_step_vectors(Anchor, LL, UL, nCutOff);

    % Initial performance at node 1
    OPT_first = OPTCRIT(L, jD(:,1));

    % Initialize per-sequence container (training state)
    R = struct();
    R.Sequence       = Cj;
    R.Sequence2Feats = jC;
    R.D              = jD;            % scores across nodes in this seq
    R.vecneg         = vecneg;
    R.vecpos         = vecpos;

    R.OPT            = OPT_first;     % current all-pop metric
    R.allOPTs        = OPT_first;     % book-keeping per node
    R.diffOPTs       = 0;
    R.optD           = jD(:,1);       % current working predictions
    R.optDh          = nan(m, nD);    % history per hop
    R.optDh(:,1)     = R.optD;
    R.Nremain        = ones(m,1);     % current node index per case

    R.optlvec        = zeros(1, nD);  % learned percentile locations
    R.optuvec        = zeros(1, nD);
    R.optlthr        = zeros(1, nD);  % absolute thresholds corresponding to learned percentiles (on training data)
    R.optuthr        = zeros(1, nD);

    % Optimize deferral thresholds node-by-node
    for I = 1:nD-1
        R = optimize_node(R, I, L, OPTCRIT, CFG);
    end

    % Summaries
    R.uN           = unique(R.Nremain)';       % unique node positions after deferral
    R.AnalSeq      = R.Sequence(R.uN);         % realized node order (subset)
    R.AnalSeqDesc  = Ddesc(R.Sequence2Feats);  % approx: participating feature columns
    R.examsfreq    = arrayfun(@(k) 100*sum(R.Nremain==k)/m, 1:nD);

    if CFG.Verbose
        fprintf('\n  Final %s = %.4f', CFG.OPTCRIT_name, R.OPT);
    end

    if R.OPT > bestScore
        bestScore = R.OPT;
        best      = R;
    end
end

% Build final IN (trained model + training analysis)
IN = best;
IN.SEQOPT         = CFG.SEQOPT;
IN.ApplyMode      = CFG.ApplyMode;
IN.OPTCRIT_name   = CFG.OPTCRIT_name;
IN.Ddesc          = Ddesc;

% Return outputs expected by original API
optD   = IN.optD;
optCrit = IN.OPT;

% ------------------------------------------------------------------------------------
% Helpers
% ------------------------------------------------------------------------------------
function CFG = fillCFGDefaults(CFG)
    if ~isfield(CFG,'Verbose'), CFG.Verbose = true; end
    if ~isfield(CFG,'ApplyMode'), CFG.ApplyMode = 'percentile'; end
    if ~isfield(CFG,'SEQOPT'), CFG.SEQOPT = struct; end
    if ~isfield(CFG.SEQOPT,'AnchorType'),     CFG.SEQOPT.AnchorType = 1; end % 1=flexible, 2=fixed median
    if ~isfield(CFG.SEQOPT,'Aggregation'),    CFG.SEQOPT.Aggregation = 'replace'; end
    if ~isfield(CFG.SEQOPT,'OptimizeScope'),  CFG.SEQOPT.OptimizeScope = 'local'; end
    if ~isfield(CFG.SEQOPT,'Patience'),       CFG.SEQOPT.Patience = 3; end
    if ~isfield(CFG,'OPTCRIT_name'),          CFG.OPTCRIT_name = 'OPTCRIT'; end
end

function [Anchor, LL, UL] = build_anchor_bounds(jD, Lims, AnchorType)
    [m, nD] = size(jD);
    Anchor = zeros(1,nD); LL = zeros(1,nD); UL = zeros(1,nD);
    switch AnchorType
        case 1  % Flexible anchoring around decision boundary (0) for classifiers
            for z = 1:nD
                x  = jD(:,z);
                xf = x(isfinite(x));
                nfin = numel(xf);
                if nfin == 0
                    % Degenerate column: anchor at median; set +/- Lims
                    Anchor(z) = 50;
                    LL(z)     = max(0, 50 - Lims(1));
                    UL(z)     = min(100, 50 + Lims(2));
                    continue;
                end
                Anchor(z) = 100 * sum(xf < 0) / nfin;

                % Lower side
                Lthr = xf(xf < 0);
                if isempty(Lthr)
                    LL(z) = max(0, Anchor(z) - Lims(1));
                else
                    pLthr = prc_omitnan(Lthr, 100 - Lims(1));
                    if ~isfinite(pLthr)
                        LL(z) = max(0, Anchor(z) - Lims(1));
                    else
                        LL(z) = 100 * sum(xf <= pLthr) / nfin;
                    end
                end

                % Upper side
                Uthr = xf(xf > 0);
                if isempty(Uthr)
                    UL(z) = min(100, Anchor(z) + Lims(2));
                else
                    pUthr = prc_omitnan(Uthr, Lims(2));
                    if ~isfinite(pUthr)
                        UL(z) = min(100, Anchor(z) + Lims(2));
                    else
                        UL(z) = 100 * sum(xf <= pUthr) / nfin;
                    end
                end

                % Clamps
                LL(z) = min(LL(z), Anchor(z));
                UL(z) = max(UL(z), Anchor(z));
                LL(z) = max(0,   LL(z));
                UL(z) = min(100, UL(z));
            end
        case 2  % Fixed percentile anchoring around median
            Anchor = repmat(50,1,nD);
            LL     = max(0,  Anchor - Lims(1));
            UL     = min(100, Anchor + Lims(2));
        otherwise
            error('Unknown AnchorType: %d', AnchorType);
    end
end

function [vecneg, vecpos] = build_step_vectors(Anchor, LL, UL, nCutOff)
    nD = numel(Anchor);
    vecneg = cell(1,nD); vecpos = cell(1,nD);
    for z = 1:nD
        % Use linspace so vectors are never empty; drop the first (anchor) entry.
        vn = linspace(Anchor(z), LL(z), nCutOff+1);
        vp = linspace(Anchor(z), UL(z), nCutOff+1);
        if numel(vn)>1, vn(1)=[]; end
        if numel(vp)>1, vp(1)=[]; end

        % Final minimal safeguards
        if isempty(vn) || Anchor(z) <= LL(z)
            vn = Anchor(z) : -max((Anchor(z)-LL(z))/(max(1,nCutOff)), eps) : LL(z);
            if ~isempty(vn), vn(1)=[]; end
        end
        if isempty(vp) || Anchor(z) >= UL(z)
            vp = Anchor(z) :  max((UL(z)-Anchor(z))/(max(1,nCutOff)), eps) : UL(z);
            if ~isempty(vp), vp(1)=[]; end
        end
        vecneg{z} = vn; vecpos{z} = vp;
    end
end

function R = optimize_node(R, I, L, OPTCRIT, CFG)
    % Optimize deferral band for node I -> I+1
    fI = find(R.Nremain == I);
    if isempty(fI)
        % Nothing to optimize at this node
        R.optDh(:,I+1) = R.optD;
        return
    end

    DI   = R.D(:, I);
    jDI  = DI(fI); jDI = jDI(isfinite(jDI));
    if isempty(jDI)
        R.optDh(:,I+1) = R.optD;
        return
    end

    best_gain = -Inf;
    pat = 0; P = numel(R.vecneg{I});
    best = struct('lvec',NaN,'uvec',NaN,'lthr',NaN,'uthr',NaN, ...
                  'Nremain',R.Nremain,'D',R.optD,'allOPT',R.OPT);

    for j = 1:P
        lthr = prc_omitnan(jDI, R.vecneg{I}(j));
        uthr = prc_omitnan(jDI, R.vecpos{I}(j));
        if ~isfinite(lthr) || ~isfinite(uthr) || lthr > uthr, continue; end

        fII  = fI(DI(fI) >= lthr & DI(fI) <= uthr);
        if isempty(fII), continue; end

        % Aggregate predictions for fII
        jD = R.optD;
        switch lower(CFG.SEQOPT.Aggregation)
            case 'replace'
                jD(fII) = R.D(fII, I+1);
            case 'mean'
                jD(fII) = nm_nanmean([R.D(fII, I) R.D(fII, I+1)], 2);
            otherwise
                error('Unknown Aggregation: %s', CFG.SEQOPT.Aggregation);
        end

        % Score gain
        switch lower(CFG.SEQOPT.OptimizeScope)
            case 'local'
                prev  = OPTCRIT(L(fII), R.optD(fII));
                now   = OPTCRIT(L(fII), jD(fII));
            case 'global'
                prev  = R.OPT;
                now   = OPTCRIT(L, jD);
            otherwise
                error('Unknown OptimizeScope: %s', CFG.SEQOPT.OptimizeScope);
        end
        gain = now - prev;

        if gain > best_gain
            best_gain = gain; pat = 0;
            best.lvec = R.vecneg{I}(j);  best.uvec = R.vecpos{I}(j);
            best.lthr = lthr;            best.uthr = uthr;
            best.D    = jD;
            best.allOPT = OPTCRIT(L, jD);
            best.Nremain       = R.Nremain; best.Nremain(fII) = I+1;
            if CFG.Verbose
                fprintf('\n  Node %d→%d: gain=%.4f, band=[%.4f, %.4f], |prop|=%d', ...
                        I, I+1, gain, lthr, uthr, numel(fII));
            end
        else
            pat = pat + 1;
            if pat >= CFG.SEQOPT.Patience
                break;
            end
        end
    end

    % Commit best (if any)
    if isfinite(best_gain) && best_gain > -Inf
        R.optlvec(I) = best.lvec;   R.optuvec(I) = best.uvec;
        R.optlthr(I) = best.lthr;   R.optuthr(I) = best.uthr;
        R.optD       = best.D;
        R.optDh(:,I+1) = best.D;
        R.Nremain    = best.Nremain;
        R.diffOPTs(I)= best.allOPT - R.OPT;
        R.OPT        = best.allOPT;
        R.allOPTs(I) = best.allOPT;
    else
        % No improvement: carry forward unchanged
        R.optDh(:,I+1) = R.optD;
        R.optlvec(I) = NaN; R.optuvec(I) = NaN;
        R.optlthr(I) = NaN; R.optuthr(I) = NaN;
        R.allOPTs(I) = R.OPT;
        R.diffOPTs(I)= 0;
    end
end

function t = prc_omitnan(x, p)
    % x is a vector; compute p-th percentile, NaN-safe
    x = x(:);
    x = x(isfinite(x));
    if isempty(x)
        t = NaN;
    else
        % prctile in MATLAB ignores NaNs if we removed them; returns scalar
        t = prctile(x, p);
    end
end

function b = defaultBAC(y, s)
    % Simple balanced accuracy for +/-1 labels (fallback).
    % You should pass your own OPTCRIT instead of relying on this fallback.
    y  = y(:); s = s(:);
    pos = (y==1); neg = (y==-1);
    if ~any(pos) || ~any(neg)
        b = NaN; return;
    end
    % default decision boundary at 0; adjust to your scores if needed
    yhat = sign(s);
    TPR = mean(yhat(pos) == 1);
    TNR = mean(yhat(neg) == -1);
    b = 0.5*(TPR+TNR);
end

end

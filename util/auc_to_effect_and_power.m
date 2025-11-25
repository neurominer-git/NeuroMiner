function T = auc_to_effect_and_power(N, AUC, varargin)
% auc_to_effect_and_power  Convert AUC(N) to effect sizes & statistical power, with optional plotting and CSV.
%
% PURPOSE
%   For each simulated point (N, AUC), compute:
%     • Effect sizes: d' and Cohen's d (equal-variance binormal model; d'=Cohen's d)
%     • SE(AUC), z-statistic vs H0:AUC=0.5, Wald CI
%     • Statistical power for testing AUC > 0.5 (one- or two-sided), using empirical SE if provided
%   Also supports:
%     • Optional design-effect (DE) inflation of SE to reflect multi-site clustering (ICC)
%       or replacing pair counts with Neff (do one or the other, not both).
%     • Optional plots (AUC curve + CI, effect-size curve + CI, power curve)
%     • Optional CSV export via writetable
%
% INPUTS
%   N    : vector of total sample sizes (Kx1 or 1xK)
%   AUC  : vector of AUC values in (0,1), same length as N
%
% NAME–VALUE OPTIONS (all optional)
%   'Prev'        : prevalence π of positives; scalar or vector length K. Default 0.10
%   'Alpha'       : significance level. Default 0.05
%   'Tail'        : 'one' or 'two' (test of AUC > 0.5 vs AUC ≠ 0.5). Default 'two'
%   'Plot'        : true/false to show plots. Default true
%   'PlotWhat'    : 'all'|'auc'|'effect'|'power'. Default 'all'
%   'WriteCSV'    : true/false to write CSV. Default false
%   'CSVFile'     : filename for CSV. Default 'AUC_effectsize_power.csv'
%   'SiteSizes'   : vector of site sizes (enables site adjustment if paired with ICC)
%   'ICC'         : intraclass correlation (0..1) (enables site adjustment if paired with SiteSizes)
%   'UseNeffPairs': true/false. If true, compute pair counts using Neff and DO NOT inflate SE by DE.
%                   If false (default), keep N for pairs and inflate SE by sqrt(DE).
%   --- Empirical uncertainty (choose one; precedence: FoldAUC > AUC_CI > AUC_SE) ---
%   'FoldAUC'     : cell array Kx1; FoldAUC{k} is vector of CV AUCs at N(k)
%   'AUC_CI'      : Kx2 matrix of empirical [lo, hi] AUC CIs
%   'AUC_SE'      : Kx1 vector of empirical SEs of AUC means
%
% OUTPUT
%   T : table with columns:
%       N, prev, n_pos, n_neg, AUC, dprime, cohen_d, SE_used, z_obs,
%       power_one, power_two, power (selected by 'Tail'), AUC_CI_lo, AUC_CI_hi,
%       (optional) DE, Neff
%
% NOTES
%   • d' = sqrt(2)*norminv(AUC); under equal variances, d' = Cohen's d.
%   • If you provide empirical uncertainty (FoldAUC / AUC_CI / AUC_SE), those drive SE, CIs, and power.
%   • If you also provide SiteSizes+ICC, either inflate SE by sqrt(DE) (default) OR replace pair counts with Neff.

% -------------------- Parse inputs --------------------
p = inputParser;
addParameter(p, 'Prev',      0.10, @(x) isnumeric(x) && isvector(x) && all(x>0 & x<1));
addParameter(p, 'Alpha',     0.05, @(x) isnumeric(x) && isscalar(x) && x>0 && x<1);
addParameter(p, 'Tail',     'two', @(s) any(strcmpi(s,{'one','two'})));
addParameter(p, 'Plot',      true,  @(x) islogical(x) || ismember(x,[0 1]));
addParameter(p, 'PlotWhat', 'all',  @(s) any(strcmpi(s,{'all','auc','effect','power'})));
addParameter(p, 'WriteCSV',  false, @(x) islogical(x) || ismember(x,[0 1]));
addParameter(p, 'CSVFile',  'AUC_effectsize_power.csv', @(s) ischar(s) || isstring(s));
addParameter(p, 'SiteSizes', [],   @(x) isvector(x) || isempty(x));
addParameter(p, 'ICC',       [],   @(x) (isnumeric(x) && isscalar(x)) || isempty(x));
addParameter(p, 'UseNeffPairs', false, @(x) islogical(x) || ismember(x,[0 1]));
% Empirical uncertainty
addParameter(p, 'FoldAUC',   [], @(c) iscell(c) || isempty(c));
addParameter(p, 'AUC_CI',    [], @(x) (ismatrix(x) && size(x,2)==2) || isempty(x));
addParameter(p, 'AUC_SE',    [], @(x) isvector(x) || isempty(x));
parse(p, varargin{:});

alpha     = p.Results.Alpha;
tail      = lower(p.Results.Tail);
doPlot    = p.Results.Plot;
plotWhat  = lower(p.Results.PlotWhat);
doCSV     = p.Results.WriteCSV;
csvFile   = string(p.Results.CSVFile);
siteSz    = p.Results.SiteSizes;
icc       = p.Results.ICC;
useNeff   = p.Results.UseNeffPairs;
FoldAUC   = p.Results.FoldAUC;
AUC_CI_in = p.Results.AUC_CI;
AUC_SE_in = p.Results.AUC_SE;

N   = N(:);
AUC = AUC(:);
K   = numel(N);
if numel(AUC) ~= K
    error('N and AUC must have the same length.');
end

% Prev: scalar or vector -> column vector of length K
prev_in = p.Results.Prev;
if isscalar(prev_in)
    prev_vec = repmat(prev_in, K, 1);
else
    prev_vec = prev_in(:);
    if numel(prev_vec) ~= K
        error('Prev must be a scalar or a vector with the same length as N.');
    end
end

% Guard: clip AUC slightly away from {0,1} for stability in norminv
epsA = 1e-9;
AUC  = max(min(AUC, 1 - epsA), epsA);

% -------------------- Effect sizes (from point AUC) --------------------
dprime  = sqrt(2) .* norminv(AUC);  % SDT mapping
cohen_d = dprime;                   % equal-variance assumption

% -------------------- Determine SE source (empirical preferred) --------
SE_used   = [];
AUC_lo_in = [];
AUC_hi_in = [];

if ~isempty(FoldAUC)
    if numel(FoldAUC) ~= K
        error('FoldAUC must have one cell per N/AUC point.');
    end
    SE_used = nan(K,1);
    for k = 1:K
        v = FoldAUC{k};
        v = v(:); v = v(~isnan(v));
        if numel(v) < 2
            SE_used(k) = NaN;           % will backfill later if all missing
        else
            SE_used(k) = std(v,0) / sqrt(numel(v));  % SE of mean AUC across folds
        end
    end
elseif ~isempty(AUC_CI_in)
    if size(AUC_CI_in,1) ~= K || size(AUC_CI_in,2) ~= 2
        error('AUC_CI must be Kx2 [lo, hi].');
    end
    AUC_lo_in = AUC_CI_in(:,1);
    AUC_hi_in = AUC_CI_in(:,2);
    SE_used   = (AUC_hi_in - AUC_lo_in) / (2*1.96);  % back-calc Wald SE
elseif ~isempty(AUC_SE_in)
    SE_used = AUC_SE_in(:);
    if numel(SE_used) ~= K
        error('AUC_SE must have length K.');
    end
end

% If still no SE, fall back to Hanley–McNeil variance
if isempty(SE_used)
    % Pair counts from prevalence (raw N for now; site adjustment handled below)
    n_pos_tmp = max(1, round(prev_vec .* N));
    n_neg_tmp = max(1, N - n_pos_tmp);

    Q1 = AUC ./ (2 - AUC);
    Q2 = 2 .* (AUC.^2) ./ (1 + AUC);
    VarAUC_HM = ( AUC .* (1 - AUC) ...
                + (n_pos_tmp - 1) .* (Q1 - AUC.^2) ...
                + (n_neg_tmp - 1) .* (Q2 - AUC.^2) ) ./ (n_pos_tmp .* n_neg_tmp);
    SE_used = sqrt(max(VarAUC_HM, 0));
end

% -------------------- Site effects (optional) ---------------------------
DE = []; Neff = [];   % single DE/Neff for the whole experiment (can be extended if needed)
if ~isempty(siteSz) && ~isempty(icc)
    siteSz = siteSz(:);
    mbar = mean(siteSz);
    cv   = std(siteSz) / mbar;
    DE   = 1 + (mbar * (1 + cv^2) - 1) * icc;
    Neff = sum(siteSz) / DE;

    if useNeff
        % Use Neff for pair counts (no SE inflation)
        % (Handled later when computing n_pos/n_neg per N)
    else
        % Variance inflation mode: keep N for pairs but inflate SE
        SE_used = sqrt(DE) .* SE_used;
    end
end

% -------------------- z, power, and CIs -------------------------------
% Pair counts per N (possibly using Neff if requested)
n_pos = nan(K,1); n_neg = nan(K,1);
for k = 1:K
    if ~isempty(DE) && useNeff
        N_pairs = Neff;  % scalar applied at each N (can be extended to vary by N)
    else
        N_pairs = N(k);
    end
    n_pos(k) = max(1, round(prev_vec(k) * N_pairs));
    n_neg(k) = max(1, round(N_pairs - n_pos(k)));
end

% z-statistic and power (plug-in at observed AUC using SE_used)
z_obs = (AUC - 0.5) ./ SE_used;
delta = z_obs;
c_one = norminv(1 - alpha);
c_two = norminv(1 - alpha/2);

power_one = 1 - normcdf(c_one - delta);
power_two = 1 - normcdf(c_two - delta) + normcdf(-c_two - delta);

% Choose CI band for plotting/report:
%  - If empirical CI provided, use it; else Wald from SE_used.
if isempty(AUC_lo_in) || isempty(AUC_hi_in)
    AUC_CI_lo = AUC - 1.96 .* SE_used;
    AUC_CI_hi = AUC + 1.96 .* SE_used;
    ci_label  = '95% CI (Wald)';
else
    AUC_CI_lo = AUC_lo_in;
    AUC_CI_hi = AUC_hi_in;
    ci_label  = '95% CI (empirical)';
end

% -------------------- Assemble output table ---------------------------
T = table(N, prev_vec, n_pos, n_neg, AUC, dprime, cohen_d, SE_used, z_obs, ...
          power_one, power_two, AUC_CI_lo, AUC_CI_hi);

T.Properties.VariableNames{2} = 'prev';

% Convenience 'power' column based on 'Tail'
switch tail
    case 'one', T.power = T.power_one;
    otherwise,  T.power = T.power_two;
end

% Include DE/Neff columns when used
if ~isempty(DE),   T.DE   = repmat(DE,   K, 1); end
if ~isempty(Neff), T.Neff = repmat(Neff, K, 1); end

% -------------------- CSV (optional) -----------------------------------
if doCSV
    try
        writetable(T, csvFile);
        fprintf('Wrote CSV: %s\n', csvFile);
    catch ME
        warning('Could not write CSV (%s): %s', csvFile, ME.message);
    end
end

% -------------------- Plotting (optional) ------------------------------
if doPlot
    wantAUC    = strcmp(plotWhat,'all') || strcmp(plotWhat,'auc');
    wantEffect = strcmp(plotWhat,'all') || strcmp(plotWhat,'effect');
    wantPower  = strcmp(plotWhat,'all') || strcmp(plotWhat,'power');

    % Helper for prevalence text
    if all(abs(prev_vec - prev_vec(1)) < 1e-12)
        prev_txt = sprintf('prev=%.2f', prev_vec(1));
    else
        prev_txt = 'prev varies';
    end

    % AUC + CI
    if wantAUC
        figure; hold on;
        [Ns, idx] = sort(N); lo = AUC_CI_lo(idx); hi = AUC_CI_hi(idx); mu = AUC(idx);
        patch([Ns; flipud(Ns)], [lo; flipud(hi)], [0.85 0.85 1], ...
              'EdgeColor','none','FaceAlpha',0.35, 'DisplayName',ci_label);
        plot(Ns, mu, 'b-o','LineWidth',1.5,'DisplayName','AUC');
        yline(0.5,'k--','Chance');
        xlabel('Total N'); ylabel('AUC'); grid on;
        legend('Location','southeast');
        suf = "";
        if ~isempty(DE), suf = suf + ", DE applied"; end
        title("AUC vs N (" + ci_label + suf + ")");
    end

    % Effect size (d' = Cohen's d)
    if wantEffect
        % Optional CI for d': transform AUC CI endpoints
        d_lo = sqrt(2) .* norminv(max(min(AUC_CI_lo, 1-epsA), epsA));
        d_hi = sqrt(2) .* norminv(max(min(AUC_CI_hi, 1-epsA), epsA));
        [Ns, idx] = sort(N); dlo = d_lo(idx); dhi = d_hi(idx); dmu = dprime(idx);

        figure; hold on;
        patch([Ns; flipud(Ns)], [dlo; flipud(dhi)], [0.85 1 0.85], ...
              'EdgeColor','none','FaceAlpha',0.35, 'DisplayName','95% CI (via AUC CI)');
        plot(Ns, dmu, 'g-o','LineWidth',1.5,'DisplayName','d'' ( = Cohen''s d )');
        xlabel('Total N'); ylabel('Effect size (standardized)'); grid on;
        legend('Location','southeast');
        title("Effect size vs N");
    end

    % Power plot
    if wantPower
        figure; hold on;
        h1 = plot(N, power_one, 'o-','LineWidth',1.5,'DisplayName','One-sided power');
        h2 = plot(N, power_two, 's-','LineWidth',1.5,'DisplayName','Two-sided power');
        if strcmp(tail,'one')
            h3 = plot(N, power_one, 'k-','LineWidth',2,'DisplayName','Selected (Tail=one)');
        else
            h3 = plot(N, power_two, 'k-','LineWidth',2,'DisplayName','Selected (Tail=two)');
        end
        xlabel('Total N'); ylabel('Power'); grid on; ylim([0 1]);
        legend([h1 h2 h3], 'Location','southeast');

        suf = '';                              % suffix for title
        if ~isempty(DE), suf = [suf ', DE applied']; end
        if ~isempty(FoldAUC) || ~isempty(AUC_CI_in) || ~isempty(AUC_SE_in)
            suf = [suf ', empirical SE'];
        else
            suf = [suf ', HM SE'];
        end
        title(sprintf('Statistical power vs. N (\\alpha=%.3f, %s%s)', alpha, prev_txt, suf));
    end
end
end

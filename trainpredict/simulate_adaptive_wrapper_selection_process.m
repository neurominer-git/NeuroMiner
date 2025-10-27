%% Demo: visualize adaptive wrapper dynamics over time
% - Simulates a forward-like loop
% - Tracks r-vector updates using φ(s)
% - Adds synthetic high-similarity (near-duplicate) features
% - Plots: r heatmap, r stats/optparam, penalty curve vs similarity density, lambda_eff

clear; clc; rng(7);

%% ---------- Synthetic data & similarity ----------
n  = 300;                 % samples
p0 = 120;                 % initial features (before adding near-duplicates)
X  = randn(n,p0);

% Create some correlated groups to make the similarity meaningful
for g = 1:4
    idx = (1:20) + (g-1)*20;
    X(:,idx) = X(:,idx) + 0.8*randn(n,1); % shared latent factor
end

%% ---------- High-similarity synthetic features (near-duplicates) ----------
% We will create near-duplicates X_dup = zscore(X_base) + sigma*randn, so corr ≈ 1/sqrt(1+sigma^2).
% Target corr rdup => sigma = sqrt(1/rdup^2 - 1).
n_bases      = 6;         % number of base features to duplicate
dups_perBase = 3;         % how many duplicates per base
rdup_target  = 0.97;      % desired correlation between duplicate and base (≈ very high similarity)
sigma_dup    = sqrt(max(1/(rdup_target^2) - 1, 0)); % derive noise std from target r

base_candidates = 1:p0;
base_idx = base_candidates(randperm(p0, n_bases));

X_dup_all = [];
dup_map   = [];  % [col_index_base, col_index_new] (for reference)
for b = 1:numel(base_idx)
    j = base_idx(b);
    xb = zscore(X(:,j), 0, 1);  % standardize base so formula holds
    for d = 1:dups_perBase
        dup = xb + sigma_dup*randn(n,1);   % near-duplicate
        X_dup_all = [X_dup_all dup];       %#ok<AGROW>
        dup_map   = [dup_map; j, p0 + size(X_dup_all,2)]; %#ok<AGROW>
    end
end

X  = [X X_dup_all];
p  = size(X,2);

% Re-standardize features for downstream computations
Xz = zscore(X,0,1);

% Similarity matrix S = |corr| among features
S  = abs(corr(Xz,'rows','pairwise'));  % p x p
S(1:p+1:end) = 0;                      % zero self-similarity
S = min(1, max(0, S));                 % clip to [0,1] for safety

%% ---------- Ground-truth signal for scoring ----------
true_feats = [5 17 26 43 58 77 95 111];      % “informative” features (keep on original cols)
beta_true  = zeros(p,1); beta_true(true_feats) = 0.8;
y          = Xz * beta_true + 0.4*randn(n,1);

% A cheap “validation score” proxy per candidate: corr^2 with y
base_val = (corr(Xz, y, 'rows','pairwise')).^2;   % p x 1 in [0..1]

%% ---------- Adaptive parameters (forward flavor) ----------
gamma   = 0.98;      % decay
eta0    = 1e-3;      % drift
eta1    = 5e-3;      % similarity bump scale (set 0 to disable penalty)
rmax    = 10;        % cap on refusal
AutoLam = true;      % auto-λ on/off
LamC    = 0.8;       % auto-λ scale

% Penalty function φ(s): ultra-smooth asymmetric (erf gates)
c = 0.55; w = 0.15;
beta_well = 1.0; 
beta_hi   = 1.0;
sigma_lo  = w/3;     % softness of window edges
sigma_hi  = 0.08;    % softness of high-sim ramp

phi_fun = @(s) redundancy_penalty_asym_ultrasmooth(s, c, w, beta_well, beta_hi, sigma_lo, sigma_hi);

%% ---------- Natural stop config (for reference; not terminating here) ----------
Stop.TauAbs   = 0;     % absolute tolerance
Stop.UseMAD   = true;  % MAD band
Stop.MADWinsz = 8;     
Stop.Zmad     = 2.0;
Stop.hist     = [];
Stop.Patience = 0;     % not used in this demo (we don't stop early here)

%% ---------- Simulation loop ----------
T   = 60;                 % iterations
Ssel = false(p,1);        % selected mask
r    = zeros(p,1);        % refusal vector
Rhist = zeros(p,T);       % refusal history
optparam = 0;             % best score so far
opt_hist = zeros(T,1);    % store best score
lam_hist = zeros(T,1);    % λ_eff over time
sel_hist = zeros(T,1);    % selected feature each iter

for t = 1:T
    % Candidate pool = not yet selected
    pool = find(~Ssel);
    if isempty(pool), break; end

    % Raw candidate scores (use base_val; you could recompute each round if needed)
    val = base_val(pool);

    % Refusal per candidate
    rsub = r(pool);

    % Effective lambda (auto or manual)
    if AutoLam
        sig = mad(val,1) * 1.4826;  % robust sigma ≈ MAD
        lam = LamC * sig / max(1 + median(rsub), eps);
    else
        lam = 0.5;
    end
    lam_hist(t) = lam;

    % Penalized ranking
    [~, ord] = sort(val - lam * rsub, 'descend');
    j_sel = pool(ord(1));           % winner this round
    sel_hist(t) = j_sel;

    % Form “ensemble” score proxy for accepted block (1 feature here)
    param = val(ord(1));            % best raw val
    raw_impr = param - optparam;
    if param > optparam
        optparam = param;
        % update natural-stop history with accepted improvement
        Stop.hist = [Stop.hist; raw_impr];
        if numel(Stop.hist) > Stop.MADWinsz
            Stop.hist = Stop.hist(end-Stop.MADWinsz+1:end);
        end
    end
    opt_hist(t) = optparam;

    % --------- Adaptive update (forward): r ← γ r + η0 + η1*(1-w_t)*φ(s) ---------
    r = gamma*r + eta0;

    % rank-weight for this accepted candidate (only 1 here => w_t = 1/numCandidates)
    w_t = 1 / max(1, numel(pool));
    si  = S(:, j_sel);             % similarity of all features to the chosen one
    pen = phi_fun(si);             % φ(s)
    r   = r + eta1 * (1 - w_t) * pen;

    % Cap refusal
    r = min(r, rmax);

    % Mark selected and store history
    Ssel(j_sel) = true;
    Rhist(:,t)  = r;
end

%% ---------- Plots ----------
tvec = 1:T;

figure('Color','w','Position',[80 80 1200 700]);

% (1) Heatmap of r over time (mark selections)
subplot(2,2,1);
imagesc(Rhist); axis tight; colorbar;
xlabel('iteration'); ylabel('feature index'); title('Refusal r (feature × time)');
hold on;
plot(tvec, sel_hist, 'w.', 'MarkerSize', 12); % mark selected feature each iter

% (2) r statistics and optparam over time
subplot(2,2,2); hold on; grid on; box off;
plot(tvec, max(Rhist,[],1), 'LineWidth', 1.8, 'DisplayName','max(r)');
plot(tvec, mean(Rhist,1),   'LineWidth', 1.8, 'DisplayName','mean(r)');
yyaxis right;
plot(tvec, opt_hist, 'LineWidth', 1.8, 'LineStyle','--', 'DisplayName','best score');
ylabel('best score');
yyaxis left; ylabel('refusal');
xlabel('iteration'); title('Refusal stats and best score'); legend('Location','best');

% (3) penalty function φ(s) and current similarity profile (robust KDE)
subplot(2,2,3); hold on; grid on; box off;
sgrid = linspace(0,1,600);
plot(sgrid, phi_fun(sgrid), 'LineWidth', 2, 'DisplayName','\phi(s)');
% show similarities to last selected feature (robust to numeric edge cases)
if any(sel_hist)
    last_sel = sel_hist(find(sel_hist,1,'last'));
    ss = S(:, last_sel);

    % Clip to [0,1] to satisfy ksdensity's Support constraint
    ss = max(0, min(1, ss));

    % Scale factor to overlay on φ(s)
    scale = max(abs(phi_fun(sgrid)));
    if ~isfinite(scale) || scale <= 0, scale = 1; end

    try
        % If there is spread, use KDE with boundary correction
        if any(isfinite(ss)) && (max(ss) - min(ss) > eps)
            [f, x] = ksdensity(ss, 'Support',[0,1], 'BoundaryCorrection','reflection');
            plot(x, scale * f / max(f), 'LineWidth', 1.5, 'LineStyle',':', 'DisplayName','sim density (scaled)');
        else
            % Fallback: simple histogram-shaped line if data are (near) constant
            edges  = linspace(0,1,21);
            counts = histcounts(ss, edges, 'Normalization','pdf');
            xc     = (edges(1:end-1) + edges(2:end))/2;
            mxc    = max(counts);
            if mxc == 0, mxc = 1; end
            plot(xc, scale * counts / mxc, 'LineWidth', 1.5, 'LineStyle',':', 'DisplayName','sim density (scaled, hist)');
        end
    catch
        % Last-resort fallback: histogram only
        edges  = linspace(0,1,21);
        counts = histcounts(ss, edges, 'Normalization','pdf');
        xc     = (edges(1:end-1) + edges(2:end))/2;
        mxc    = max(counts);
        if mxc == 0, mxc = 1; end
        plot(xc, scale * counts / mxc, 'LineWidth', 1.5, 'LineStyle',':', 'DisplayName','sim density (scaled, hist)');
    end
end
plot([c-w c-w], ylim, 'k--', 'HandleVisibility','off');
plot([c+w c+w], ylim, 'k--', 'HandleVisibility','off');
plot(xlim, [0 0], 'k:', 'HandleVisibility','off');
xlabel('similarity s (|corr|)'); ylabel('\phi(s)'); 
title(sprintf('Penalty function (c=%.2f, w=%.2f, \\beta_w=%.2f, \\beta_h=%.2f)', c,w,beta_well,beta_hi));
legend('Location','best');

% (4) λ_eff over time
subplot(2,2,4); hold on; grid on; box off;
plot(tvec, lam_hist, 'LineWidth', 2);
xlabel('iteration'); ylabel('\lambda_{\it eff}');
title('\lambda_{\it eff} over time');

%% ---------- Helper: ultra-smooth asymmetric penalty ----------
function pen = redundancy_penalty_asym_ultrasmooth(s, c, w, beta_well, beta_hi, sigma_lo, sigma_hi)
    s   = double(s(:));
    Phi = @(z) 0.5*(1 + erf(z./sqrt(2)));
    Wlo = Phi((s - (c - w))./max(sigma_lo,eps)) - Phi((s - (c + w))./max(sigma_lo,eps));
    well = -beta_well .* exp(-((s - c).^2) ./ (2*(w.^2) + eps)) .* Wlo;
    Rhi  =  beta_hi   .* Phi((s - (c + w))./max(sigma_hi,eps));
    pen  = well + Rhi;
end

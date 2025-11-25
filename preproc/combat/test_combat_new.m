function test_combat_new
% TEST_COMBAT_NEW
%   Sanity tests for the new ComBat implementation:
%   - Batch mode: removal of batch effect
%   - Retain/remove covariate effects (label vs nuisance)
%   - No-batch mode with spline modelling
%   - Unseen batch calibration via combat_update_newbatch_auto
%
%   All tests use synthetic data with known structure and produce
%   graphical + numeric output.

rng(1); % reproducibility
VERBOSE = true; % global variable used by combat_new, if declared there

%% -------------------------------------------------------------
%  Global synthetic data settings
% --------------------------------------------------------------
p  = 200;   % #features
nT = 300;   % #train samples
nS = 150;   % #second (test) samples

%% -------------------------------------------------------------
% 1) Batch correction without covariates
% --------------------------------------------------------------
fprintf('\n===== TEST 1: Batch correction (no covariates) =====\n');

nB = 3; % 3 training batches
[dat_train, batch_train] = make_synth_batch_data(p, nT, nB);

% Before ComBat: batch means should differ
mean_pre = group_means(dat_train, batch_train);

opts = struct();
[dat_train_cb, est1] = combat_new(dat_train, batch_train, [], [], opts);
mean_post = group_means(dat_train_cb, batch_train);

% Plot feature-wise means for one feature across batches
feat = 1;
figure('Name','Test 1: Batch means before/after','Color','w');
subplot(1,2,1);
boxplot(dat_train(feat,:)', batch_train');
title(sprintf('Feature %d: pre-ComBat', feat));
xlabel('Batch'); ylabel('Intensity');

subplot(1,2,2);
boxplot(dat_train_cb(feat,:)', batch_train');
title(sprintf('Feature %d: post-ComBat', feat));
xlabel('Batch'); ylabel('Intensity');

fprintf('Mean batch differences (feature-averaged) before vs after:\n');
disp(table((1:nB)', mean_pre, mean_post, ...
    'VariableNames', {'Batch','MeanPre','MeanPost'}));

%% -------------------------------------------------------------
% 2) Retain label effect, remove nuisance covariate effect
% --------------------------------------------------------------
fprintf('\n===== TEST 2: Keep label, remove nuisance covariate =====\n');

% Two covariates:
%   col1 = binary label (effect we want to retain)
%   col2 = continuous nuisance covariate (effect we want to remove)
[dat2, batch2, label2, cov_nuis2] = make_synth_cov_data(p, nT, nB);

mod2 = [label2 cov_nuis2];  % n x 2

% Correlations with label and nuisance before ComBat
[r_lab_pre, r_nuis_pre] = corr_with_cov(dat2, label2, cov_nuis2);

% Set keep/remove on ORIGINAL mod columns:
%   keep_idx   = [1 2]  (we model both covariates)
%   remove_idx = [2]    (we remove only the nuisance effect)
opts2 = struct();
opts2.keep_idx   = 1;
opts2.remove_idx = 2;

[dat2_cb, est2] = combat_new(dat2, batch2, mod2, [], opts2);

% Correlations after ComBat
[r_lab_post, r_nuis_post] = corr_with_cov(dat2_cb, label2, cov_nuis2);

fprintf('Median |corr(feature, label)|   pre: %.3f   post: %.3f\n', ...
    median(abs(r_lab_pre)),  median(abs(r_lab_post)));
fprintf('Median |corr(feature, nuisance)| pre: %.3f   post: %.3f\n', ...
    median(abs(r_nuis_pre)), median(abs(r_nuis_post)));

figure('Name','Test 2: Correlations with covariates','Color','w');
subplot(1,2,1);
scatter(abs(r_lab_pre), abs(r_nuis_pre), '.'); axis square;
xlabel('|corr(label)| pre'); ylabel('|corr(nuisance)| pre');
title('Pre-ComBat');

subplot(1,2,2);
scatter(abs(r_lab_post), abs(r_nuis_post), '.'); axis square;
xlabel('|corr(label)| post'); ylabel('|corr(nuisance)| post');
title('Post-ComBat (keep label, remove nuisance)');
grid on;

%% -------------------------------------------------------------
% 3) No-batch mode with spline modelling
% --------------------------------------------------------------
fprintf('\n===== TEST 3: No-batch mode + spline =====\n');

% Nonlinear dependence on "age" (covariate) for a subset of features
[dat_nb, age_nb, label_nb] = make_synth_nobatch_spline(p, nT);

mod_nb = [label_nb age_nb]; % col1=label, col2=age

% We want to REMOVE the nonlinear age effect while retaining label
opts3 = struct();
% define spline: say 5 df on column 2 (age)
df_map = containers.Map('KeyType','double','ValueType','double');
df_map(2) = 5;              % spline on age only
opts3.spline.df_map = df_map;
opts3.keep_idx      = 1;  % model both label & age
opts3.remove_idx    = 2;    % remove age contribution

% No-batch mode: set batch vector with single level
batch_nb = ones(nT,1);

[dat_nb_cb, est3] = combat_new(dat_nb, batch_nb, mod_nb, [], opts3);

% Check nonlinearity wrt age in one illustrative feature
feat = 1;
figure('Name','Test 3: Nonlinear age effect (spline, no-batch)','Color','w');
subplot(1,2,1);
scatter(age_nb, dat_nb(feat,:)', '.'); hold on;
title(sprintf('Feature %d: pre-ComBat', feat));
xlabel('Age'); ylabel('Intensity');

subplot(1,2,2);
scatter(age_nb, dat_nb_cb(feat,:)', '.'); hold on;
title(sprintf('Feature %d: post-ComBat (age removed)', feat));
xlabel('Age'); ylabel('Intensity');

% Quick numeric check: R^2 of nonlinear fit before vs after
r2_pre  = nonlinear_r2(dat_nb(feat,:)', age_nb);
r2_post = nonlinear_r2(dat_nb_cb(feat,:)', age_nb);
fprintf('Feature %d: R^2(age → feature) pre: %.3f  post: %.3f (expect drop)\n', ...
    feat, r2_pre, r2_post);

%% -------------------------------------------------------------
% 4) New unseen batch calibration (compare EB vs no_shrink vs strong_shrink)
% --------------------------------------------------------------
fprintf('\n===== TEST 4: New unseen batch calibration (mode comparison) =====\n');

% One synthetic dataset with 4 batches
nTotal = nT + nS;
[dat_all4, batch_all4] = make_synth_batch_data(p, nTotal, 4);  % batches 1..4

% Training = batches 1..3, unseen = batch 4
train_mask = batch_all4 ~= 4;
test_mask  = ~train_mask;

dat_tr   = dat_all4(:, train_mask);
batch_tr = batch_all4(train_mask);
dat_ts   = dat_all4(:, test_mask);
batch_ts = batch_all4(test_mask);     % all 4's

% Train ComBat on training batches
[dat_tr_cb_trainOnly, est4_base] = combat_new(dat_tr, batch_tr, [], [], struct());

% --- helper: run one mode ---
modes = {'eb','no_shrink','strong_shrink'};
results = struct();
feat = 1;

for k = 1:numel(modes)
    mode = modes{k};
    fprintf('\n--- Mode: %s ---\n', mode);

    opts_calib = struct();
    opts_calib.mode     = mode;
    opts_calib.selector = struct('per_batch_frac', 1, 'min_per_batch', 10);
    if strcmp(mode,'strong_shrink')
        opts_calib.strong_shrink_alpha = 0.7;  % fairly strong extra shrink
    end

    est4 = est4_base; % work on a copy
    est4 = combat_update_newbatch_auto(dat_ts, batch_ts, [], est4, opts_calib);

    % Apply updated estimators to both train and unseen test
    dat_tr_cb2 = combat_new(dat_tr, batch_tr, [], est4, struct());
    dat_ts_cb  = combat_new(dat_ts, batch_ts, [], est4, struct());

    dat_all4_cb = zeros(size(dat_all4));
    dat_all4_cb(:, train_mask) = dat_tr_cb2;
    dat_all4_cb(:, test_mask)  = dat_ts_cb;

    % store for stats + plotting
    results.(mode).dat_all_cb = dat_all4_cb;

    % Batch-wise means
    mean_batch_pre4  = group_means(dat_all4,   batch_all4);
    mean_batch_post4 = group_means(dat_all4_cb, batch_all4);

    fprintf('Mean batch differences (feature-averaged) pre vs post (mode=%s):\n', mode);
    disp(table(unique(batch_all4(:)), mean_batch_pre4, mean_batch_post4, ...
        'VariableNames', {'Batch','MeanPre','MeanPost'}));
end

% --- Plot comparison for a single feature across modes ---
figure('Name','Test 4: New batch calibration by mode','Color','w');

subplot(1,4,1);
boxplot(dat_all4(feat,:)', batch_all4');
title(sprintf('Feat %d: pre', feat));
xlabel('Batch'); ylabel('Intensity');

for k = 1:numel(modes)
    mode = modes{k};
    dat_all4_cb = results.(mode).dat_all_cb;
    subplot(1,4,1+k);
    boxplot(dat_all4_cb(feat,:)', batch_all4');
    title(sprintf('post (%s)', mode));
    xlabel('Batch'); ylabel('Intensity');
end

%% -------------------------------------------------------------
% 5) Complex no-batch scenario: label + 2 covs, one spline-removed
% --------------------------------------------------------------
fprintf('\n===== TEST 5: No-batch, label + 2 covariates, spline removal =====\n');

% Synthetic data:
%  - label (binary): effect to RETAIN
%  - cov_lin (continuous): linear effect to RETAIN
%  - age (continuous): nonlinear effect (sin), to REMOVE via spline
[dat5, label5, cov_lin5, age5] = make_synth_two_cov_spline(p, nT);

% No batch: all ones
batch5 = ones(nT,1);

% Build mod: [label, cov_lin, age]
mod5 = [label5, cov_lin5, age5];

% Correlations BEFORE
[r_lab_pre5, r_lin_pre5, r_age_pre5] = corr_three_covs(dat5, label5, cov_lin5, age5);

% Set up spline + keep/remove:
%   col1 = label    (keep)
%   col2 = cov_lin  (keep)
%   col3 = age      (remove, with spline)
opts5 = struct();
df_map = containers.Map('KeyType','double','ValueType','double');
df_map(3) = 5;                       % spline-expand age (column 3)
opts5.spline.df_map = df_map;

opts5.keep_idx   = [1 2];            % label + linear cov
opts5.remove_idx = 3;                % age only

[dat5_cb, est5] = combat_new(dat5, batch5, mod5, [], opts5);

% Correlations AFTER
[r_lab_post5, r_lin_post5, r_age_post5] = corr_three_covs(dat5_cb, label5, cov_lin5, age5);

fprintf('Median |corr(feature, label)|     pre: %.3f   post: %.3f\n', ...
    median(abs(r_lab_pre5)),  median(abs(r_lab_post5)));
fprintf('Median |corr(feature, cov_lin)|   pre: %.3f   post: %.3f\n', ...
    median(abs(r_lin_pre5)),  median(abs(r_lin_post5)));
fprintf('Median |corr(feature, age)|       pre: %.3f   post: %.3f\n', ...
    median(abs(r_age_pre5)),  median(abs(r_age_post5)));

% Pick one feature that is strongly age-driven
feat5 = 1;

figure('Name','Test 5: label + 2 covs (spline removal of age)','Color','w');
subplot(2,2,1);
scatter(label5, dat5(feat5,:)', '.');
title(sprintf('Feat %d vs label (pre)', feat5));
xlabel('Label'); ylabel('Intensity');

subplot(2,2,2);
scatter(label5, dat5_cb(feat5,:)', '.');
title(sprintf('Feat %d vs label (post)', feat5));
xlabel('Label'); ylabel('Intensity');

subplot(2,2,3);
scatter(age5, dat5(feat5,:)', '.');
title(sprintf('Feat %d vs age (pre)', feat5));
xlabel('Age'); ylabel('Intensity');

subplot(2,2,4);
scatter(age5, dat5_cb(feat5,:)', '.');
title(sprintf('Feat %d vs age (post, age removed)', feat5));
xlabel('Age'); ylabel('Intensity');

% Quick nonlinear R^2 wrt age before/after for this feature
r2_pre5  = nonlinear_r2(dat5(feat5,:)',  age5);
r2_post5 = nonlinear_r2(dat5_cb(feat5,:)', age5);
fprintf('Feat %d: R^2(age → feature) pre: %.3f  post: %.3f (expect strong drop)\n', ...
    feat5, r2_pre5, r2_post5);

fprintf('\nAll tests finished.\n');

end

%% ======================================================================
%  Helper functions
% ======================================================================

function [X, batch] = make_synth_batch_data(p, n, nBatch)
% Synthetic data with additive batch offsets.
% X: p x n, batch: n x 1
batch = randi(nBatch, n, 1);
grand_mean = randn(p,1)*0.1;
batch_effects = linspace(-1, 1, nBatch);          % 1 x nBatch
noise = randn(p, n) * 0.5;
X = grand_mean + noise;
for b = 1:nBatch
    X(:, batch==b) = X(:, batch==b) + batch_effects(b);
end
end

function m = group_means(X, batch)
% Feature-averaged mean per batch.
bLevels = unique(batch(:))';
m = zeros(numel(bLevels), 1);
for i = 1:numel(bLevels)
    m(i) = mean(mean(X(:, batch==bLevels(i)),1),2);
end
end

function [X, batch, label, cov_nuis] = make_synth_cov_data(p, n, nBatch)
% Data with batch + label + nuisance covariate effects.
batch = randi(nBatch, n, 1);
label = double(rand(n,1) > 0.5);       % 0/1
cov_nuis = randn(n,1);                 % continuous

grand_mean = randn(p,1)*0.1;
beta_label = randn(p,1)*0.8;           % strong label effect
beta_nuis  = randn(p,1)*0.6;           % nuisance effect
batch_effects = linspace(-1, 1, nBatch);

noise = randn(p, n)*0.5;
X = grand_mean + noise;
for i = 1:n
    X(:,i) = X(:,i) + beta_label*label(i) + beta_nuis*cov_nuis(i) + batch_effects(batch(i));
end

end

function [r_lab, r_nuis] = corr_with_cov(X, label, cov_nuis)
% Per-feature correlation with label and nuisance covariate.
p = size(X,1);
r_lab  = zeros(p,1);
r_nuis = zeros(p,1);
for j = 1:p
    x = X(j,:)';
    r_lab(j)  = corr(x, label);
    r_nuis(j) = corr(x, cov_nuis);
end
end

function [X, age, label] = make_synth_nobatch_spline(p, n)
% Nonlinear dependence on age for some features, plus label effect.
age   = 20 + 40*rand(n,1);          % 20-60
label = double(rand(n,1) > 0.5);
grand_mean = randn(p,1)*0.1;
beta_label = randn(p,1)*0.7;

% Nonlinear age effect (e.g. sin) on first k features
k_nl = round(p*0.3);
beta_age = randn(k_nl,1)*0.5;

noise = randn(p,n)*0.3;
X = grand_mean + noise;
for i = 1:n
    % Label effect on all features
    X(:,i) = X(:,i) + beta_label*label(i);
    % Nonlinear age effect on subset
    X(1:k_nl,i) = X(1:k_nl,i) + beta_age * sin(age(i)/10);
end
end

function r2 = nonlinear_r2(y, x)
% Quick R^2 from a 3rd-degree polynomial as a proxy for nonlinear fit.
X = [ones(size(x)) x x.^2 x.^3];
b = X\y;
yhat = X*b;
ss_tot = sum((y - mean(y)).^2);
ss_res = sum((y - yhat).^2);
r2 = 1 - ss_res/ss_tot;
end

function [X, label, cov_lin, age] = make_synth_two_cov_spline(p, n)
% Synthetic data:
%   label   : binary effect (retain)
%   cov_lin : linear covariate effect (retain)
%   age     : nonlinear covariate (sine), to be removed via spline

label   = double(rand(n,1) > 0.5);         % 0/1
cov_lin = randn(n,1);                      % linear covariate
age     = 20 + 40*rand(n,1);               % 20-60

grand_mean = randn(p,1)*0.1;
beta_label = randn(p,1)*0.7;               % label effect on all features
beta_lin   = randn(p,1)*0.6;               % linear cov effect on all features

% Make age effect CLEAR & strong for a small subset of features
k_age  = max(5, round(p*0.1));             % first k_age features age-driven
beta_age = randn(k_age,1)*1.5;             % much stronger age effect

noise = randn(p,n)*0.3;
X = grand_mean + noise;
phi_age = sin(age/10);                     % nonlinear basis actually used

for i = 1:n
    X(:,i) = X(:,i) + beta_label*label(i) + beta_lin*cov_lin(i);
    X(1:k_age,i) = X(1:k_age,i) + beta_age * phi_age(i);
end
end

function [r_lab, r_lin, r_age] = corr_three_covs(X, label, cov_lin, age)
p = size(X,1);
r_lab = zeros(p,1);
r_lin = zeros(p,1);
r_age = zeros(p,1);
for j = 1:p
    x = X(j,:)';
    r_lab(j) = corr(x, label);
    r_lin(j) = corr(x, cov_lin);
    r_age(j) = corr(x, age);
end
end

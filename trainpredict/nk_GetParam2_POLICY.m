% ==========================================================================
% FORMAT [param, model] = nk_GetParam2_POLICY(Y, label, ModelOnly, Param)
% ==========================================================================
% Doubly-robust (AIPW/DR) policy learner for treatment selection in
% retrospective observational data (multi-class treatments).
%
% PURPOSE
%   Learns a treatment policy pi(X) that selects the treatment maximizing
%   predicted remission probability, and evaluates it via a doubly-robust
%   policy value estimator on the provided dataset (typically CV1 test fold).
%
% IMPORTANT NM NOTE (conceptual integration)
%   - NM expects a single scalar criterion param.val per call.
%   - Here, param.val is the estimated policy value V_hat(pi) (scalar).
%   - Do NOT interpret AUC/BAC of "max_a p_a(X)" vs Y as policy validation.
%   - Proper usage is nested CV; CV1 optimizes V_hat, CV2 reports final V_hat.
%
% INPUTS
%   Y         : [N x p] baseline features X (pre-treatment)
%   label     : treatment/outcome container, recommended formats:
%               (A) struct with fields:
%                   label.Y : [N x 1] remission label (binary)
%                   label.A : [N x 1] treatment category (1..K or 0..K-1)
%               (B) numeric matrix [N x 2] with:
%                   label(:,1)=Ylabel, label(:,2)=A
%   ModelOnly : if 1, return fitted model only (no param struct)
%   Param     : hyperparameter cell array (see below)
%
% GLOBALS
%   MODEFL    : only 'classification' is meaningful here (binary remission)
%   EVALFUNC  : optional; ignored by default because policy value is computed
%               internally. (You may later set EVALFUNC = @nm_policyvalue_dr)
%
% Param mapping (recommended defaults in brackets):
%   Param{1}  = propensity learner type:
%              'MultinomialLogReg' (sklearn LogisticRegression multi_class)
%   Param{2}  = outcome learner type (S-learner):
%              'LogReg' | 'LinearSVC_Platt' (calibrated)
%   Param{3}  = fit_intercept (0/1) [1]
%   Param{4}  = propensity C (double) [1.0]
%   Param{5}  = outcome C (double) [1.0]
%   Param{6}  = max_iter (int) [2000]
%   Param{7}  = propensity solver (char) ['lbfgs']
%   Param{8}  = tau_overlap (double) [0.05]  % minimum propensity for support
%   Param{9}  = eps_clip (double) [1e-6]     % clip propensities to avoid /0
%   Param{10} = allow_out_of_support (0/1) [0]
%              if 0: do not recommend treatments with e_hat < tau; fallback
%              if 1: ignore tau in argmax
%
% OUTPUTS
%   model : struct containing python objects and metadata:
%           .prop_model  (python)  P(A|X)
%           .out_model   (python)  S-learner P(Y|X,A)
%           .K           (int)     number of treatment categories
%           .A_levels    (vector)  sorted unique treatment labels
%   param : struct (if ~ModelOnly):
%           .val         (scalar)  DR policy value estimate V_hat(pi)
%           .target      (N x 1)   mu_pi(X)  predicted remission under policy
%           .dec_values  (N x 1)   same as target (for NM compatibility)
%           .pi          (N x 1)   recommended treatment index in A_levels
%           .mu_all      (N x K)   mu_a(X) for all a (potential outcomes)
%           .e_all       (N x K)   e_hat_a(X) propensities
%           .in_support  (N x K)   e_hat_a(X) >= tau
% ==========================================================================
% (c) Draft module for NeuroMiner-style integration, 01/2026

function [param, model] = nk_GetParam2_POLICY(Y, label, ModelOnly, Param)
global MODEFL EVALFUNC %#ok<NUSED>
param = [];

% ---------------------------
% 0) Sanitize and unpack data
% ---------------------------
X = double(Y);

% Extract remission outcome y and treatment A
if isstruct(label)
    y = double(label.Y(:));
    A = double(label.A(:));
elseif isnumeric(label) && size(label,2) >= 2
    y = double(label(:,1));
    A = double(label(:,2));
else
    error('POLICYLEARNER: label must be struct(label.Y,label.A) or [N x 2] numeric matrix.');
end

if ~strcmp(MODEFL,'classification')
    error('POLICYLEARNER is intended for MODEFL=''classification'' with binary remission outcome.');
end

% Map outcome to {0,1}
uy = unique(y(~isnan(y)));
if numel(uy) ~= 2
    error('POLICYLEARNER expects binary remission labels.');
end
if all(ismember(uy,[-1 1]))
    y01 = y == max(uy);
elseif all(ismember(uy,[0 1]))
    y01 = y;
else
    y01 = y == max(uy);
end
y01 = double(y01(:));

% Treatments: allow arbitrary numeric labels; derive levels
A = A(:);
A_levels = unique(A(~isnan(A)));
A_levels = sort(A_levels);
K = numel(A_levels);
if K < 2
    error('POLICYLEARNER expects >=2 treatment categories.');
end

% Remap A to indices 1..K for internal use
A_idx = zeros(size(A));
for k = 1:K
    A_idx(A == A_levels(k)) = k;
end

N = size(X,1);
%P = size(X,2);

% ---------------------------
% 1) Hyperparameters
% ---------------------------
prop_type   = Param{1};                 % 'MultinomialLogReg'
out_type    = Param{2};                 % 'LogReg' | 'LinearSVC_Platt'
fit_int     = logical(Param{3});
C_prop      = double(Param{4});
C_out       = double(Param{5});
max_iter    = int64(Param{6});
solver_prop = char(Param{7});
tau         = double(Param{8});
eps_clip    = double(Param{9});
allow_oos   = logical(Param{10});

% ---------------------------
% 2) Build & fit propensity model: e_hat = P(A|X)
% ---------------------------
switch prop_type
    case 'MultinomialLogReg'
        % sklearn LogisticRegression for multinomial propensity
        % Note: multi_class='multinomial' + lbfgs is standard.
        prop_model = py.sklearn.linear_model.LogisticRegression( ...
            C=C_prop, max_iter=max_iter, solver=solver_prop, ...
            fit_intercept=fit_int, multi_class='multinomial');
    otherwise
        error('Unknown propensity model type: %s', prop_type);
end

% Fit propensity on X -> A_idx
prop_model = prop_model.fit(double(X), int32(A_idx));

% ---------------------------
% 3) Build & fit outcome model (S-learner): mu(x,a) = P(Y=1|X,A=a)
%     Implementation: augment X with one-hot(A) and fit a probabilistic model
% ---------------------------
X_aug = [X, onehot_int(A_idx, K)];  % [N x (P+K)]

switch out_type
    case 'LogReg'
        out_model = py.sklearn.linear_model.LogisticRegression( ...
            C=C_out, max_iter=max_iter, solver='lbfgs', ...
            fit_intercept=fit_int);
        out_model = out_model.fit(double(X_aug), int32(y01));

    case 'LinearSVC_Platt'
        % Linear SVC + Platt scaling (CalibratedClassifierCV)
        base = py.sklearn.svm.LinearSVC(C=C_out);
        out_model = py.sklearn.calibration.CalibratedClassifierCV( ...
            base, method='sigmoid', cv=int64(3));
        out_model = out_model.fit(double(X_aug), int32(y01));

    otherwise
        error('Unknown outcome model type: %s', out_type);
end

% ---------------------------
% 4) Package model for downstream predict()
% ---------------------------
model = struct();
model.prop_model = prop_model;
model.out_model  = out_model;
model.K          = K;
model.A_levels   = A_levels;
model.tau        = tau;
model.eps_clip   = eps_clip;
model.allow_oos  = allow_oos;

% If only model is requested, stop here
if ModelOnly
    return;
end

% ---------------------------
% 5) Predict propensities e_hat_a(X) for all a
% ---------------------------
e_all = double(prop_model.predict_proba(double(X))); % [N x K] columns aligned with class order

% sklearn stores class order; ensure it matches 1..K
% In multinomial LR, classes_ should contain {1..K}. If not, remap columns.
classes_prop = double(py.array.array('d', prop_model.classes_));
[~, perm] = ismember(1:K, classes_prop);
if any(perm==0)
    error('Propensity model class mapping failed; classes_ mismatch.');
end
e_all = e_all(:, perm);

% Clip
e_all = max(min(e_all, 1.0), eps_clip);

% Support mask
in_support = e_all >= tau;

% ---------------------------
% 6) Predict potential outcomes mu_a(X) for all a by plugging each a
% ---------------------------
mu_all = zeros(N, K);
for a = 1:K
    X_aug_a = [X, onehot_int(a*ones(N,1), K)];
    % predict_proba: [:,1]=P(Y=0), [:,2]=P(Y=1)
    p = double(out_model.predict_proba(double(X_aug_a)));
    mu_all(:,a) = p(:,2);
end

% ---------------------------
% 7) Define policy pi(X) = argmax_a mu_a(X) subject to overlap gating
% ---------------------------
pi_idx = zeros(N,1);
for i = 1:N
    if allow_oos
        [~,pi_idx(i)] = max(mu_all(i,:));
    else
        allowed = find(in_support(i,:));
        if isempty(allowed)
            % Fallback: choose treatment with highest propensity (most supported)
            [~,pi_idx(i)] = max(e_all(i,:));
        else
            [~,j] = max(mu_all(i,allowed));
            pi_idx(i) = allowed(j);
        end
    end
end

% ---------------------------
% 8) Compute DR/AIPW policy value on THIS dataset
%     V_hat(pi) = mean( mu_pi + I(A=pi)/e_pi * (Y - mu_obs) )
% ---------------------------
mu_pi  = mu_all(sub2ind([N,K], (1:N)', pi_idx));
mu_obs = mu_all(sub2ind([N,K], (1:N)', A_idx));

e_pi   = e_all(sub2ind([N,K], (1:N)', pi_idx));
agree  = (A_idx == pi_idx);

Vhat = mean( mu_pi + (agree ./ e_pi) .* (y01 - mu_obs) );

% ---------------------------
% 9) Populate NM-compatible param output
% ---------------------------
param.val        = Vhat;
param.target     = mu_pi(:);             % predicted remission under policy (for reference)
param.dec_values = mu_pi(:);
param.pi         = A_levels(pi_idx);     % map back to original treatment labels
param.mu_all     = mu_all;
param.e_all      = e_all;
param.in_support = in_support;

end

% ==========================================================================
% Helper: one-hot encoder for integer labels in 1..K
% ==========================================================================
function O = onehot_int(idx, K)
idx = int32(idx(:));
N = numel(idx);
O = zeros(N, K);
for i = 1:N
    if idx(i) >= 1 && idx(i) <= K
        O(i, idx(i)) = 1;
    end
end
end

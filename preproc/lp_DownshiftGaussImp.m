function imputed_data = lp_DownshiftGaussImp(data, shift_factor, scale_factor, rngSeed)
% Imputes NaNs using a left-shifted Gaussian per feature (Perseus-like).
% data: (samples x features) double
% shift_factor: mean shift in SD units (default 1.8)
% scale_factor: SD as fraction of observed SD (default 0.3)
% rngSeed: optional, for reproducibility (e.g., 42)
%
% Notes:
% - Operates independently on the provided matrix (no leakage).
% - All-NaN features are left as NaN.
% - If observed SD <= eps or non-finite, falls back to constant fill at mu_shifted.

if nargin < 2 || isempty(shift_factor), shift_factor = 1.8; end
if nargin < 3 || isempty(scale_factor), scale_factor = 0.3; end
if nargin >= 4 && ~isempty(rngSeed)
    rng(rngSeed, 'twister');
end

[~, nFeatures] = size(data);
imputed_data = data;

% enforce sensible bounds
scale_factor = max(scale_factor, 0);

for j = 1:nFeatures
    col = data(:, j);
    missing_idx = isnan(col);
    if ~any(missing_idx)
        continue
    end

    observed = col(~missing_idx);

    % Skip completely NaN features (leave NaN)
    if isempty(observed)
        continue
    end

    mu_obs = mean(observed);
    sd_obs = std(observed);  % sample std (n-1), NaN-safe since observed has no NaNs
    if ~isfinite(sd_obs) || sd_obs <= eps
        % Constant or degenerate: use a constant at shifted mean
        mu_impute = mu_obs - shift_factor * 0;
        imputed_vals = repmat(mu_impute, sum(missing_idx), 1);
        imputed_data(missing_idx, j) = imputed_vals;
        continue
    end

    mu_impute    = mu_obs - shift_factor * sd_obs;
    sigma_impute = sd_obs  * scale_factor;

    if sigma_impute <= eps || ~isfinite(sigma_impute)
        % Practically zero width: constant fill
        imputed_vals = repmat(mu_impute, sum(missing_idx), 1);
    else
        % Gaussian draws without toolbox dependency
        imputed_vals = mu_impute + sigma_impute * randn(sum(missing_idx), 1);
    end

    imputed_data(missing_idx, j) = imputed_vals;
end


function [P_log10, Pfdr_log10, P_empirical, I, I_null] = nk_SignBasedConsistencySignificance_SVR(E, nPerm)

% Inputs:
% - E: [features × folds × components] SVR weight ensemble
% - nPerm: number of sign permutations (e.g., 1000)

% Outputs:
% - P_log10: -log10 of empirical p-values
% - Pfdr_log10: -log10 of FDR-corrected empirical p-values
% - P_empirical: raw empirical p-values
% - I: observed sign-consistency values
% - I_null: null distribution of I under random sign flips

if nargin < 2 || isempty(nPerm)
    nPerm = 1000;
end

% Compute observed sign-consistency
I = nk_SignBasedConsistency(E);
[N, ~, C] = size(E);
I_null = zeros(N, C, nPerm);

fprintf('\nComputing empirical null distribution via random sign flipping (%d permutations)...\n', nPerm);

for p = 1:nPerm
    % Random sign flipping: simulate null hypothesis (no stable directionality)
    random_signs = sign(randn(size(E)));
    E_perm = E .* random_signs;

    I_null(:,:,p) = nk_SignBasedConsistency(E_perm);
end

% Compute empirical one-sided p-values: proportion of null values >= observed
P_empirical = mean(I_null >= I, 3, 'omitnan');

% Avoid zeros (never observed in null)
P_empirical = max(P_empirical, 1/nPerm);

% Apply FDR correction
Pfdr_empirical = zeros(size(P_empirical));
for c = 1:C
    [~, ~, ~, Pfdr_empirical(:,c)] = fdr_bh(P_empirical(:,c), 0.05);
end

% Log-transform for plotting
P_log10 = -log10(P_empirical);
Pfdr_log10 = -log10(Pfdr_empirical);
Pfdr_log10(Pfdr_log10 < 0) = 0;  % clean up numerical negatives

end

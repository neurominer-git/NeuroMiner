function I = nk_SignBasedConsistency(E)
% Compute modified version of sign-based consistency criterion using a binary
% classifier ensemble. See paper by Vanessa Gomez-Verdejo et al.,
% Neuroinformatics, 2019, 17:593-609. We additionally downweight the
% consistency vector I by the number of nonfinite values in the ensemble matrix.
% I = 2 * abs( nanmean(E>0,2) - 0.5) .* (1 - sum(isnan(E),2) / size( E, 2));
% Ensure E is 3-D: [N × P × C]

if ismatrix(E)
    E = reshape(E, size(E,1), size(E,2), 1);
end
[N, P, C] = size(E);

% Fraction of non-NaN per feature/component
Rnan = 1 - squeeze(sum(isnan(E),2)) / P;   % [N × C]

% Positive and negative sign‐counts averaged across folds
Ip = squeeze(nm_nanmean(E>0, 2)) .* Rnan;  % [N × C]
In = squeeze(nm_nanmean(E<0, 2)) .* Rnan;  % [N × C]

% Features entirely NaN get NaN
Ip(Rnan == 0) = NaN;
In(Rnan == 0) = NaN;

% Final consistency
I = abs(Ip - In);  % [N × C]

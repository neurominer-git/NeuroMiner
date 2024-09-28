function I = nk_SignBasedConsistency(E)
% Compute modified version of sign-based consistency criterion using a binary
% classifier ensemble. See paper by Vanessa Gomez-Verdejo et al.,
% Neuroinformatics, 2019, 17:593-609. We additionally downweight the
% consistency vector I by the number of nonfinite values in the ensemble matrix.
% I = 2 * abs( nanmean(E>0,2) - 0.5) .* (1 - sum(isnan(E),2) / size( E, 2));
Rnan = 1-sum(isnan(E),2) / size( E, 2 );
Ip = nm_nanmean(E>0,2).*Rnan;
In = nm_nanmean(E<0,2).*Rnan;
% Addition 11/02/2024: features that consists completely of NaN weights are
% set to NaN.
Ip(Rnan==0) = NaN;
In(Rnan==0) = NaN;
I = abs(Ip-In);
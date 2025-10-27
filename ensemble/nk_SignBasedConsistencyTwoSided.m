function I = nk_SignBasedConsistencyTwoSided(E)
% Compute modified version of sign-based consistency criterion using a binary
% classifier ensemble. See paper by Vanessa Gomez-Verdejo et al.,
% Neuroinformatics, 2019, 17:593-609. We additionally downweight the
% consistency vector I by the number of nonfinite values in the ensemble matrix.
% This version measures the directionality of effects
Rnan = 1-sum(isnan(E),2) / size( E, 2 );
I = nm_nanmean(E,2).*Rnan;
% Features that consists completely of NaN weights are
% set to NaN.
I(Rnan==0) = NaN;

function [P, Pfdr, Z, I] = nk_SignBasedConsistencySignificanceTwoSided(E)

% Computed sign-based consistency [0= no consistency, 1=absolute
% consistency]
I = nk_SignBasedConsistencyTwoSided(E);
% Compute Z score
Z = I ./ std(I,"omitnan");
% Compute P value of Z score (two-sided test of Z to measure deviation from zero)
P = 2 * (1- nm_normcdf(abs(Z),0,1));
% Correct for multiple comparisons using FDR
[~,~,~,Pfdr] = fdr_bh(P,0.05);
%log-transform P values
P = -log10(P); Pfdr = -log10(Pfdr); 
Pfdr(Pfdr<0)=0;
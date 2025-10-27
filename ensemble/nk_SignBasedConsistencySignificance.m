function [P, Pfdr, Z, I] = nk_SignBasedConsistencySignificance(E, I)

% Computed sign-based consistency [0= no consistency, 1=absolute
% consistency]
if ~exist('I','var') || isempty(I)
    I = nk_SignBasedConsistency(E);
end
% Compute Z score
Z = I ./ std(I,"omitnan");
% Compute P value of Z score (right-tailed one-sided test of Z)
P = nm_normcdf(-Z,0,1);
% Correct for multiple comparisons using FDR
[~,~,~,Pfdr] = fdr_bh(P,0.05);
%log-transform P values
P = -log10(P); Pfdr = -log10(Pfdr); 
Pfdr(Pfdr<0)=0;
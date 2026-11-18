function [STATS, DIFF] = wilcoxon(G1, G2, alpha, xnames, ynames, filename)
% Purpose: Run the established paired Wilcoxon comparator for one reference vector versus one or more matched vectors.
% Syntax: [STATS,DIFF] = wilcoxon(G1,G2,alpha,xnames,ynames,filename)
% Inputs: Matched numeric vectors/rows, alpha, labels and optional legacy output filename.
% Outputs: Per-comparison statistics and matched differences.
% Authority and flow: Preserves the legacy Wilcoxon implementation; Stage-2 changes only the normal-approximation tail probability to the two-sided probability already used by the exact branch.
% Scientific/state contract: This is the inferential authority used by Cross-analysis paired/reference Wilcoxon dispatch.
% Invariants: Zero-difference handling, ranks, Hodges-Lehmann estimates, confidence intervals and exact branch remain unchanged.
% Materialization and performance: O(N*comparisons) plus exact 2^N enumeration only for the existing N<=15 branch.
% Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact statistical vectors only.
% Interactive/retained use: Intended for explicit statistical comparison/report actions, not high-frequency retained interaction.
% Failure semantics: All-zero matched differences fail as in legacy code; other validation/failure behavior is unchanged.
% Side effects: No NM mutation; optional legacy file writing occurs only when the existing filename argument is explicitly supplied.
% Consumers and dependencies: NMResultsViewerCrossAnalysisTools and legacy comparator/export callers; nm_tiedrank, ff2n, fdr_bh when legacy file export is requested.
% Based on the WILCOXON code of Giuseppe Cardillo
nG = size(G2,1);
DIFF = zeros(size(G2));
ynames2 = ynames(2:end);
if nG>1, 
    ynames{1} = [ynames{1} ' [ref]']; 
end
for i=1:nG
    [STATS(i), DIFF(i,:)] = wilcoxon_sub(G1,G2(i,:),alpha, ynames2{i});
end

if exist('filename','var') && ~isempty(filename)
   sh = {'pp','diff','stats'};
   STATALL.tbl_perf = array2table([G1' G2'],'VariableNames',ynames', 'RowNames', xnames);
   STATALL.tbl_diff = array2table(DIFF','VariableNames',ynames2', 'RowNames', xnames);
   STATALL.tbl_stats = struct2table(STATS,'AsArray',true);
   if nG>1
       pvals = STATALL.tbl_stats{:,end};
       [~,~,~,pvals_fdr] = fdr_bh(pvals,0.05);
       STATALL.tbl_stats = [ STATALL.tbl_stats table(pvals_fdr,'VariableNames',{'p[FDR]'})];
   end
   tblnames = {'tbl_perf', 'tbl_diff', 'tbl_stats'};
   display_writetable(STATALL, filename, tblnames, sh);
end

function [STATS, DIFF] = wilcoxon_sub(x1,x2,alpha, name_comparison)
% Purpose: Execute one paired signed-rank comparison used by wilcoxon.
% Syntax: [STATS,DIFF] = wilcoxon_sub(x1,x2,alpha,name_comparison)
% Inputs: Two matched vectors, alpha and comparison label.
% Outputs: One statistic struct and x2-x1 matched differences.
% Authority and flow: Implements the legacy exact/asymptotic signed-rank branches; only asymptotic p is corrected to two-sided.
% Scientific/state contract: Exact and normal-approximation branches must report consistent two-sided probabilities.
% Invariants: All legacy ranking/CI/estimator/statistic calculations are preserved.
% Materialization and performance: O(N^2) Walsh-average work plus legacy exact enumeration for N<=15.
% Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact statistical vectors only.
% Interactive/retained use: Intended for explicit statistical comparison/report actions, not high-frequency retained interaction.
% Failure semantics: All-zero differences fail explicitly; legacy failure behavior otherwise preserved.
% Side effects: No NM mutation; optional legacy file writing occurs only when the existing filename argument is explicitly supplied.
% Consumers and dependencies: wilcoxon wrapper only; nm_tiedrank, ff2n and distribution functions.

DIFF = x2-x1;
dff=sort(DIFF); %difference between x1 and x2
dff(dff==0)=[]; %eliminate null variations
n=length(dff); %number of ranks
if length(x1)~=n %tell me if there are null variations
    fprintf('There are %d null variations that will be deleted\n',length(x1)-n)
end
if isempty(dff) %if all variations are null variations exit function
    error('There are not variations. Wilcoxon test can''t be performed')
end

%Ranks of absolute value of samples differences with sign
[r,t]   = nm_tiedrank(abs(dff)); %ranks and ties
W       = sum(r.*sign(dff)); %Wilcoxon statics (sum of ranks with sign)
pem     = median(dff); %point estimation of median of differences
m       = ceil(n/2); %location of the median

if mod(n,2) == 0 %If the length of the series is even
    tmp = [dff(1:m) pem dff(m:end)]; %add the median in the middle
    dff = tmp; clear tmp 
    m   = m+1;
end

%find how many differences far from the median we have to choose
C       = cumsum(binopdf(0:1:n,n,0.5));
T       = find( C <= alpha/2,1,'last')-1;
cintpem = dff([m-T m+T]); %construct the interval
clear C T m
[I,J]   = ndgrid(dff,dff); d=triu(I+J)./2; %Walsh averages triangular matrix
ld      = sort(d(d~=0)); %linearization of Walsh averages matrix
clear I J 
HLe     = median(ld); %Hodges-Lehmann estimator
if n>15
    A=n*(n+1)/4; B=realsqrt(n*(n+1)*(2*n+1)/24); 
    Za=-realsqrt(2).*erfcinv(2.*(1-alpha/2));
    T=fix(A-Za.*B);
else
    TC=[0 0 0 0 0 0 2 3 5 8 10 13 17 21 25];
    T=TC(n); clear TC
end
cintHLe = ld([T+1 end-T])';
clear dff d ld T%clear unnecessary variable

%If the number of elements N<15 calculate the exact distribution of the
%signed ranks (the number of combinations is 2^N); else use the normal
%distribution approximation.
STATS.comparison = name_comparison;
if n<=15
    ap=ff2n(n); %the all possibilities based on two-level full-factorial design.
    ap(ap~=1)=-1; %change 0 with -1
    k=1:1:n; 
    J=ap*k'; %all possible sums of ranks for k elements
    %to compute the p-value see how many values are more extreme of the observed
    %W and then divide for the total number of combinations
    p=length(J(abs(J)>=abs(W)))/length(J); %p-value
    STATS.method = 'Exact distribution';
    STATS.W      = W;
    STATS.mean   = [];
    STATS.std    = [];
    STATS.z      = [];
    STATS.p      = p;
else
    sW           = sqrt((2*n^3+3*n^2+n-t)/6); %standard deviation
    zW           = (abs(W)-0.5)/sW; %z-value with correction for continuity
    p            = min(1,2*(1-normcdf(zW))); % two-sided p-value
    STATS.method = 'Normal approximation';
    STATS.W      = W;
    STATS.mean   = 0;
    STATS.std    = sW;
    STATS.z      = zW;
    STATS.p      = p;
end


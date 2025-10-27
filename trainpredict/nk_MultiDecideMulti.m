function [hE, hEPerf, hSim] = nk_MultiDecideMulti(P, L, C, G)

n = size(P,1);
MajVote = zeros(n,G);
for curclass = 1:G
    MajVote(:,curclass) = sum(P(:,C==curclass),2);
end
[~,hE] = max(MajVote,[],2);
hEPerf = sum(hE == L)*100/n;
hSim = MajVote ./ sum(MajVote,2);

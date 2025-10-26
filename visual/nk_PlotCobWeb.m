function [h, n_mat, ca, o] = nk_PlotCobWeb(mat, groupnames, ha)

cla(ha); ha.Visible='on';
ha.Position= [.12 .5 .7 .425];
[M,N] = size(mat);
idx = eye(M,N);
n_mat =  (mat ./ sum(mat,2))*100;
mcl = n_mat(~idx);
Ax = cell(M,N); Ux = cell(M,N);
for i=1:M
    for j=1:N
        Ax{i,j} = sprintf('%s\n\\rightarrow%s', groupnames{i},groupnames{j});
        Ux{i,j} = '';
    end
end
Ax = [Ax(~idx) Ux(~idx)];
% Plot cobweb graph
[h, ca, o] = spider([ones(numel(mcl),1)*100/N mcl ],'Misclassification web',[ zeros(numel(mcl),1) 50*ones(numel(mcl),1) ],Ax,[], ha, [], 8, 8, 1, 1);
o(1).LineStyle=':'; o(2).LineWidth=2.5;
ratio = nk_MultiClassRatio2Random(mat);
ca.Title.String=sprintf('[ TMR: %1.1f%% ]', ratio);
ca.Title.Position = [0 1.35];
ca.Title.Visible='on';

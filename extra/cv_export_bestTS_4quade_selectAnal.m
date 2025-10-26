%% extract bestTS for each outer CV fold (n_perm * n_folds) 

% load NM structure, 
% the analyses for which you want to extract
% performance need to be trained

%% CHANGE: 
% for which analyses do you want to extract outer CV performance? 
analind = [1,2]; % enter index/indices as in NM structure

%%
% assuming all use cv of analysis 1
[ix, jx] = size(NM.analysis{1}.params.cv.TrainInd);

nA = size(analind, 2);

G = zeros(ix*jx, nA);
Gnames = {};
Analnames = {};
for i = 1:nA
    ll=1;
    idx = analind(i);
    AnalG = NM.analysis{1,idx}.GDdims{1,1};
    Analnames{i} = NM.analysis{1,idx}.id;
    for f=1:ix
        for d=1:jx
            G(ll,i) = AnalG.bestTS{1,1}(f,d);
            Gnames{ll} = sprintf('CV2: R%g_F%g', f,d);
            ll=ll+1;
        end
    end
end

G_table = array2table(G); 
G_table.Properties.VariableNames = Analnames; 
G_table.FoldPerm = Gnames';
G_table.vxlPCA = G; 





function Y_all = JuSpace_no_GUI_2D_faster(Yimg, IN, INDPruneVec, INDExtFeat)

if ~isfield(IN,'ROIflag')
    ROIflag = false;
else
    ROIflag = IN.ROIflag;
end

if IN.cortype == 1
    cortype = 'Spearman';
elseif IN.cortype == 2
    cortype = 'Pearson';
end

if ~isempty(INDPruneVec)

    numRows = size(Yimg, 1);
    
    Yimg_new = zeros(numRows, size(Yimg, 2) + numel(INDPruneVec));
    
    colCounterA = 1;
    
    for i = 1:size(Yimg_new, 2)
        if any(INDPruneVec == i)
            Yimg_new(:, i) = zeros(numRows, 1);
        else
            Yimg_new(:, i) = Yimg(:, colCounterA);
            colCounterA = colCounterA + 1;
        end
    end
    Yimg = Yimg_new;
end

if ~isempty(INDExtFeat)
    IN.YAtlas = IN.YAtlas(:,INDExtFeat==1);
    IN.YNT = IN.YNT(:,INDExtFeat==1);
    IN.YTPM = IN.YTPM(:,INDExtFeat==1);
end

% remove nan rows if necessary
nan_rows = all(isnan(Yimg), 2);

if sum(nan_rows) > 0
    Yimg_nonan = Yimg(~nan_rows, :);
else
    Yimg_nonan = Yimg;
end

% compute ROI means
if ~ROIflag
    YimgROIs = cell(size(IN.YAtlas,1),1);
    
    for k = 1:size(IN.YAtlas,1)
        a = unique(IN.YAtlas(k,:));
        a = a(a~=0); 
        AtlasROIs = a(~isnan(a));
    
        YimgROIs{k,1} = zeros(size(Yimg_nonan,1), numel(AtlasROIs));
    
        for i = 1:numel(AtlasROIs)
            indVec = round(IN.YAtlas(k,:)) == round(AtlasROIs(i));

            if sum(indVec) >=20
                YimgROIs{k,1}(:,i) = mean(removenan_my(Yimg_nonan(:,indVec)'),1);
                if ~isempty(IN.YTPM)
                    TPMROIs{k,1}(:,i) = mean(removenan_my(IN.YTPM(:,indVec)'),1);
                end
                NTROIs{k,1}(:,i) = mean(removenan_my(IN.YNT(:,indVec)'),1);
            else
                YimgROIs{k,1}(:,i) = NaN(size(Yimg_nonan,1),1)';
                if ~isempty(IN.YTPM)
                    TPMROIs{k,1}(:,i) = NaN;
                end
                NTROIs{k,1}(:,i) = NaN(size(IN.YNT,1),1)';
            end
        end
%         YimgROIs{k,1} = tempYimgROIs;
    end
else
    colStart = 1;
    for k = 1:size(IN.YAtlas,1)
        a = unique(IN.YAtlas(k,:));
        a = a(a~=0); 
        AtlasROIs = a(~isnan(a));

        colEnd = colStart + size(AtlasROIs,2) - 1;
        YimgROIs{k, 1} = Yimg_nonan(:, colStart:colEnd);
        colStart = colEnd + 1; 
    end
end

% compute correlations
Y = [];

for k = 1:size(IN.YAtlas,1)
    if IN.autocorcorrect == 1
        data_ij = removenan_my([YimgROIs{k,1}',NTROIs{k,1}',TPMROIs{k,1}']);
        r_curr = partialcorr(data_ij(:,1:size(YimgROIs{k,1}',2)),...
                             data_ij(:,size(YimgROIs{k,1}',2)+1:size(YimgROIs{k,1}',2)+size(NTROIs{k,1}',2)),...
                             data_ij(:,size(YimgROIs{k,1}',2)+size(NTROIs{k,1}',2)+1:end),...
                             'type',cortype);
    else
        data_ij = removenan_my([YimgROIs{k,1}',NTROIs{k,1}']);
        r_curr= corr(data_ij(:,1:size(YimgROIs{k,1}',2)),...
                     data_ij(:,size(YimgROIs{k,1}',2)+1:size(YimgROIs{k,1}',2)+size(NTROIs{k,1}',2)),...
                     'type',cortype);
    end 
    Y = [Y,fishers_r_to_z(r_curr)];
end

% add nan_rows back if necessary
if sum(nan_rows) > 0
    Y_all = NaN(size(Yimg,1),size(Y,2));
    Y_all(~nan_rows, :) = Y;
else
    Y_all = Y;
end

% V_brainmask = spm_vol(brainmask);

% dims = V_brainmask.dim(1:3);
% 
% num_voxels = prod(dims); 
% 
% brainmask_indices = indVol_brainmask(:);
% 
% Yimg_sized = zeros(size(Yimg, 1), num_voxels);
% 
% Yimg_sized(:, brainmask_indices) = Yimg;

%old
% V = zeros(dims);
% Yimg_sized = zeros(size(Yimg,1),numel(V));
% for i = 1:size(Yimg,1)
%     V = zeros(dims);
%     V(indVol_brainmask) = Yimg(i,:);
%     Yimg_sized(i,:) = reshape(V,1,numel(V));
% end

% for k = 1:size(IN.YAtlas,1)
%     a = unique(IN.YAtlas(k,:));
%     a = a(a~=0);
%     AtlasROIs = a(~isnan(a));
%     
%     for i = 1:numel(AtlasROIs)
%         indVec = round(IN.YAtlas(k,:)) == round(AtlasROIs(i));
%         for j = 1:size(Yimg_sized,1)
%             YimgROIs{k,1}(j,i) = mean(Yimg_sized(j,indVec),2);
%         end
%     end
% end


end
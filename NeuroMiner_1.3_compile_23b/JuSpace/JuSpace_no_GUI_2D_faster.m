function Y = JuSpace_no_GUI_2D_faster(Yimg, IN, INDPruneVec)

YAtlas = IN.YAtlas;
NTROIs = IN.NTROIs;
V_brainmask = IN.V_brainmask;
indVol_brainmask = IN.indVol_brainmask;

if IN.autocorcorrect == 1
    autocorrect = 1;
    TPMROIs = IN.TPMROIs;
elseif IN.autocorcorrect == 2
    autocorrect = 0;
end

if IN.cortype == 1
    cortype = 'Spearman';
elseif IN.cortype == 2
    cortype = 'Pearson';
end

if ~isempty(INDPruneVec)

    % Number of rows in Yimg
    numRows = size(Yimg, 1);
    
    % Create a new matrix with zeros
    Yimg_new = zeros(numRows, size(Yimg, 2) + numel(INDPruneVec));
    
    % Initialize column counters
    colCounterA = 1;
    colCounterRemoved = 1;
    
    for i = 1:size(Yimg_new, 2)
        if any(INDPruneVec == i)
            % If the column index matches a removed column, insert zeros
            Yimg_new(:, i) = zeros(numRows, 1);
        else
            % Otherwise, copy the corresponding column from the original Yimg
            Yimg_new(:, i) = Yimg(:, colCounterA);
            colCounterA = colCounterA + 1;
        end
    end
    Yimg = Yimg_new;
end

% V_brainmask = spm_vol(brainmask);

dims = V_brainmask.dim(1:3);

%old
% V = zeros(dims);
% Yimg_sized = zeros(size(Yimg,1),numel(V));
% for i = 1:size(Yimg,1)
%     V = zeros(dims);
%     V(indVol_brainmask) = Yimg(i,:);
%     Yimg_sized(i,:) = reshape(V,1,numel(V));
% end

%new
num_voxels = prod(dims); 

brainmask_indices = indVol_brainmask(:);

Yimg_sized = zeros(size(Yimg, 1), num_voxels);

Yimg_sized(:, brainmask_indices) = Yimg;

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

YimgROIs = cell(size(IN.YAtlas,1),1);

for k = 1:size(IN.YAtlas,1)
    a = unique(IN.YAtlas(k,:));
    a = a(a~=0); 
    AtlasROIs = a(~isnan(a));

    tempYimgROIs = zeros(size(Yimg,1), numel(AtlasROIs));

    for i = 1:numel(AtlasROIs)
        indVec = round(IN.YAtlas(k,:)) == round(AtlasROIs(i));
        tempYimgROIs(:,i) = mean(removenan_my(Yimg_sized(:,indVec)'),1);
    end
    YimgROIs{k,1} = tempYimgROIs;
end

Y = [];

for k = 1:size(YAtlas,1)
    if autocorrect == 1
        data_ij = removenan_my([YimgROIs{k,1}',NTROIs{k,1}',TPMROIs{k,1}']);
        r_curr = partialcorr(data_ij(:,1:size(YimgROIs{k,1}',2)),data_ij(:,size(YimgROIs{k,1}',2)+1:size(YimgROIs{k,1}',2)+size(NTROIs{k,1}',2)),data_ij(:,size(YimgROIs{k,1}',2)+size(NTROIs{k,1}',2)+1:end),'type',cortype);
    else
        data_ij = removenan_my([YimgROIs{k,1}',NTROIs{k,1}']);
        r_curr= corr(data_ij(:,1:size(YimgROIs{k,1}',2)),data_ij(:,size(YimgROIs{k,1}',2)+1:size(YimgROIs{k,1}',2)+size(NTROIs{k,1}',2)),'type',cortype);
    end 
    Y = [Y,r_curr];
end

end
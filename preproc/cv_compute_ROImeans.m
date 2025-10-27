function [Ymean, IN] = cv_compute_ROImeans(Yimg, IN)

Ymean = [];

for k = 1:size(IN.YAtlas,1)
    tempYimgROIs = zeros(size(Yimg,1), numel(IN.AtlasROIs{k,1}));

    for i = 1:numel(IN.AtlasROIs{k,1})
        indVec = round(IN.YAtlas(k,:)) == round(IN.AtlasROIs{k,1}(i));
        tempYimgROIs(:,i) = mean(removenan_my(Yimg(:,indVec)'),1);
    end
    Ymean = [Ymean,tempYimgROIs];
end


% 
% S.Vm                         = spm_vol(IN.brainmask);
% [S.dims, S.indvol, ~, S.vox] = nk_ReadMaskIndVol(S.Vm, IN.atlas);
% image_for_size = char(IN.brainmask);
% if ~isfield(IN,'ROI_matrix')
%     IN.ROI_matrix = resize_img_useTemp_imcalc_NM(char(IN.atlas),image_for_size); %from JuSpace Toolbox
%     IN.maskVec = reshape(IN.ROI_matrix,size(IN.ROI_matrix,1)*size(IN.ROI_matrix,2)*size(IN.ROI_matrix,3),1)';
%     thres = 0; % should be possible to configure in menu
%     IN.maskVec = int64(IN.maskVec(IN.maskVec > thres));
%     % create mean GMV table
%     IN.u_maskVec = unique(IN.maskVec);
%     IN.nROI = numel(IN.u_maskVec);
% end
% Ymean = zeros(size(Yimg,1),IN.nROI);
% for i = 1:IN.nROI
%     indVec = IN.maskVec == IN.u_maskVec(i);
%     Ymean(:,i) = mean(Yimg(:,indVec),2);
% end




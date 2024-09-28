function Ypet = cv_apply_JuSpace(Yimg, brainmask, atlas, cortype, autocorcorrect, petlist, INDPruneVec)

Yimg_new = [];

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

% add JuSpace path

dir_tool = extractBefore(which('JuSpace'),[filesep,'JuSpace.m']);

if isempty(dir_tool)
    dir_tool = '/data/core-psy-archive/projects/LH_BEST/opt/JuSpace_v1.3';
end

% read brainmask for resizing of Yimg
Vm = spm_vol(brainmask);

if ~exist('label','var') || isempty(label), label = 0; end
if ~exist('labelop','var') || isempty(labelop), labelop = 'gt'; end

vox = sqrt(sum(Vm.mat(1:3,1:3).^2));                
Y   = [];
indvol=[];

for sl=1:Vm.dim(3)
    % read mask
   
    M = spm_matrix([0 0 sl 0 0 0 1 1 1]);
   
    mask_slice = spm_slice_vol(Vm,M,Vm.dim(1:2),1);
    ind0 = find(feval(labelop, mask_slice,label));
    ind = ind0 + (sl - 1)*prod(Vm.dim(1:2));
    indvol = [indvol; ind];
    clear mask_slice
end

dims = Vm.dim(1:3);

% [S.dims, S.indvol, ~, S.vox] = nk_ReadMaskIndVol(S.Vm, []);

% resize Yimg to to brainmask
V = zeros(dims);
C = zeros(size(Yimg,1),numel(V));
for i = 1:size(Yimg,1)
    V = zeros(dims);
    V(indvol) = Yimg(i,:); % transfer vector into 3D space
    C(i,:) = reshape(V,1,numel(V));
end

% create global variable to store atlas matrix
global JSMEM

for i = 1:size(atlas,1)
    JSMEM.atlas{i} = atlas(i,:);
    % create atlas matrix if not already stored in JSMEM
    if ~isfield(JSMEM,'atlas_matrix') || i > numel(JSMEM.atlas_matrix)
        atlas_matrix = resize_image_JuSpace(atlas(i,:),brainmask);    
        JSMEM.atlas_matrix{i} = atlas_matrix;
    else
        atlas_matrix = JSMEM.atlas_matrix{i};
    end    


    % reshape atlas into 1-D format
    atlasVec = reshape(atlas_matrix,size(atlas_matrix,1)*size(atlas_matrix,2)*size(atlas_matrix,3),1)';
    
    % get number of atlas regions
    a = unique(atlasVec(:));
    a = a(a~=0);
    atlas_vals = a(~isnan(a));
    
    %initialize Ymean with zeros
    Ymean{i} = zeros(size(Yimg,1),numel(atlas_vals));
    
    for j = 1:numel(atlas_vals)
        indVec = round(atlasVec) == round(atlas_vals(j));
        Ymean{i}(:,j) = mean(C(:,indVec),2);
    end
end

clear Yimg;
clear V;
clear S;
clear atlas_matrix; 
     
options = [4; cortype; 0; autocorcorrect; 0];

petvec = zeros([1,numel(petlist)]);
for j = 1:numel(petlist)
    petvec(j) = petlist{j}.listidx; 
end

if size(atlas,1) == 1
    Ypet = JuSpace_noGUI_2D(Ymean{1},atlas,options,petvec,brainmask,dir_tool);
else
    for i = 1:size(atlas,1)
        Ypet_curr = JuSpace_noGUI_2D(Ymean{i},atlas(i,:),options,petvec,brainmask,dir_tool);
        Ypet_all{i,1} = Ypet_curr;
    end

    numMatrices = size(Ypet_all,1);
    numColumns = size(Ypet_all{1,1},2);
    Ypet = zeros(size(Ypet_all{1,1},1),numColumns*numMatrices);
    
    for i = 1:numMatrices
        Ypet(:, i:numMatrices:end) = padarray(Ypet_all{i,1}, [0, (numMatrices - 1) * numColumns - size(Ypet_all{i,1}, 2)], 0, 'post');
    end
end

end
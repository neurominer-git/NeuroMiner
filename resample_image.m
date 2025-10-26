function P = resample_image(P, voxsiz, bounding_box)

if ~exist('P','var') || isempty(P)
    P = spm_select([1 Inf],'image');
end

if ~exist('voxsiz','var') || isempty(voxsiz)
    voxsiz = [3 3 3]; % new voxel size {mm}
end

V = spm_vol(P);

VV = [V(1) V(1)];
[p,n,e] = fileparts(V(1).fname);

for i=1:numel(V)
   if ~exist('bounding_box','var') || isempty(bounding_box)
       bb = spm_get_bbox(V(i));
   else
       bb = bounding_box;
   end
   VV(1:2)   = V(i);
   VV(1).mat = spm_matrix([bb(1,:) 0 0 0 voxsiz])*spm_matrix([-1 -1 -1]);
   VV(1).dim = ceil(VV(1).mat \ [bb(2,:) 1]' - 0.1)';
   VV(1).dim = VV(1).dim(1:3);
   spm_reslice(VV,struct('mean',false,'which',1,'interp',1)); % 1 for linear
end
P = fullfile(p,['r' n e]);
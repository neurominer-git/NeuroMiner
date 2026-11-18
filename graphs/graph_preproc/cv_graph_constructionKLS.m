function CM = cv_graph_constructionKLS(A, method, atlas, brainmask)
% KL divergence method following Kong et al. 2014
%
% FORMAT CM = cv_graph_constructionKLS(A, method, atlas, brainmask)
%
% A        : subjects x voxels matrix in the current NeuroMiner brain mask
% atlas    : parcellation atlas image path
% brainmask: NeuroMiner brain mask image path defining the voxel columns in A
%
% NOTE
% The original function signature used (A, method, brainmask, atlas), whereas
% cv_graph_PerfGraphConstruction called it as (A, method, parcellation,
% brainmask). The implementation is now aligned with the backend caller.
% The atlas is sampled inside the NeuroMiner brain-mask index vector so that
% ROI labels and columns of A have matching length.

if nargin < 4 || isempty(brainmask)
    error('cv_graph_constructionKLS:missingBrainmask', 'A brain mask path is required.');
end
if nargin < 3 || isempty(atlas)
    error('cv_graph_constructionKLS:missingAtlas', 'A parcellation atlas path is required.');
end

S.Vm                         = spm_vol(brainmask);
[S.dims, S.indvol, ~, S.vox] = nk_ReadMaskIndVol(S.Vm, []); %#ok<ASGLU>
image_for_size               = char(brainmask);

ROI_matrix = resize_img_useTemp_imcalc(char(atlas), image_for_size); % JuSpace helper
roiVecFull = reshape(ROI_matrix, 1, []);
roiVecMask = roiVecFull(S.indvol);
validVoxel = roiVecMask > 0 & isfinite(roiVecMask);
maskVec    = int64(roiVecMask(validVoxel));

if isempty(maskVec)
    error('cv_graph_constructionKLS:emptyAtlasMask', 'The parcellation atlas has no positive ROI labels inside the NeuroMiner brain mask.');
end

if size(A,2) == numel(validVoxel)
    A = A(:, validVoxel);
elseif size(A,2) ~= numel(maskVec)
    error('cv_graph_constructionKLS:dimensionMismatch', ...
        ['The number of columns in A (%d) matches neither the NeuroMiner brain-mask voxel count (%d) ', ...
         'nor the positive atlas-in-mask voxel count (%d).'], size(A,2), numel(validVoxel), numel(maskVec));
end

rois   = unique(maskVec);
n_rois = numel(rois);
if n_rois < 2
    error('cv_graph_constructionKLS:tooFewROIs', 'At least two atlas ROIs are required to compute pairwise KL divergences.');
end

pdf_struct = struct;
sp = 512; % retained legacy smoothing/grid setting
for i = 1:size(A,1)
    pp_values = A(i,:);
    ppname = sprintf('pp_%d',i);
    for j = 1:n_rois
        roi = rois(j);
        voxel_values = pp_values(maskVec == roi);
        roiname = sprintf('roi_%d',j);
        [~, ~, ~, cdf_values] = kde(voxel_values, sp);
        pdf_struct.(ppname).(roiname) = cdf_values;
    end
end

n_edges = (n_rois*n_rois-n_rois)/2;
kls_df = zeros(size(A,1), n_edges);

for i = 1:size(A,1)
    con_mat = diag(ones(n_rois,1));
    ppname = sprintf('pp_%d',i);
    pp_rois = pdf_struct.(ppname);
    for j = 1:n_rois
        for k = j+1:n_rois
            roiname1 = sprintf('roi_%d',j);
            roiname2 = sprintf('roi_%d',k);
            pdf_j = pp_rois.(roiname1);
            pdf_k = pp_rois.(roiname2);
            kls = symmetric_kldiv(pdf_j, pdf_k);
            con_mat(j,k) = kls;
            con_mat(k,j) = kls;
        end
    end
    con_mat_t = con_mat.';
    rem_idx = (1:size(con_mat_t,1)).' > (1:size(con_mat_t,2));
    edges_vec = con_mat_t(rem_idx);
    kls_df(i,:) = edges_vec;
end
CM = kls_df;
end

function sym_kldiv = symmetric_kldiv(p,q)
P = reshape(p,[numel(p),1]);
Q = reshape(q,[numel(q),1]);
if numel(P) ~= numel(Q)
    error('cv_graph_constructionKLS:pdfLengthMismatch', 'KL input vectors must have equal length.');
end
P = max(P, eps);
Q = max(Q, eps);
sym_kldiv = sum(P .* log2(P./Q) + Q .* log2(Q./P), 'omitnan');
end

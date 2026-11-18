function [Y, Thresh] = nk_ReturnSubSpaces(V, Vm, n_samples, n_subjects, Thresh, reportfile)
% ===============================================================================
% function [Y, Thresh] = nk_ReturnSubSpaces(V, Vm, n_samples, n_subjects, Thresh)
% ===============================================================================
% Vectorizes 3D NIFTI/ANALYZE images based on a space-defining image. This
% is the core image vectorization tool of NM and it currently works only
% together with SPM.
%
% (binarized or atlas-based image)
% V             :   Volume structure (output of spm_vol) of images to be read-in
% Vm            :   Volume structure of brain mask / atlas
% n_samples     :   N subject groups
% n_subjects    :   Vector of N x m subjects
% Thresh        :   Threshold structure with fields:
%                       Vml (unique values in mask, double),
%                       nVml (number of unique values in mask, double ),
%                       Lm (Value descriptors, nVml x 1 cell array), and
%                       threshop (Thresholding operation, cell)
% Optimized implementation:
%   The legacy implementation traversed slices first, then labels, and read
%   every subject image once per active label in each slice. This version
%   preserves the same SPM slice-sampling operation and the same feature
%   order, but separates mask indexing from subject data sampling. It reads
%   each subject slice once and distributes the sampled values to all active
%   mask/atlas labels for that slice.
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaoas Koutsouleris, 06/2026

if ~exist('V', 'var') || isempty(V)
    n_samples=1; n_subjects=Inf;
    V = spm_vol(spm_select(n_subjects,'image','Select images to read-in'));
end
if ~exist('Vm', 'var') || isempty(Vm)
    Vm = spm_vol(spm_select(1,'image','Select space-defining image'));
end
if ~exist('Thresh','var') || isempty(Thresh)
    Thresh = nk_DataIO3_SpaceDefImage_config(Vm);
end
if ~exist('reportfile','var'), reportfile = []; end

Lm = Thresh.Lm;
Vml = Thresh.Vml;
nVml = Thresh.nVml;
if nVml~=numel(Vml), nVml=1; end
threshop = Thresh.threshop;

% Prepare data container
Y = cell(1,nVml);

% Check which cell contains image info if V is a cell array
if iscell(V)
    indV=0;
    for i=1:numel(V)
        if ~isempty(V{i})
            indV = i; break
        end
    end
else
    indV=1;
end
if ~indV, fprintf('\n'); error('No images found to read in!'); end

% -------------------------------------------------------------------------
% Pass 1: read the space-defining image once per slice and cache the exact
% per-slice/per-label linear indices used by the legacy function. These
% indices define the final feature order: slice order, then MATLAB find(...)
% order within the current slice.
% -------------------------------------------------------------------------
sliceLabelInd = cell(Vm.dim(3), nVml);
sliceLabelN   = zeros(Vm.dim(3), nVml);
Mdat          = cell(Vm.dim(3), 1);

for sl=1:Vm.dim(3)
    M = spm_matrix([0 0 sl 0 0 0 1 1 1]);
    if iscell(V)
        Mdat{sl} = Vm.mat\V{indV}(1).mat\M;
    else
        Mdat{sl} = Vm.mat\V(indV).mat\M;
    end
    mask_slice = spm_slice_vol(Vm,M,Vm.dim(1:2),1);
    fprintf('\nReading mask slice %g/%g',sl,Vm.dim(3))
    for l = 1:nVml
        ind0 = find(feval(threshop{1},mask_slice,Vml(l)));
        sliceLabelInd{sl,l} = ind0;
        sliceLabelN(sl,l) = numel(ind0(:));
    end
    clear mask_slice
end

n_rows = sum(n_subjects(:));
progressTask = [];
if isfield(Thresh,'DataIOProgressTask') && isfield(Thresh,'DataIOProgressRows') && ...
        double(Thresh.DataIOProgressRows) == n_rows
    progressTask = Thresh.DataIOProgressTask;
end
labelOffsets = cell(1,nVml);
for l = 1:nVml
    n_feat_l = sum(sliceLabelN(:,l));
    if n_feat_l > 0
        Y{l} = zeros(n_rows, n_feat_l);
        labelOffsets{l} = [0; cumsum(sliceLabelN(:,l))];
    else
        Y{l} = [];
        labelOffsets{l} = zeros(Vm.dim(3)+1,1);
    end
end

% -------------------------------------------------------------------------
% Pass 2: subject-major sampling. Each subject slice is sampled once and the
% values are copied into the preallocated rows for all active labels. This
% preserves legacy numeric sampling, while avoiding repeated subject reads
% for every atlas/mask label. A compact command-window progress line is
% updated in-place at subject level in serial mode. The parfor path is
% retained for controlled testing, but it is disabled by default because SPM
% MEX/NIfTI access was observed to be unsafe with thread pools and showed
% limited benefit with process pools. To enable it explicitly, set
% Thresh.UseParallelReturnSubSpaces = true and start a process-based pool
% before calling this function. Thread pools are never used here.
% -------------------------------------------------------------------------
useParallel = false;
if nVml == 1 && ~isempty(Y{1}) && isfield(Thresh,'UseParallelReturnSubSpaces') && isequal(Thresh.UseParallelReturnSubSpaces, true)
    try
        if license('test','Distrib_Computing_Toolbox')
            pool = gcp('nocreate');
            if ~isempty(pool)
                poolClass = class(pool);
                useParallel = ~contains(poolClass, 'ThreadPool', 'IgnoreCase', true);
                if ~useParallel
                    warning('NM:nk_ReturnSubSpaces:ThreadPoolDisabled', ...
                        ['nk_ReturnSubSpaces disables parfor with thread pools because SPM ', ...
                         'NIfTI/MEX access is not reliable under parpool(''threads''). ', ...
                         'Using serial subject-major reading instead.']);
                end
            end
        end
    catch ME
        warning('NM:nk_ReturnSubSpaces:ParallelDisabled', ...
            'Parallel nk_ReturnSubSpaces path disabled: %s', ME.message);
        useParallel = false;
    end
end

if useParallel
    fprintf('\nReading subject data in parallel: %g subjects using existing process parpool.\n', n_rows);
    n_feat = size(Y{1},2);
    Y1 = zeros(n_rows, n_feat);
    if iscell(V)
        sampleOfRow = zeros(n_rows,1);
        indexOfRow  = zeros(n_rows,1);
        row0 = 0;
        for j=1:n_samples
            rows = row0 + (1:n_subjects(j));
            sampleOfRow(rows) = j;
            indexOfRow(rows) = 1:n_subjects(j);
            row0 = row0 + n_subjects(j);
        end
        parfor row = 1:n_rows
            j = sampleOfRow(row);
            i = indexOfRow(row);
            rowVals = zeros(1,n_feat);
            for sl=1:Vm.dim(3)
                try
                    d = spm_slice_vol( V{j}(i), Mdat{sl}, Vm.dim(1:2), 1 );
                catch
                    error('\nFile problem: %s,',V{j}(i).fname)
                end
                if any(isnan(d))
                    fprintf('\nFile problem: %s,',V{j}(i).fname);
                end
                n_here = sliceLabelN(sl,1);
                if n_here > 0
                    c1 = labelOffsets{1}(sl) + 1;
                    c2 = labelOffsets{1}(sl+1);
                    rowVals(c1:c2) = d(sliceLabelInd{sl,1});
                end
            end
            Y1(row,:) = rowVals;
        end
    else
        parfor row = 1:n_rows
            rowVals = zeros(1,n_feat);
            for sl=1:Vm.dim(3)
                try
                    d = spm_slice_vol( V(row), Mdat{sl}, Vm.dim(1:2), 1 );
                catch
                    error('\nFile problem: %s,',V(row).fname)
                end
                if any(isnan(d))
                    fprintf('\nFile problem: %s,',V(row).fname);
                end
                n_here = sliceLabelN(sl,1);
                if n_here > 0
                    c1 = labelOffsets{1}(sl) + 1;
                    c2 = labelOffsets{1}(sl+1);
                    rowVals(c1:c2) = d(sliceLabelInd{sl,1});
                end
            end
            Y1(row,:) = rowVals;
        end
    end
    Y{1} = Y1;
    if ~isempty(progressTask)
        progressTask = NMProgressTools.step(progressTask, n_rows, n_rows, ...
            sprintf('Read volumetric subject %g of %g.', n_rows, n_rows), true);
    end
    fprintf('Finished reading %g subjects in parallel.\n', n_rows);
else
    row0 = 0;
    updateEvery = max(1, round(n_rows/100));
    tStart = tic;
    if nVml == 1
        fprintf('\nReading subject data: ');
    else
        fprintf('\nReading subject data: ');
    end
    for j=1:n_samples
        for i = 1:n_subjects(j)
            row = row0 + i;
            if row == 1 || mod(row, updateEvery) == 0 || row == n_rows
                elapsed = toc(tStart);
                rate = row / max(elapsed, eps);
                remaining = (n_rows-row) / max(rate, eps);
                fprintf('\rReading subject %g/%g (%.1f%%) | %.2f subj/s | ETA %.1f min', ...
                    row, n_rows, 100*row/max(n_rows,1), rate, remaining/60);
            end
            for sl=1:Vm.dim(3)
                try
                    if iscell(V)
                        d = spm_slice_vol( V{j}(i), Mdat{sl}, Vm.dim(1:2), 1 );
                    else
                        d = spm_slice_vol( V(row), Mdat{sl}, Vm.dim(1:2), 1 );
                    end
                catch
                    if iscell(V)
                        error('\nFile problem: %s,',V{j}(i).fname)
                    else
                        error('\nFile problem: %s,',V(row).fname)
                    end
                end
                if any(isnan(d))
                    if iscell(V)
                        fprintf('\nFile problem: %s,',V{j}(i).fname);
                    else
                        fprintf('\nFile problem: %s,',V(row).fname);
                    end
                end
                for l = 1:nVml
                    n_here = sliceLabelN(sl,l);
                    if n_here > 0
                        c1 = labelOffsets{l}(sl) + 1;
                        c2 = labelOffsets{l}(sl+1);
                        Y{l}(row,c1:c2) = d(sliceLabelInd{sl,l});
                    end
                end
            end
            if ~isempty(progressTask) && (row == 1 || mod(row, updateEvery) == 0 || row == n_rows)
                progressTask = NMProgressTools.step(progressTask, row, n_rows, ...
                    sprintf('Read volumetric subject %g of %g.', row, n_rows), row == n_rows);
            end
        end
        row0 = row0 + n_subjects(j);
    end
    fprintf('\n');
end

if ~isempty(reportfile) && exist(reportfile,'file')
    fid = fopen(reportfile,'a');
    fprintf(fid,'\n\nIMPORT SUMMARY:');
    fprintf(fid,'\n===============');
    cLm = char(Lm); sLm = size(cLm,2);
    for l=1:nVml
        fprintf(fid,['\nLabel %' num2str(numel(num2str(nVml))) 'g [ %' num2str(sLm) 's ]: %g voxels'],l, Lm{l}, size(Y{l},2));
    end
end
if nVml <2, Y = Y{1}; end

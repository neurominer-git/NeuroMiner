function [sY, isSpatialPreprocessed] = nk_PerfSpatFilt( Y, CURACT, Param )
% nk_PerfSpatFilt - Performs spatial filtering on data with optional fusion
%
% Syntax:
%   sY = nk_PerfSpatFilt(Y, CURACT, Param)
%
% Description:
%   The function `nk_PerfSpatFilt` applies spatial filtering to input data 
%   `Y` based on the parameters provided in `CURACT` and `Param`. If the 
%   preprocessing structure `CURACT` indicates that data fusion has occurred, 
%   the function extracts the appropriate modality, applies the spatial 
%   filtering, and re-fuses the data. The function handles multiple modalities, 
%   brain masks, and various data types, ensuring that the filtered data is 
%   correctly processed and assembled.
%
% Input Arguments:
%   Y      - The data to be filtered, which can be a cell array or matrix. 
%            The data may contain multiple modalities to be processed.
%   CURACT - Structure containing current active preprocessing parameters, 
%            including spatial settings that define how the data should be 
%            filtered (e.g., brain mask paths, bad coordinates).
%   Param  - Structure containing additional parameters required for filtering, 
%            such as dimension vectors, data types, and threshold values.
%
% Output:
%   sY     - The filtered data, returned as a cell array or matrix depending 
%            on the input. If spatial filtering is not applicable, the 
%            original input data `Y` is returned unchanged.
%
% Notes:
%   - The function assumes that data fusion may have been performed before 
%     smoothing, and handles the fusion and filtering process accordingly.
%   - The function manages missing data and NaN values appropriately during 
%     the filtering process.
%   - If the brain mask specified in `Param` is not found, the function 
%     attempts to create a temporary volume for processing. 
%
% Example:
%   sY = nk_PerfSpatFilt(Y, CURACT, Param);
%
% See also:
%   nk_SpatFilt, nk_ReadMaskIndVol, spm_vol
% =========================================================================
% (c) Nikolaos Koutsouleris, 26/08/2024

if isfield(CURACT,'SPATIAL') && CURACT.SPATIAL.cubetype>1
    % If data fusion has happened before subject-specific spatial preprocessing
    % extract the modality, process it and fuse it again 
    S = CURACT.SPATIAL;
    terminalTypes = [5 7 8]; % waveletSpatial (cubetype 9) is image-preserving and must use mask geometry
    dimvecx = Param.dimvecx;
    if iscell(Param.brainmask), nM = numel(Param.brainmask); else, nM=1; end
    nP = size(CURACT.SPATIAL.PX.opt,1);
    if ~nP, nP=1;end
    fY = cell(nP,nM);
    sY = cell(nP,1);
    Vm = []; Vmvol = [];
    for zu = 1:nM
        datatype = Param.datatype(zu);
        if datatype == 1, brainmask = nk_RemCommaFromStr(Param.brainmask{zu}); else, brainmask = ''; end
        badcoords = Param.badcoords{zu};
        if nM>1
            LABEL = Param.threshval{zu};
            LABELOPERATOR = Param.threshop{zu};
            if isfield(Param,'Vm')
                Vm = Param.Vm{zu};
                Vmvol = Param.Vmvol{zu};
            end
        else
            LABEL = Param.threshval;
            LABELOPERATOR = Param.threshop;
            if isfield(Param,'Vm')
                Vm = Param.Vm;
                Vmvol = Param.Vmvol;
            end
        end
        dimst               = dimvecx( zu ) + 1; 
        dimend              = dimvecx( zu + 1 );
        if iscell(Y)
            if zu<=numel(Y)
                tY          = Y{zu}(:,dimst:dimend);     
            else
                tY          = [];
            end
        else
            if size(Y,2)<dimend
                Y = Y';
            end
            tY                  = Y(:,dimst:dimend);     
        end
        if datatype == 2 && ismember(double(S.cubetype),[4 9])
            if nM > 1
                contract = Param.surfaceGeometryContract{zu};
            else
                contract = Param.surfaceGeometryContract;
            end
            if size(tY,2) ~= contract.vertexCount
                error('nk_PerfSpatFilt:surfaceFeatureAxisMismatch', ...
                    'Surface data contain %d features, but the DataIO mesh contains %d vertices.', ...
                    size(tY,2),contract.vertexCount);
            end
            [masks,~,maskGroup] = unique(isfinite(tY),'rows','stable');
            for zv = 1:nP
                fY{zv,zu} = nan(size(tY),'like',tY);
            end
            completed = 0;
            total = nP * size(tY,1);
            for group = 1:size(masks,1)
                rows = maskGroup==group;
                op = nk_SurfaceHeatKernel(contract,masks(group,:).');
                for zv = 1:nP
                    value = S.PX.opt(zv);
                    completedBefore = completed;
                    onCompleted = @(done,batchSize) report_spatial_progress( ...
                        datatype,S.cubetype,completedBefore+done,total,batchSize,zu,nM,zv,nP);
                    switch double(S.cubetype)
                        case 4
                            fY{zv,zu}(rows,:) = nk_SurfaceHeatFilter(tY(rows,:),op,value,onCompleted);
                        case 9
                            fprintf('\nSurface graph-wavelet level %g: ',value);
                            fY{zv,zu}(rows,:) = nk_SurfaceGraphWavelet( ...
                                tY(rows,:),op,value,S.WAVELET,onCompleted);
                            fprintf('\n');
                    end
                    completed = completed + nnz(rows);
                end
            end
        elseif datatype ~= 1
            fY(:,zu) = repmat({tY},nP,1);
        else
            tmpflg = false;
            indnan = false;
            if ~ismember(S.cubetype, terminalTypes)
            if ~exist(brainmask,'file')
                if ~isempty(Vm) && ~isempty(Vmvol)
                    tmpflg = true;
                    Vm = WriteTempVol(Vm, Vmvol, tmpflg);
                    brainmask = Vm.fname;
                else
                    error('Space-defining image %s cannot be found! Make sure your paths are up-to-date!', brainmask);
                end
            end
            S.Vm                         = spm_vol(brainmask);
            [S.dims, S.indvol, ~, S.vox] = nk_ReadMaskIndVol(S.Vm, S.Vm, LABEL, LABELOPERATOR);
            if isfield(Param,'indNonRem') && ~isempty(Param.indNonRem) && sum(~Param.indNonRem) > 0
                indNonRem                = Param.indNonRem;
                ttY                      = zeros(size(tY,1),size(indNonRem)); 
                ttY(:,indNonRem)         = tY; 
            else
                ttY                      = tY;
            end
            nanMask = isnan(ttY);
            indnan = any(nanMask,2);
            else
                ttY = tY;
            end
            S.badcoords = badcoords;
            onProgress = @(done,batchSize,option) report_spatial_progress( ...
                datatype,S.cubetype,(option-1)*size(ttY,1)+done, ...
                nP*size(ttY,1),batchSize,zu,nM,option,nP);
            tY = nk_SpatFilt(ttY,S,onProgress);
            clear ttY
            for zv = 1:nP
                fY{zv,zu} = tY{zv};
                if any(indnan)
                    fY{zv,zu}(nanMask) = nan;
                end
            end
            if tmpflg, DeleteTempVol(Vm,tmpflg); end
        end
    end
    for zv = 1:nP, sY{zv} = cell2mat(fY(zv,:));end
    isSpatialPreprocessed = true;
else
    sY = Y;
    isSpatialPreprocessed = false;
end
end

function report_spatial_progress(datatype,cubetype,completed,total,batchSize,modal,nM,option,nP)
% One progress contract for completed Gaussian and wavelet subject batches.
global CVPOS
if datatype==2, domain='Surface'; else, domain='Volumetric'; end
if cubetype==9
    kind='wavelet'; name='wavelet reconstruction';
    if datatype==2, fprintf('%s',repmat('.',1,batchSize)); end
else
    kind='gaussian'; name='Gaussian smoothing';
end
NMRuntimeProgressTools.writeLegacyModuleProgressSafe( ...
    [domain ' ' name], ...
    sprintf('%s %s, modality %d/%d, option %d/%d: %d/%d subject-branch operations completed.', ...
        domain,kind,modal,nM,option,nP,completed,total), ...
    100*completed/total,CVPOS,[lower(domain) '_' kind]);
end

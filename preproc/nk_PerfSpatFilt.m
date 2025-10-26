function sY = nk_PerfSpatFilt( Y, CURACT, Param )
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
    % If data fusion has happened before the smoothing
    % extract the modality, smooth it and fuse it again 
    S = CURACT.SPATIAL;
    dimvecx = Param.dimvecx;
    if iscell(Param.brainmask), nM = numel(Param.brainmask); else, nM=1; end
    nP = size(CURACT.SPATIAL.PX.opt,1);
    if ~nP, nP=1;end
    fY = cell(nP,nM);
    sY = cell(nP,1);
    Vm = []; Vmvol = [];
    for zu = 1:nM
        if nM>1
            brainmask       = nk_RemCommaFromStr(Param.brainmask{zu});
            datatype        = Param.datatype(zu);
            if isfield(Param,'Vm')
                Vm          = Param.Vm{zu};
                Vmvol       = Param.Vmvol{zu};
            end
            badcoords       = Param.badcoords{zu};
            LABEL           = Param.threshval{zu};
            LABELOPERATOR   = Param.threshop{zu};
        else
            brainmask       = nk_RemCommaFromStr(Param.brainmask{1});
            datatype        = Param.datatype;
            if isfield(Param,'Vm')
                Vm          = Param.Vm;
                Vmvol       = Param.Vmvol;
            end
            badcoords       = Param.badcoords{1};
            LABEL           = Param.threshval;
            LABELOPERATOR   = Param.threshop;
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
        if datatype ~= 1
            for zv = 1:nP
                fY{zv, zu} = tY; 
            end
        elseif CURACT.SPATIAL.cubetype ~= 5 && CURACT.SPATIAL.cubetype ~= 7
            tmpflg = false;
            if ~exist(brainmask,'file')
                if ~isempty(Vm) && ~isempty(Vmvol)
                    tmpflg = true;
                    Vm = WriteTempVol(Vm, Vmvol, tmpflg);
                    brainmask = Vm.fname;
                else
                    error('Space-defining image %s cannot be found! Make sure your paths are up-to-date!', brainmask);
                end
            end
            S.brainmask                  = brainmask;
            S.badcoords                  = badcoords;
            S.Vm                         = spm_vol(S.brainmask);
            [S.dims, S.indvol, ~, S.vox] = nk_ReadMaskIndVol(S.Vm, S.Vm, LABEL, LABELOPERATOR);
            if isfield(Param,'indNonRem') && ~isempty(Param.indNonRem) && sum(~Param.indNonRem) > 0
                indNonRem                = Param.indNonRem;
                ttY                      = zeros(size(tY,1),size(indNonRem)); 
                ttY(:,indNonRem)         = tY; 
            else
                ttY                      = tY;
            end
            nanMask                      = isnan(ttY);
            indnan                       = any(nanMask,2);
            tY                           = nk_SpatFilt(ttY, S);
            clear ttY
            % Transfer smoothed data into container and handle NaNs
            % properly
            for zv = 1:nP
                fY{zv,zu} = tY{zv};
                if any(indnan)
                    fY{zv,zu}(nanMask) = nan; 
                end
            end
            if tmpflg, DeleteTempVol(Vm,tmpflg); end
        else
            S.badcoords                  = badcoords;
            ttY                          = tY;
            tY                           = nk_SpatFilt(ttY, S);
            for zv = 1:nP
                fY{zv,zu} = tY{zv};
            end
        end
    end
    for zv = 1:nP, sY{zv} = cell2mat(fY(zv,:));end
else
    sY = Y;
end
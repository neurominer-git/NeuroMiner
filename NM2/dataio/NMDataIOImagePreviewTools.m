classdef NMDataIOImagePreviewTools
    % Preview-only utilities for browser-based imaging DataIO.
    % These methods do not mutate NM and are intentionally independent from
    % the import/commit path.

    methods (Static)
        function out = renderAxialOverlay(imageFile, maskFile, opts)
            % renderAxialOverlay  Render a lightweight axial image/mask overlay preview for the DataIO viewer.
            %
            % Consumes imageFile, maskFile, opts; returns out.
            % It produces temporary viewer artifacts and does not define committed NM modality semantics.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling.
            %
            % opts.sliceIndex: selects the image/surface slice or subject index rendered for preview.
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = struct('ok',false,'message','Not rendered.','imageDataUri','', ...
                'sliceIndex',NaN,'nSlices',NaN,'imageDim',[],'maskDim',[],'voxelSize',[], ...
                'maskVoxelCountOnSlice',NaN,'warning','');

            imageFile = NMDataIOImagePreviewTools.asChar(imageFile);
            maskFile = NMDataIOImagePreviewTools.asChar(maskFile);
            spaceDefType = lower(NMDataIOImagePreviewTools.optionChar(opts, 'spaceDefType', 'brainmask'));
            isAtlas = strcmp(spaceDefType, 'atlas');
            [spmImageFiles, imageMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({imageFile}, 'imageViewer.imageFile', true);
            if NMDataIOMessageTools.hasFatal(imageMessages)
                out.message = NMDataIOImagePreviewTools.firstMessageText(imageMessages, sprintf('Image file cannot be resolved for SPM: %s', imageFile));
                out.messages = imageMessages;
                return;
            end
            [spmMaskFiles, maskMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({maskFile}, 'imageViewer.maskFile', true);
            if NMDataIOMessageTools.hasFatal(maskMessages)
                out.message = NMDataIOImagePreviewTools.firstMessageText(maskMessages, sprintf('Brainmask file cannot be resolved for SPM: %s', maskFile));
                out.messages = maskMessages;
                return;
            end
            imageFileSPM = spmImageFiles{1};
            maskFileSPM = spmMaskFiles{1};
            out.fileResolutionMessages = [imageMessages; maskMessages];
            req = {'spm_vol','spm_slice_vol','spm_matrix'};
            for i = 1:numel(req)
                if ~NMDataIOImagePreviewTools.functionAvailable(req{i})
                    out.message = sprintf('Required SPM function is not available: %s', req{i});
                    return;
                end
            end

            try
                Vi = spm_vol(imageFileSPM);
                Vm = spm_vol(maskFileSPM);
                if numel(Vi) > 1, Vi = Vi(1); end
                if numel(Vm) > 1, Vm = Vm(1); end
                out.imageDim = double(Vi.dim(:)');
                out.maskDim = double(Vm.dim(:)');
                out.nSlices = double(Vm.dim(3));
                out.voxelSize = sqrt(sum(Vm.mat(1:3,1:3).^2,1));

                tol = 1e-6;
                if isfield(opts,'sliceIndex') && ~isempty(opts.sliceIndex) && isfinite(double(opts.sliceIndex)) && double(opts.sliceIndex) > 0
                    sliceIndex = round(double(opts.sliceIndex));
                    sliceIndex = min(max(sliceIndex,1), Vm.dim(3));
                else
                    counts = zeros(Vm.dim(3),1);
                    for sl = 1:Vm.dim(3)
                        M0 = spm_matrix([0 0 sl 0 0 0 1 1 1]);
                        ms = spm_slice_vol(Vm, M0, Vm.dim(1:2), 1);
                        fin = ms(isfinite(ms));
                        if isAtlas
                            counts(sl) = nnz(isfinite(ms) & ms ~= 0);
                        else
                            if ~isempty(fin) && ~all(abs(fin(:)) <= tol | abs(fin(:) - 1) <= tol)
                                out.message = 'Brainmask is not binary within tolerance 1e-6; viewer expects finite 0/1 mask values.';
                                return;
                            end
                            counts(sl) = nnz(abs(ms - 1) <= tol);
                        end
                    end
                    [mx, sliceIndex] = max(counts);
                    if isempty(sliceIndex) || ~isfinite(sliceIndex) || mx < 1, sliceIndex = round(Vm.dim(3)/2); end
                end
                out.sliceIndex = double(sliceIndex);

                M = spm_matrix([0 0 sliceIndex 0 0 0 1 1 1]);
                maskSlice = spm_slice_vol(Vm, M, Vm.dim(1:2), 1);
                finiteMask = maskSlice(isfinite(maskSlice));
                if isAtlas
                    if isempty(finiteMask)
                        out.message = 'Atlas viewer overlay contains no finite values.';
                        return;
                    end
                    msk = isfinite(maskSlice) & maskSlice ~= 0;
                else
                    if isempty(finiteMask) || ~all(abs(finiteMask(:)) <= tol | abs(finiteMask(:) - 1) <= tol)
                        out.message = 'Brainmask is not binary within tolerance 1e-6; viewer expects finite 0/1 mask values.';
                        return;
                    end
                    msk = abs(maskSlice - 1) <= tol;
                end
                out.maskVoxelCountOnSlice = double(nnz(msk));
                M1 = Vm.mat \ Vi.mat \ M;
                img = double(spm_slice_vol(Vi, M1, Vm.dim(1:2), 1));
                img = rot90(img);
                msk = rot90(msk);
                img(~isfinite(img)) = NaN;
                finiteImg = img(isfinite(img));
                if isempty(finiteImg)
                    out.message = sprintf('Selected mask-space slice %g contains no finite sampled image values.', sliceIndex);
                    return;
                end
                lo = prctile(finiteImg, 1);
                hi = prctile(finiteImg, 99);
                if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
                    lo = min(finiteImg); hi = max(finiteImg);
                end
                if hi <= lo, hi = lo + eps; end
                gray = uint8(max(0, min(1, (img - lo) ./ (hi - lo))) .* 255);
                gray(~isfinite(img)) = 0;
                rgb = repmat(gray, [1 1 3]);
                alpha = NMDataIOImagePreviewTools.optionDouble(opts, 'maskOpacity', 0.35);
                alpha = max(0, min(1, alpha));
                red = rgb(:,:,1); green = rgb(:,:,2); blue = rgb(:,:,3);
                red(msk) = uint8((1-alpha) .* double(red(msk)) + alpha .* 255);
                green(msk) = uint8((1-alpha) .* double(green(msk)));
                blue(msk) = uint8((1-alpha) .* double(blue(msk)));
                rgb(:,:,1) = red; rgb(:,:,2) = green; rgb(:,:,3) = blue;

                % Browser previews are meant for human plausibility checks.
                % Mask-space slices can be small (for example 65x77 at 3 mm);
                % enlarge before PNG encoding so the viewer is useful without
                % depending on browser-specific interpolation of tiny images.
                minDisplay = 520;
                maxScale = 10;
                sz2 = size(rgb);
                scale = max(1, min(maxScale, floor(minDisplay ./ max(1, min(sz2(1), sz2(2))))));
                if scale > 1
                    rgb = repelem(rgb, scale, scale, 1);
                end

                tmp = [tempname '.png'];
                imwrite(rgb, tmp, 'png');
                fid = fopen(tmp, 'rb');
                if fid < 0
                    out.message = sprintf('Could not read temporary PNG: %s', tmp);
                    return;
                end
                c = onCleanup(@() NMDataIOImagePreviewTools.cleanupFile(fid, tmp)); %#ok<NASGU>
                bytes = fread(fid, Inf, '*uint8');
                out.imageDataUri = ['data:image/png;base64,' NMDataIOImagePreviewTools.base64(bytes)];
                out.ok = true;
                out.message = sprintf('Rendered axial mask-space slice %g/%g.', out.sliceIndex, out.nSlices);
            catch ME
                out.ok = false;
                out.message = sprintf('%s: %s', ME.identifier, ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
            end
        end

        function out = prepareAxialVolume(imageFile, maskFile, opts)
            % prepareAxialVolume  Read and normalize image/mask volume data for axial preview rendering.
            %
            % Consumes imageFile, maskFile, opts; returns out.
            % It produces temporary viewer artifacts and does not define committed NM modality semantics.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            %
            % opts.sliceIndex: selects the image/surface slice or subject index rendered for preview.
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = struct('ok',false,'message','Viewer volume not prepared.', ...
                'viewerMode','client_volume','imageVolumeUrl','','maskVolumeUrl','', ...
                'dataType','float32','maskDataType','uint8','overlayMode','brainmask','roiLabels',[], ...
                'dims',[],'sliceIndex',NaN, ...
                'nSlices',NaN,'imageDim',[],'maskDim',[],'voxelSize',[], ...
                'window',[],'maskVoxelCountOnSlice',NaN,'warning','');

            imageFile = NMDataIOImagePreviewTools.asChar(imageFile);
            maskFile = NMDataIOImagePreviewTools.asChar(maskFile);
            tmpDir = NMDataIOImagePreviewTools.optionChar(opts, 'tmpDir', '');
            spaceDefType = lower(NMDataIOImagePreviewTools.optionChar(opts, 'spaceDefType', 'brainmask'));
            isAtlas = strcmp(spaceDefType, 'atlas');
            [spmImageFiles, imageMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({imageFile}, 'imageViewer.volume.imageFile', true);
            if NMDataIOMessageTools.hasFatal(imageMessages)
                out.message = NMDataIOImagePreviewTools.firstMessageText(imageMessages, sprintf('Image file cannot be resolved for SPM: %s', imageFile));
                out.messages = imageMessages;
                return;
            end
            [spmMaskFiles, maskMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({maskFile}, 'imageViewer.volume.maskFile', true);
            if NMDataIOMessageTools.hasFatal(maskMessages)
                out.message = NMDataIOImagePreviewTools.firstMessageText(maskMessages, sprintf('Brainmask file cannot be resolved for SPM: %s', maskFile));
                out.messages = maskMessages;
                return;
            end
            imageFileSPM = spmImageFiles{1};
            maskFileSPM = spmMaskFiles{1};
            out.fileResolutionMessages = [imageMessages; maskMessages];
            req = {'spm_vol','spm_slice_vol','spm_matrix'};
            for i = 1:numel(req)
                if ~NMDataIOImagePreviewTools.functionAvailable(req{i})
                    out.message = sprintf('Required SPM function is not available: %s', req{i});
                    return;
                end
            end

            try
                Vi = spm_vol(imageFileSPM);
                Vm = spm_vol(maskFileSPM);
                if numel(Vi) > 1, Vi = Vi(1); end
                if numel(Vm) > 1, Vm = Vm(1); end
                out.imageDim = double(Vi.dim(:)');
                out.maskDim = double(Vm.dim(:)');
                out.nSlices = double(Vm.dim(3));
                out.voxelSize = sqrt(sum(Vm.mat(1:3,1:3).^2,1));

                nSlices = double(Vm.dim(3));
                vol = [];
                maskVol = [];
                maskCounts = zeros(nSlices,1);
                tol = 1e-6;
                roiIDValues = [];
                for sl = 1:nSlices
                    M0 = spm_matrix([0 0 sl 0 0 0 1 1 1]);
                    maskSlice = spm_slice_vol(Vm, M0, Vm.dim(1:2), 1);
                    finiteMask = maskSlice(isfinite(maskSlice));
                    if isAtlas
                        if isempty(finiteMask)
                            out.message = 'Atlas viewer overlay contains no finite values.';
                            return;
                        end
                        msk = rot90(uint16(max(0, round(maskSlice))));
                        roiIDValues = union(roiIDValues, double(unique(msk(msk > 0)))');
                    else
                        if isempty(finiteMask) || ~all(abs(finiteMask(:)) <= tol | abs(finiteMask(:) - 1) <= tol)
                            out.message = 'Brainmask is not binary within tolerance 1e-6; viewer expects finite 0/1 mask values.';
                            return;
                        end
                        msk = rot90(uint8(abs(maskSlice - 1) <= tol));
                    end
                    M1 = Vm.mat \ Vi.mat \ M0;
                    img = rot90(single(spm_slice_vol(Vi, M1, Vm.dim(1:2), 1)));
                    if sl == 1
                        vol = zeros([size(img,1), size(img,2), nSlices], 'single');
                        if isAtlas
                            maskVol = zeros([size(msk,1), size(msk,2), nSlices], 'uint16');
                        else
                            maskVol = false([size(msk,1), size(msk,2), nSlices]);
                        end
                    end
                    if ~isequal(size(img), [size(vol,1), size(vol,2)]) || ~isequal(size(msk), [size(maskVol,1), size(maskVol,2)])
                        out.message = sprintf('Viewer volume assembly failed at slice %g because sampled slice dimensions changed unexpectedly.', sl);
                        return;
                    end
                    vol(:,:,sl) = img;
                    maskVol(:,:,sl) = msk;
                    maskCounts(sl) = nnz(msk > 0);
                end

                if isfield(opts,'sliceIndex') && ~isempty(opts.sliceIndex) && isfinite(double(opts.sliceIndex)) && double(opts.sliceIndex) > 0
                    sliceIndex = round(double(opts.sliceIndex));
                    sliceIndex = min(max(sliceIndex,1), nSlices);
                else
                    [mx, sliceIndex] = max(maskCounts);
                    if isempty(sliceIndex) || ~isfinite(sliceIndex) || mx < 1, sliceIndex = round(nSlices/2); end
                end
                out.sliceIndex = double(sliceIndex);
                out.maskVoxelCountOnSlice = double(maskCounts(sliceIndex));

                finiteImg = vol(isfinite(vol));
                if isempty(finiteImg)
                    out.message = 'No finite image values were available after sampling the subject image into brainmask space.';
                    return;
                end
                maxWindowValues = 1000000;
                if numel(finiteImg) > maxWindowValues
                    take = unique(round(linspace(1, numel(finiteImg), maxWindowValues)));
                    finiteForWindow = finiteImg(take);
                else
                    finiteForWindow = finiteImg;
                end
                lo = prctile(double(finiteForWindow(:)), 1);
                hi = prctile(double(finiteForWindow(:)), 99);
                if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
                    lo = double(min(finiteImg)); hi = double(max(finiteImg));
                end
                if hi <= lo, hi = lo + eps; end

                [assetDir, assetUrlBase, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
                if ~isempty(assetErr)
                    out.message = assetErr;
                    return;
                end
                if exist(assetDir,'dir') ~= 7
                    [ok,msg] = mkdir(assetDir);
                    if ~ok
                        out.message = sprintf('Could not create the temporary folder needed for image viewing (%s): %s', assetDir, msg);
                        return;
                    end
                end
                token = NMDataIOImagePreviewTools.safeToken();
                pkgDir = fullfile(assetDir, token);
                [ok,msg] = mkdir(pkgDir);
                if ~ok
                    out.message = sprintf('Could not create viewer volume package directory %s: %s', pkgDir, msg);
                    return;
                end
                imageBin = fullfile(pkgDir, 'image_f32.bin');
                if isAtlas
                    maskBin = fullfile(pkgDir, 'atlas_u16.bin');
                    NMDataIOImagePreviewTools.writeBinaryFile(imageBin, vol(:), 'single');
                    NMDataIOImagePreviewTools.writeBinaryFile(maskBin, uint16(maskVol(:)), 'uint16');
                    out.maskDataType = 'uint16';
                    out.overlayMode = 'atlas';
                    out.roiLabels = NMDataIOImagePreviewTools.viewerRoiLabels(maskFile, opts, roiIDValues);
                    out.maskVolumeUrl = [assetUrlBase '/' token '/atlas_u16.bin'];
                else
                    maskBin = fullfile(pkgDir, 'mask_u8.bin');
                    NMDataIOImagePreviewTools.writeBinaryFile(imageBin, vol(:), 'single');
                    NMDataIOImagePreviewTools.writeBinaryFile(maskBin, uint8(maskVol(:)), 'uint8');
                    out.maskDataType = 'uint8';
                    out.overlayMode = 'brainmask';
                    out.maskVolumeUrl = [assetUrlBase '/' token '/mask_u8.bin'];
                end

                out.imageVolumeUrl = [assetUrlBase '/' token '/image_f32.bin'];
                out.dims = double([size(vol,1), size(vol,2), size(vol,3)]);
                out.window = [double(lo), double(hi)];
                out.ok = true;
                if isAtlas
                    out.message = sprintf('Prepared client-side axial viewer volume in atlas space (%g x %g x %g; %g ROI label(s)).', out.dims(1), out.dims(2), out.dims(3), numel(roiIDValues));
                else
                    out.message = sprintf('Prepared client-side axial viewer volume in brainmask space (%g x %g x %g).', out.dims(1), out.dims(2), out.dims(3));
                end
            catch ME
                out.ok = false;
                out.message = sprintf('%s: %s', ME.identifier, ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
            end
        end
    end

    methods (Static)
        function [assetDir, assetUrlBase, err] = viewerAssetDir(tmpDir)
            % viewerAssetDir  Resolve or create the temporary asset directory used by the browser image viewer.
            %
            % Consumes tmpDir; returns assetDir, assetUrlBase, err.
            % It produces temporary viewer artifacts and does not define committed NM modality semantics.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            err = '';
            tmpDir = NMDataIOImagePreviewTools.asChar(tmpDir);
            if isempty(tmpDir)
                assetDir = fullfile(tempdir, 'nm_dataio_viewer_cache');
                assetUrlBase = '';
                err = 'Internal DataIO viewer error: no browser session tmpDir was provided for binary viewer-volume export.';
                return;
            end
            webDir = fileparts(tmpDir);
            if isempty(webDir) || exist(webDir,'dir') ~= 7
                assetDir = '';
                assetUrlBase = '';
                err = sprintf('Internal DataIO viewer error: browser web directory could not be inferred from tmpDir %s.', tmpDir);
                return;
            end
            assetDir = fullfile(webDir, 'dataio_viewer_cache');
            assetUrlBase = 'dataio_viewer_cache';
        end

        function token = safeToken()
            % safeToken  Create a filesystem/UI-safe token from user or metadata text.
            %
            % No required inputs -> token.
            % It produces temporary viewer artifacts and does not define committed NM modality semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            try
                token = ['vol_' strrep(char(java.util.UUID.randomUUID()), '-', '_')];
            catch
                token = ['vol_' regexprep(tempname, '[^A-Za-z0-9_]', '_')];
            end
        end

        function writeBinaryFile(path, data, precision)
            % writeBinaryFile  Write numeric viewer payload data in the binary format expected by browser assets.
            %
            % Path, data, precision -> no explicit output.
            % It produces temporary viewer artifacts and does not define committed NM modality semantics.
            % Performs explicit file-system IO; throws on invalid preconditions instead of returning an ambiguous partial result.
            fid = fopen(path, 'w', 'ieee-le');
            if fid < 0
                error('NMDataIOImagePreviewTools:FileWrite', 'Could not open %s for binary export.', path);
            end
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            count = fwrite(fid, data, precision);
            if count ~= numel(data)
                error('NMDataIOImagePreviewTools:FileWrite', 'Could not write all binary elements to %s.', path);
            end
        end
    end

    methods (Static)
        function labels = viewerRoiLabels(atlasFile, opts, roiIDs)
            % viewerRoiLabels  Resolve ROI label text for atlas overlays displayed in the viewer.
            %
            % Consumes atlasFile, opts, roiIDs; returns labels.
            % It produces temporary viewer artifacts and does not define committed NM modality semantics.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            labels = struct();
            roiIDs = double(roiIDs(:)');
            for i = 1:numel(roiIDs)
                labels.(sprintf('roi_%.0f', roiIDs(i))) = sprintf('ROI_%g', roiIDs(i));
            end
            try
                labelFile = NMDataIOImagePreviewTools.optionChar(opts, 'atlasLabelFile', '');
                if isempty(labelFile)
                    cand = NMDataIOAtlasDescriptorTools.detectAtlasDescriptorCandidates(atlasFile);
                    if strcmp(cand.status,'single'), labelFile = cand.files{1}; end
                end
                if isempty(labelFile), return; end
                descOpts = struct('roiIDs', roiIDs, ...
                    'delimiter', NMDataIOImagePreviewTools.optionChar(opts, 'atlasLabelDelimiter', 'auto'), ...
                    'hasHeader', NMDataIOImagePreviewTools.optionChar(opts, 'atlasLabelHasHeader', 'auto'), ...
                    'idColumn', NMDataIOImagePreviewTools.optionChar(opts, 'atlasLabelIDColumn', ''), ...
                    'nameColumn', NMDataIOImagePreviewTools.optionChar(opts, 'atlasLabelNameColumn', ''));
                desc = NMDataIOAtlasDescriptorTools.inspectAtlasDescriptor(atlasFile, labelFile, descOpts);
                if isfield(desc,'roiNamesByAtlasOrder') && numel(desc.roiNamesByAtlasOrder) == numel(roiIDs)
                    for i = 1:numel(roiIDs)
                        labels.(sprintf('roi_%.0f', roiIDs(i))) = desc.roiNamesByAtlasOrder{i};
                    end
                end
            catch ME
                labels.warning = sprintf('Viewer ROI label lookup failed: %s', ME.message);
            end
        end
    end

    methods (Static, Access = private)

        function txt = firstMessageText(messages, fallback)
            txt = fallback;
            if isempty(messages), return; end
            if isstruct(messages)
                for i = 1:numel(messages)
                    if isfield(messages,'text') && ~isempty(messages(i).text)
                        txt = char(string(messages(i).text));
                        return;
                    end
                end
            end
        end

        function s = asChar(x)
            if isstring(x), x = char(x); end
            if iscell(x) && ~isempty(x), x = x{1}; end
            if isempty(x), s = ''; else, s = char(x); end
        end

        function tf = functionAvailable(name)
            c = exist(name,'file');
            tf = any(c == [2 3 5 6 8]) || ~isempty(which(name));
        end

        function v = optionChar(opts, field, defaultValue)
            v = defaultValue;
            if isstruct(opts) && isfield(opts,field) && ~isempty(opts.(field))
                v = NMDataIOImagePreviewTools.asChar(opts.(field));
            end
        end

        function v = optionDouble(opts, field, defaultValue)
            v = defaultValue;
            if isstruct(opts) && isfield(opts,field) && ~isempty(opts.(field))
                t = double(opts.(field));
                if isfinite(t), v = t; end
            end
        end

        function txt = base64(bytes)
            if isempty(bytes), txt = ''; return; end
            try
                enc = java.util.Base64.getEncoder();
                txt = char(enc.encodeToString(typecast(uint8(bytes(:)), 'int8')));
            catch
                txt = matlab.net.base64encode(bytes(:));
            end
        end

        function cleanupFile(fid, path)
            try fclose(fid); catch, end %#ok<CTCH>
            if exist(path,'file') == 2
                try delete(path); catch, end %#ok<CTCH>
            end
        end
    end
end

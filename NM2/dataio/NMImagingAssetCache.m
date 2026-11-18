classdef NMImagingAssetCache
% NMImagingAssetCache
% -------------------------------------------------------------------------
% Binary browser-asset packaging for imaging payloads. Scientific
% volumes remain authoritative in memory; files here are temporary transport
% artifacts scoped to one browser session.
%
% The packager accepts optional precomputed content hashes and avoids rewriting
% files whose byte size already matches the immutable content-addressed
% package identity. It performs no scientific transformation.
%
% Documentation: docs/NMImagingAssetContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function package = writeWorkspace(tmpDir, contentId, structural, atlas, profileEnabled, contentHashes, nativeFeaturePackage)
            % writeWorkspace  Publish immutable anatomy plus native feature/atlas resources.
            profileEnabled = logical(profileEnabled);
            tTotal = tic;
            NMImagingVolumeAccess.validateVolume(structural);
            tStage = tic;
            [assetDir,urlBase] = NMImagingAssetCache.assetDirectory(tmpDir);
            NMImagingAssetCache.profileLog(profileEnabled, ...
                '[nm-prof]     imaging asset directory resolution:     %.3fs (%s)\n', ...
                toc(tStage),assetDir);
            token = ['img_' regexprep(char(string(contentId)),'[^A-Za-z0-9_-]','_')];
            if numel(token) > 100, token = token(1:100); end
            pkgDir = fullfile(assetDir,token);
            packageDirectoryExisted = exist(pkgDir,'dir') == 7;
            if ~packageDirectoryExisted
                [ok,msg] = mkdir(pkgDir);
                if ~ok, error('NMImagingAssetCache:CreateDirectory','Could not create %s: %s',pkgDir,msg); end
            end
            NMImagingAssetCache.profileLog(profileEnabled, ...
                '[nm-prof]     imaging asset package directory:        existing=%d path=%s\n', ...
                double(packageDirectoryExisted),pkgDir);

            structuralHash = NMImagingAssetCache.hashOrCompute(contentHashes,'structural',structural.data,'single');
            structuralPath = fullfile(pkgDir,'structural_f32.bin');
            tStage = tic;
            structuralWritten = NMImagingAssetCache.writeBinaryIfNeeded( ...
                structuralPath,single(structural.data(:)),'single',numel(structural.data)*4);
            NMImagingAssetCache.profileLog(profileEnabled, ...
                '[nm-prof]     imaging asset structural write:         %.3fs (elements=%d written=%d bytes=%d)\n', ...
                toc(tStage),double(numel(structural.data)),double(structuralWritten),double(numel(structural.data))*4);

            nativeFeatureAssets = struct( ...
                'available',false, ...
                'gridId','', ...
                'mappingId','', ...
                'supportAsset',struct('url','','dataType','uint8','elementCount',0,'contentHash',''), ...
                'overlayAssets',struct('measureId',{},'url',{},'dataType',{},'elementCount',{},'contentHash',{}));
            if ~isempty(fieldnames(nativeFeaturePackage))
                NMImagingNativeFeatureSource.validatePackage(nativeFeaturePackage,false);
                nativeSupportPath = fullfile(pkgDir,'feature_native_support_u8.bin');
                tStage = tic;
                nativeSupportWritten = NMImagingAssetCache.writeBinaryIfNeeded( ...
                    nativeSupportPath,uint8(nativeFeaturePackage.grid.supportData(:)),'uint8', ...
                    numel(nativeFeaturePackage.grid.supportData));
                NMImagingAssetCache.profileLog(profileEnabled, ...
                    '[nm-prof]     imaging native support write:         %.3fs (elements=%d written=%d bytes=%d)\n', ...
                    toc(tStage),double(numel(nativeFeaturePackage.grid.supportData)), ...
                    double(nativeSupportWritten),double(numel(nativeFeaturePackage.grid.supportData)));
                nativeOverlayAssets = repmat(struct('measureId','','url','','dataType','float32', ...
                    'elementCount',0,'contentHash',''),1,numel(nativeFeaturePackage.overlays));
                for ii=1:numel(nativeFeaturePackage.overlays)
                    fileName = sprintf('feature_native_overlay_%03d_f32.bin',ii);
                    overlayPath = fullfile(pkgDir,fileName);
                    tOverlayWrite = tic;
                    overlayWritten = NMImagingAssetCache.writeBinaryIfNeeded( ...
                        overlayPath,single(nativeFeaturePackage.overlays(ii).data(:)),'single', ...
                        numel(nativeFeaturePackage.overlays(ii).data)*4);
                    NMImagingAssetCache.profileLog(profileEnabled, ...
                        '[nm-prof]     imaging native overlay %d/%d write: %.3fs (metric=%s elements=%d written=%d bytes=%d)\n', ...
                        ii,numel(nativeFeaturePackage.overlays),toc(tOverlayWrite), ...
                        char(string(nativeFeaturePackage.overlays(ii).measureId)), ...
                        double(numel(nativeFeaturePackage.overlays(ii).data)),double(overlayWritten), ...
                        double(numel(nativeFeaturePackage.overlays(ii).data))*4);
                    nativeOverlayAssets(ii).measureId = char(string(nativeFeaturePackage.overlays(ii).measureId));
                    nativeOverlayAssets(ii).url = sprintf('%s/%s/%s',urlBase,token,fileName);
                    nativeOverlayAssets(ii).elementCount = numel(nativeFeaturePackage.overlays(ii).data);
                    nativeOverlayAssets(ii).contentHash = char(string(nativeFeaturePackage.overlays(ii).contentHash));
                end
                nativeFeatureAssets.available = true;
                nativeFeatureAssets.gridId = char(string(nativeFeaturePackage.grid.gridId));
                nativeFeatureAssets.mappingId = char(string(nativeFeaturePackage.grid.mappingId));
                nativeFeatureAssets.supportAsset = struct( ...
                    'url',sprintf('%s/%s/feature_native_support_u8.bin',urlBase,token), ...
                    'dataType','uint8', ...
                    'elementCount',numel(nativeFeaturePackage.grid.supportData), ...
                    'contentHash',char(string(nativeFeaturePackage.grid.supportContentHash)));
                nativeFeatureAssets.overlayAssets = nativeOverlayAssets;
            end

            atlasAsset = struct('available',false,'atlasId','','url','','dataType','uint32','elementCount',0,'contentHash','');
            if ~isempty(fieldnames(atlas))
                atlasPath = fullfile(pkgDir,'atlas_u32.bin');
                tStage = tic;
                atlasWritten = NMImagingAssetCache.writeBinaryIfNeeded( ...
                    atlasPath,uint32(atlas.data(:)),'uint32',numel(atlas.data)*4);
                NMImagingAssetCache.profileLog(profileEnabled, ...
                    '[nm-prof]     imaging asset atlas write:              %.3fs (elements=%d written=%d bytes=%d)\n', ...
                    toc(tStage),double(numel(atlas.data)),double(atlasWritten),double(numel(atlas.data))*4);
                atlasAsset.available = true;
                atlasAsset.atlasId = char(string(atlas.atlasId));
                atlasAsset.url = sprintf('%s/%s/atlas_u32.bin',urlBase,token);
                atlasAsset.elementCount = numel(atlas.data);
                atlasAsset.contentHash = NMImagingAssetCache.hashOrCompute(contentHashes,'atlas',atlas.data,'uint32');
            end

            package = struct( ...
                'schema','NMImagingAssetManifest', ...
                'schemaVersion',2, ...
                'contentId',char(string(contentId)), ...
                'packageToken',token, ...
                'byteOrder','little_endian', ...
                'structuralContentHash',structuralHash, ...
                'structuralUrl',sprintf('%s/%s/structural_f32.bin',urlBase,token), ...
                'nativeFeatureAssets',nativeFeatureAssets, ...
                'atlasAsset',atlasAsset);
            NMImagingAssetCache.profileLog(profileEnabled, ...
                '[nm-prof]     imaging asset writeWorkspace TOTAL:      %.3fs (token=%s existingDir=%d)\n', ...
                toc(tTotal),token,double(packageDirectoryExisted));
        end

        function package = writeFeatureResource(tmpDir, resourceId, overlays, nativeFeaturePackage, supportData, profileEnabled, writeNativeSupport)
            % writeFeatureResource  Write only mutable feature assets for a resident imaging workspace.
            %
            % Purpose:
            %   Package feature payloads that change during a retained scientific-selection update without
            %   rewriting resident structural, atlas, or geometry resources.
            %
            % Inputs:
            %   tmpDir/session-local browser directory; deterministic resourceId; display overlay structs with
            %   measureId and data; optional NMImagingNativeFeaturePackage; optional changed display-support
            %   vector; optional flag requesting transport of changed native-grid support.
            %
            % Outputs:
            %   Content-addressed URLs and hashes for display overlays, optional changed display support,
            %   native-grid overlays, and native-grid support when its materialized identity changed.
            %
            % Authority and flow:
            %   Scientific values and support are already materialized by the owning imaging/surface service.
            %   This function is transport-only and performs no resampling, interpolation, thresholding, or inference.
            %
            % Materialization and performance:
            %   Writes only changed feature-scale arrays. It reads no source files, parses no metadata, and never
            %   writes anatomy or atlas arrays; exact duplicate native/display arrays share one immutable asset URL.
            %
            % Failure semantics:
            %   Invalid overlay/native-package schemas fail explicitly before any browser descriptor is returned.
            if nargin < 4, nativeFeaturePackage = struct(); end
            if nargin < 5, supportData = []; end
            if nargin < 6 || isempty(profileEnabled), profileEnabled = false; end
            if nargin < 7 || isempty(writeNativeSupport), writeNativeSupport = false; end
            profileEnabled = logical(profileEnabled); writeNativeSupport = logical(writeNativeSupport);
            if ~isstruct(overlays)
                error('NMImagingAssetCache:InvalidFeatureOverlays','Feature overlays must be a struct array.');
            end
            tTotal = tic;
            [assetDir,urlBase] = NMImagingAssetCache.assetDirectory(tmpDir);
            token = ['feature_' regexprep(char(string(resourceId)),'[^A-Za-z0-9_-]','_')];
            if numel(token) > 100, token = token(1:100); end
            pkgDir = fullfile(assetDir,token);
            if exist(pkgDir,'dir') ~= 7
                [ok,msg] = mkdir(pkgDir);
                if ~ok, error('NMImagingAssetCache:CreateDirectory','Could not create %s: %s',pkgDir,msg); end
            end

            supportAsset = struct('available',false,'url','','dataType','uint8','elementCount',0,'contentHash','');
            if ~isempty(supportData)
                supportBytes = uint8(supportData(:));
                supportHash = NMImagingContentIdentity.hashArray(supportBytes,'uint8');
                supportName = 'feature_support_u8.bin';
                supportPath = fullfile(pkgDir,supportName);
                written = NMImagingAssetCache.writeBinaryIfNeeded(supportPath,supportBytes,'uint8',numel(supportBytes));
                supportAsset = struct('available',true,'url',sprintf('%s/%s/%s',urlBase,token,supportName), ...
                    'dataType','uint8','elementCount',numel(supportBytes),'contentHash',supportHash);
                NMImagingAssetCache.profileLog(profileEnabled, ...
                    '[nm-prof]     imaging feature support write:          %.3fs (elements=%d written=%d)\n', ...
                    toc(tTotal),double(numel(supportBytes)),double(written));
            end

            overlayAssets = repmat(struct('measureId','','url','','dataType','float32','elementCount',0,'contentHash',''),1,numel(overlays));
            for ii=1:numel(overlays)
                if ~isfield(overlays(ii),'measureId') || isempty(overlays(ii).measureId) || ~isfield(overlays(ii),'data')
                    error('NMImagingAssetCache:InvalidFeatureOverlay','Each feature overlay requires measureId and data.');
                end
                data = single(overlays(ii).data(:));
                hash = '';
                if isfield(overlays(ii),'displayContentHash') && ~isempty(overlays(ii).displayContentHash)
                    hash = char(string(overlays(ii).displayContentHash));
                elseif isfield(overlays(ii),'contentHash') && ~isempty(overlays(ii).contentHash)
                    hash = char(string(overlays(ii).contentHash));
                else
                    hash = NMImagingContentIdentity.hashArray(data,'single');
                end
                fileName = sprintf('overlay_%03d_f32.bin',ii);
                path = fullfile(pkgDir,fileName);
                written = NMImagingAssetCache.writeBinaryIfNeeded(path,data,'single',numel(data)*4);
                overlayAssets(ii) = struct('measureId',char(string(overlays(ii).measureId)), ...
                    'url',sprintf('%s/%s/%s',urlBase,token,fileName),'dataType','float32', ...
                    'elementCount',numel(data),'contentHash',hash);
                NMImagingAssetCache.profileLog(profileEnabled, ...
                    '[nm-prof]     imaging feature overlay %d/%d write:    %.3fs (metric=%s elements=%d written=%d)\n', ...
                    ii,numel(overlays),toc(tTotal),char(string(overlays(ii).measureId)),double(numel(data)),double(written));
            end

            nativeFeatureAssets = struct('available',false,'gridId','','mappingId','', ...
                'supportAsset',struct('url','','dataType','uint8','elementCount',0,'contentHash',''), ...
                'overlayAssets',struct('measureId',{},'url',{},'dataType',{},'elementCount',{},'contentHash',{}));
            if isstruct(nativeFeaturePackage) && isscalar(nativeFeaturePackage) && ...
                    isfield(nativeFeaturePackage,'schema') && strcmp(nativeFeaturePackage.schema,'NMImagingNativeFeaturePackage')
                NMImagingNativeFeatureSource.validatePackage(nativeFeaturePackage,false);
                nativeAssets = repmat(struct('measureId','','url','','dataType','float32','elementCount',0,'contentHash',''),1,numel(nativeFeaturePackage.overlays));
                for ii=1:numel(nativeFeaturePackage.overlays)
                    meta = nativeFeaturePackage.overlays(ii);
                    displayHit = find(strcmp({overlayAssets.measureId},meta.measureId) & ...
                        strcmp({overlayAssets.contentHash},meta.contentHash) & ...
                        [overlayAssets.elementCount] == numel(meta.data),1,'first');
                    if ~isempty(displayHit)
                        nativeAssets(ii) = overlayAssets(displayHit);
                    else
                        fileName = sprintf('native_overlay_%03d_f32.bin',ii);
                        path = fullfile(pkgDir,fileName);
                        data = single(meta.data(:));
                        NMImagingAssetCache.writeBinaryIfNeeded(path,data,'single',numel(data)*4);
                        nativeAssets(ii) = struct('measureId',char(string(meta.measureId)), ...
                            'url',sprintf('%s/%s/%s',urlBase,token,fileName),'dataType','float32', ...
                            'elementCount',numel(data),'contentHash',char(string(meta.contentHash)));
                    end
                end
                nativeFeatureAssets.available = true;
                nativeFeatureAssets.gridId = char(string(nativeFeaturePackage.grid.gridId));
                nativeFeatureAssets.mappingId = char(string(nativeFeaturePackage.grid.mappingId));
                nativeSupportHash = char(string(nativeFeaturePackage.grid.supportContentHash));
                nativeSupportCount = numel(nativeFeaturePackage.grid.supportData);
                nativeSupportAsset = struct('url','','dataType','uint8', ...
                    'elementCount',nativeSupportCount,'contentHash',nativeSupportHash);
                if writeNativeSupport
                    if supportAsset.available && supportAsset.elementCount == nativeSupportCount && strcmp(supportAsset.contentHash,nativeSupportHash)
                        nativeSupportAsset = supportAsset;
                    else
                        nativeSupportName = 'native_support_u8.bin';
                        nativeSupportPath = fullfile(pkgDir,nativeSupportName);
                        nativeSupportData = uint8(nativeFeaturePackage.grid.supportData(:));
                        NMImagingAssetCache.writeBinaryIfNeeded(nativeSupportPath,nativeSupportData,'uint8',nativeSupportCount);
                        nativeSupportAsset.url = sprintf('%s/%s/%s',urlBase,token,nativeSupportName);
                    end
                end
                nativeFeatureAssets.supportAsset = nativeSupportAsset;
                nativeFeatureAssets.overlayAssets = nativeAssets;
            end
            package = struct('schema','NMImagingFeatureAssetManifest','schemaVersion',1, ...
                'resourceId',char(string(resourceId)),'packageToken',token,'supportAsset',supportAsset, ...
                'overlayAssets',overlayAssets,'nativeFeatureAssets',nativeFeatureAssets);
            NMImagingAssetCache.profileLog(profileEnabled, ...
                '[nm-prof]     imaging asset writeFeatureResource TOTAL: %.3fs (token=%s overlays=%d native=%d)\n', ...
                toc(tTotal),token,double(numel(overlayAssets)),double(nativeFeatureAssets.available));
        end

        function asset = writeIndexedLookup(tmpDir, resourceId, lookupIndex, contentHash, profileEnabled)
            % writeIndexedLookup  Write one immutable integer lookup used by compact feature transport.
            dataType = class(lookupIndex);
            switch dataType
                case 'uint8', bytesPerElement = 1;
                case 'uint16', bytesPerElement = 2;
                case 'uint32', bytesPerElement = 4;
            end
            tTotal = tic;
            [assetDir,urlBase] = NMImagingAssetCache.assetDirectory(tmpDir);
            token = ['lookup_' resourceId];
            pkgDir = fullfile(assetDir,token);
            [ok,msg] = mkdir(pkgDir);
            if ~ok, error('NMImagingAssetCache:CreateDirectory','Could not create %s: %s',pkgDir,msg); end
            fileName = ['indexed_lookup_' dataType '.bin'];
            path = fullfile(pkgDir,fileName);
            written = NMImagingAssetCache.writeBinaryIfNeeded(path,lookupIndex(:),dataType,numel(lookupIndex)*bytesPerElement);
            asset = struct('url',sprintf('%s/%s/%s',urlBase,token,fileName),'dataType',dataType, ...
                'elementCount',numel(lookupIndex),'contentHash',contentHash);
            NMImagingAssetCache.profileLog(profileEnabled, ...
                '[nm-prof]     imaging indexed lookup write:          %.3fs (elements=%d written=%d bytes=%d)\n', ...
                toc(tTotal),double(numel(lookupIndex)),double(written),double(numel(lookupIndex))*bytesPerElement);
        end

        function asset = writeAtlas(tmpDir, resourceId, atlas, profileEnabled, contentHash)
            % writeAtlas  Write one atlas-only browser transport resource.
            if nargin < 4 || isempty(profileEnabled), profileEnabled = false; end
            if nargin < 5, contentHash = ''; end
            profileEnabled = logical(profileEnabled);
            if ~isstruct(atlas) || ~isscalar(atlas) || ~isfield(atlas,'data') || isempty(atlas.data) || ...
                    ~isfield(atlas,'atlasId') || isempty(atlas.atlasId)
                error('NMImagingAssetCache:InvalidAtlas','A prepared atlas with data and atlasId is required.');
            end
            tTotal = tic;
            [assetDir,urlBase] = NMImagingAssetCache.assetDirectory(tmpDir);
            token = ['atlas_' regexprep(char(string(resourceId)),'[^A-Za-z0-9_-]','_')];
            if numel(token) > 100, token = token(1:100); end
            pkgDir = fullfile(assetDir,token);
            if exist(pkgDir,'dir') ~= 7
                [ok,msg] = mkdir(pkgDir);
                if ~ok, error('NMImagingAssetCache:CreateDirectory','Could not create %s: %s',pkgDir,msg); end
            end
            atlasPath = fullfile(pkgDir,'atlas_u32.bin');
            atlasData = uint32(atlas.data(:));
            written = NMImagingAssetCache.writeBinaryIfNeeded(atlasPath,atlasData,'uint32',numel(atlasData)*4);
            if isempty(contentHash)
                contentHash = NMImagingContentIdentity.hashArray(atlasData,'uint32');
            else
                contentHash = char(string(contentHash));
            end
            asset = struct('available',true,'atlasId',char(string(atlas.atlasId)), ...
                'url',sprintf('%s/%s/atlas_u32.bin',urlBase,token),'dataType','uint32', ...
                'elementCount',numel(atlasData),'contentHash',contentHash,'resourceId',char(string(resourceId)));
            NMImagingAssetCache.profileLog(profileEnabled, ...
                '[nm-prof]     imaging asset writeAtlas TOTAL:          %.3fs (token=%s elements=%d written=%d)\n', ...
                toc(tTotal),token,double(numel(atlasData)),double(written));
        end
    end

    methods (Static, Access = private)
        function hash = hashOrCompute(contentHashes,name,data,storageClass)
            hash = '';
            if isstruct(contentHashes) && isfield(contentHashes,name) && ~isempty(contentHashes.(name))
                hash = char(string(contentHashes.(name)));
            end
            if isempty(hash)
                hash = NMImagingContentIdentity.hashArray(data,storageClass);
            end
        end

        function profileLog(enabled, varargin)
            if ~enabled, return; end
            try
                fprintf(varargin{:});
            catch
            end
        end

        function [assetDir,urlBase] = assetDirectory(tmpDir)
            tmpDir = char(string(tmpDir));
            if isempty(tmpDir) || exist(tmpDir,'dir') ~= 7
                error('NMImagingAssetCache:InvalidSessionDirectory', ...
                    'A valid browser-session tmpDir is required.');
            end
            webDir = fileparts(tmpDir);
            if isempty(webDir) || exist(webDir,'dir') ~= 7
                error('NMImagingAssetCache:InvalidWebDirectory', ...
                    'The browser web directory could not be inferred from %s.',tmpDir);
            end
            assetDir = fullfile(webDir,'results_imaging_cache');
            if exist(assetDir,'dir') ~= 7
                [ok,msg] = mkdir(assetDir);
                if ~ok, error('NMImagingAssetCache:CreateDirectory','Could not create %s: %s',assetDir,msg); end
            end
            urlBase = 'results_imaging_cache';
        end

        function written = writeBinaryIfNeeded(path,data,precision,expectedBytes)
            written = true;
            if exist(path,'file') == 2
                info = dir(path);
                if ~isempty(info) && double(info(1).bytes) == double(expectedBytes)
                    written = false;
                    return;
                end
            end
            fid = fopen(path,'w','ieee-le');
            if fid < 0, error('NMImagingAssetCache:FileWrite','Could not open %s.',path); end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            count = fwrite(fid,data,precision);
            if count ~= numel(data)
                error('NMImagingAssetCache:FileWrite','Could not write all elements to %s.',path);
            end
        end
    end
end

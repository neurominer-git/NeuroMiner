classdef NMImagingMeshAssetCache
% NMImagingMeshAssetCache
% -------------------------------------------------------------------------
% Session-local binary transport for immutable world-millimetre meshes.
% No geometry is transformed by this class.
%
% Supports mesh packages and their mask-only extension.
% Documentation: docs/NMImaging3DMeshContract.md and
% docs/NMImagingLazySurfaceAssetsC18g5R3B.md
% -------------------------------------------------------------------------

    methods (Static)
        function package = writeMask(tmpDir, contentId, foregroundMask)
            % writeMask  Persist only the immutable anatomy-support volume.
            if nargin < 3 || isempty(foregroundMask)
                error('NMImagingMeshAssetCache:MissingForegroundMask', ...
                    'The volume-raycast package requires the cleaned anatomy foreground mask.');
            end
            foregroundMask = logical(foregroundMask);
            [assetDir,urlBase] = NMImagingMeshAssetCache.assetDirectory(tmpDir);
            token = ['mask_' regexprep(char(string(contentId)),'[^A-Za-z0-9_-]','_')];
            if numel(token) > 100, token = token(1:100); end
            packageDirectory = fullfile(assetDir,token);
            if exist(packageDirectory,'dir') ~= 7
                [ok,message] = mkdir(packageDirectory);
                if ~ok
                    error('NMImagingMeshAssetCache:CreateDirectory', ...
                        'Could not create %s: %s',packageDirectory,message);
                end
            end
            foregroundPath = fullfile(packageDirectory,'foreground_u8.bin');
            NMImagingMeshAssetCache.writeBinaryIfNeeded( ...
                foregroundPath,uint8(foregroundMask(:)),'uint8',numel(foregroundMask));
            package = struct( ...
                'schema','NMImagingMaskAssetManifest', ...
                'schemaVersion',1, ...
                'contentId',char(string(contentId)), ...
                'packageToken',token, ...
                'byteOrder','little_endian', ...
                'foregroundDataType','uint8', ...
                'foregroundDimensions',double(size(foregroundMask)), ...
                'foregroundVoxelCount',nnz(foregroundMask), ...
                'foregroundUrl',sprintf('%s/%s/foreground_u8.bin',urlBase,token));
        end

        function package = write(tmpDir, contentId, mesh, foregroundMask)
            % write  Persist one immutable mesh package in browser order.
            NMImagingMeshService.validateMesh(mesh);
            if nargin < 4 || isempty(foregroundMask)
                error('NMImagingMeshAssetCache:MissingForegroundMask', ...
                    'The cut-surface package requires the cleaned anatomy foreground mask.');
            end
            foregroundMask = logical(foregroundMask);
            [assetDir,urlBase] = NMImagingMeshAssetCache.assetDirectory(tmpDir);
            token = ['mesh_' regexprep(char(string(contentId)),'[^A-Za-z0-9_-]','_')];
            if numel(token) > 100, token = token(1:100); end
            packageDirectory = fullfile(assetDir,token);
            if exist(packageDirectory,'dir') ~= 7
                [ok,message] = mkdir(packageDirectory);
                if ~ok
                    error('NMImagingMeshAssetCache:CreateDirectory', ...
                        'Could not create %s: %s',packageDirectory,message);
                end
            end

            vertices = single(reshape(mesh.vertices.',[],1));
            normals = single(reshape(mesh.normals.',[],1));
            indices = uint32(mesh.indices(:));
            verticesPath = fullfile(packageDirectory,'vertices_f32.bin');
            normalsPath = fullfile(packageDirectory,'normals_f32.bin');
            indicesPath = fullfile(packageDirectory,'indices_u32.bin');
            foregroundPath = fullfile(packageDirectory,'foreground_u8.bin');
            NMImagingMeshAssetCache.writeBinaryIfNeeded( ...
                verticesPath,vertices,'single',numel(vertices)*4);
            NMImagingMeshAssetCache.writeBinaryIfNeeded( ...
                normalsPath,normals,'single',numel(normals)*4);
            NMImagingMeshAssetCache.writeBinaryIfNeeded( ...
                indicesPath,indices,'uint32',numel(indices)*4);
            NMImagingMeshAssetCache.writeBinaryIfNeeded( ...
                foregroundPath,uint8(foregroundMask(:)),'uint8',numel(foregroundMask));

            package = struct( ...
                'schema','NMImagingMeshAssetManifest', ...
                'schemaVersion',1, ...
                'contentId',char(string(contentId)), ...
                'packageToken',token, ...
                'byteOrder','little_endian', ...
                'verticesDataType','float32', ...
                'normalsDataType','float32', ...
                'indicesDataType','uint32', ...
                'foregroundDataType','uint8', ...
                'foregroundDimensions',double(size(foregroundMask)), ...
                'foregroundVoxelCount',nnz(foregroundMask), ...
                'verticesUrl',sprintf('%s/%s/vertices_f32.bin',urlBase,token), ...
                'normalsUrl',sprintf('%s/%s/normals_f32.bin',urlBase,token), ...
                'indicesUrl',sprintf('%s/%s/indices_u32.bin',urlBase,token), ...
                'foregroundUrl',sprintf('%s/%s/foreground_u8.bin',urlBase,token));
        end
    end

    methods (Static, Access = private)
        function [assetDir,urlBase] = assetDirectory(tmpDir)
            tmpDir = char(string(tmpDir));
            if isempty(tmpDir) || exist(tmpDir,'dir') ~= 7
                error('NMImagingMeshAssetCache:InvalidSessionDirectory', ...
                    'A valid browser-session tmpDir is required.');
            end
            webDirectory = fileparts(tmpDir);
            if isempty(webDirectory) || exist(webDirectory,'dir') ~= 7
                error('NMImagingMeshAssetCache:InvalidWebDirectory', ...
                    'Cannot infer browser web directory from %s.',tmpDir);
            end
            assetDir = fullfile(webDirectory,'results_imaging_cache');
            if exist(assetDir,'dir') ~= 7
                [ok,message] = mkdir(assetDir);
                if ~ok
                    error('NMImagingMeshAssetCache:CreateDirectory', ...
                        'Could not create %s: %s',assetDir,message);
                end
            end
            urlBase = 'results_imaging_cache';
        end

        function writeBinaryIfNeeded(path,data,precision,expectedBytes)
            if exist(path,'file') == 2
                info = dir(path);
                if ~isempty(info) && double(info(1).bytes) == double(expectedBytes)
                    return;
                end
            end
            fileId = fopen(path,'w','ieee-le');
            if fileId < 0
                error('NMImagingMeshAssetCache:FileWrite','Could not open %s.',path);
            end
            cleaner = onCleanup(@()fclose(fileId)); %#ok<NASGU>
            count = fwrite(fileId,data,precision);
            if count ~= numel(data)
                error('NMImagingMeshAssetCache:FileWrite', ...
                    'Could not write all elements to %s.',path);
            end
        end
    end
end

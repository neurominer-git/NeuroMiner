classdef NMImagingResampling
% NMImagingResampling
% -------------------------------------------------------------------------
% In-memory, renderer-independent resampling between direct one-based SPM
% grids. Continuous data use linear interpolation; labels/support use nearest
% interpolation. Coordinates outside the source grid are not clamped.
%
% Documentation: docs/NMImagingResamplingContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function [outputVolume,provenance] = resample(sourceVolume, targetReference, interpolation, outsideValue, targetRole)
            % resample  Sample one source volume on one explicit target grid.
            NMImagingVolumeAccess.validateVolume(sourceVolume);
            targetReference = NMImagingSpatialReference.fromVolume(targetReference);
            if nargin < 3 || isempty(interpolation), interpolation = 'linear'; end
            interpolation = lower(strtrim(char(string(interpolation))));
            if ~any(strcmp(interpolation,{'linear','nearest'}))
                error('NMImagingResampling:UnsupportedInterpolation', ...
                    'Interpolation must be linear or nearest, not "%s".',interpolation);
            end
            if nargin < 4 || isempty(outsideValue)
                if strcmp(interpolation,'nearest') && islogical(sourceVolume.data)
                    outsideValue = false;
                else
                    outsideValue = NaN;
                end
            end
            if ~isscalar(outsideValue) || ~(isnumeric(outsideValue) || islogical(outsideValue)) || ~isreal(outsideValue)
                error('NMImagingResampling:InvalidOutsideValue', ...
                    'outsideValue must be one real numeric or logical scalar.');
            end
            if nargin < 5 || isempty(targetRole), targetRole = sourceVolume.role; end
            targetRole = char(string(targetRole));

            sourceReference = sourceVolume.spatialReference;
            [sameGrid,~] = NMImagingSpatialReference.sameGrid(sourceReference,targetReference);
            provenance = NMImagingContractTools.resamplingProvenanceTemplate();
            provenance.sourceGridId = sourceReference.gridId;
            provenance.targetGridId = targetReference.gridId;
            provenance.interpolation = interpolation;
            provenance.outsideValue = outsideValue;
            provenance.sameGridExactCopy = sameGrid;
            provenance.targetVoxelToSourceVoxel = ...
                sourceReference.affineWorldToVoxel * targetReference.affineVoxel1ToWorld;
            provenance.sourceRole = sourceVolume.role;
            provenance.targetRole = targetRole;

            if sameGrid
                outputVolume = NMImagingVolumeAccess.withData(sourceVolume,sourceVolume.data,targetRole);
                outputVolume.provenance.source = 'NMImagingResampling.resample';
                outputVolume.provenance.interpolation = 'exact_copy';
                outputVolume.provenance.outsideValue = outsideValue;
                outputVolume.provenance.notes = 'Source and target grids were identical; no interpolation was performed.';
                return;
            end

            targetDimensions = double(targetReference.dimensions);
            outputData = repmat(double(outsideValue),targetDimensions);
            sourceData = double(sourceVolume.data);
            transform = provenance.targetVoxelToSourceVoxel;
            [targetI,targetJ] = ndgrid(1:targetDimensions(1),1:targetDimensions(2));
            planeCount = numel(targetI);
            for targetK = 1:targetDimensions(3)
                targetCoordinates = [targetI(:) targetJ(:) repmat(targetK,planeCount,1) ones(planeCount,1)];
                sourceCoordinates = (transform * targetCoordinates')';
                sampled = interpn(sourceData,sourceCoordinates(:,1),sourceCoordinates(:,2), ...
                    sourceCoordinates(:,3),interpolation,double(outsideValue));
                outputData(:,:,targetK) = reshape(sampled,targetDimensions(1),targetDimensions(2));
            end
            if strcmp(interpolation,'nearest') && islogical(sourceVolume.data) && ...
                    isfinite(double(outsideValue)) && any(double(outsideValue) == [0 1])
                outputData = logical(outputData);
            end
            outputVolume = NMImagingVolumeAccess.fromArray(outputData, ...
                targetReference.affineVoxel1ToWorld,targetRole,sourceVolume.provenance.sourceFile);
            outputVolume.provenance.source = 'NMImagingResampling.resample';
            outputVolume.provenance.resolvedFile = sourceVolume.provenance.resolvedFile;
            outputVolume.provenance.volumeIndex = sourceVolume.provenance.volumeIndex;
            outputVolume.provenance.scalingPolicy = sourceVolume.provenance.scalingPolicy;
            outputVolume.provenance.interpolation = interpolation;
            outputVolume.provenance.outsideValue = outsideValue;
            outputVolume.provenance.notes = sprintf( ...
                'Sampled from grid %s to grid %s using direct one-based SPM coordinates.', ...
                sourceReference.gridId,targetReference.gridId);
            NMImagingVolumeAccess.validateVolume(outputVolume);
        end
    end
end

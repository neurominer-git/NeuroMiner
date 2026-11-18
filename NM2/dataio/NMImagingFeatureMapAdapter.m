classdef NMImagingFeatureMapAdapter
% NMImagingFeatureMapAdapter
% -------------------------------------------------------------------------
% Pure feature-vector to voxel-volume reconstruction. The mapping
% preserves nk_WriteVol scientific order: select mask voxels in MATLAB
% column-major linear order, then exclude nonzero badcoords entries.
% Outside support is NaN and support is carried as a separate logical volume.
%
% Documentation: docs/NMImagingFeatureMapContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function featureMap = reconstruct(featureValues, featureSpaceVolume, badcoords, maskSelection)
            % reconstruct  Map one exact feature vector into its authoritative grid.
            if nargin < 3, badcoords = []; end
            if nargin < 4 || isempty(maskSelection)
                maskSelection = NMImagingContractTools.maskSelectionTemplate();
            end
            NMImagingVolumeAccess.validateVolume(featureSpaceVolume);
            maskSelection = NMImagingFeatureMapAdapter.validateMaskSelection(maskSelection);
            if ~(isnumeric(featureValues) || islogical(featureValues)) || ~isvector(featureValues)
                error('NMImagingFeatureMapAdapter:InvalidFeatureVector', ...
                    'Feature values must be one real numeric or logical vector.');
            end
            if ~isreal(featureValues)
                error('NMImagingFeatureMapAdapter:ComplexFeatureVector', ...
                    'Volume imaging can display only real-valued feature data; complex values are not supported.');
            end
            featureValues = featureValues(:);

            maskData = double(featureSpaceVolume.data);
            if maskSelection.roundBeforeComparison
                maskData = round(maskData);
            end
            selectedMask = NMImagingFeatureMapAdapter.applySelection( ...
                maskData,maskSelection.operator,maskSelection.threshold);
            selectedLinearIndices = find(selectedMask);
            beforeCount = numel(selectedLinearIndices);

            if isempty(badcoords)
                excluded = false(beforeCount,1);
            else
                if ~(isnumeric(badcoords) || islogical(badcoords)) || ~isvector(badcoords) || ...
                        ~isreal(badcoords) || any(~isfinite(double(badcoords(:))))
                    error('NMImagingFeatureMapAdapter:InvalidBadcoords', ...
                        'badcoords must be one numeric or logical vector.');
                end
                if numel(badcoords) ~= beforeCount
                    error('NMImagingFeatureMapAdapter:BadcoordsLengthMismatch', ...
                        ['badcoords contains %d entries, but the configured mask rule selected ' ...
                         '%d voxels before exclusion.'],numel(badcoords),beforeCount);
                end
                excluded = logical(badcoords(:) ~= 0);
            end
            retainedLinearIndices = selectedLinearIndices(~excluded);
            afterCount = numel(retainedLinearIndices);
            if numel(featureValues) ~= afterCount
                error('NMImagingFeatureMapAdapter:FeatureCountMismatch', ...
                    ['Feature vector contains %d values, but the authoritative mask/badcoords ' ...
                     'mapping contains %d retained voxels.'],numel(featureValues),afterCount);
            end

            dimensions = featureSpaceVolume.dimensions;
            overlayData = NaN(dimensions);
            supportData = false(dimensions);
            overlayData(retainedLinearIndices) = double(featureValues);
            supportData(retainedLinearIndices) = true;
            overlayVolume = NMImagingVolumeAccess.withData( ...
                featureSpaceVolume,overlayData,'feature_overlay_original_grid');
            overlayVolume.provenance.source = 'NMImagingFeatureMapAdapter.reconstruct';
            overlayVolume.provenance.notes = ...
                'NaN outside support; retained values follow mask linear order after badcoords exclusion.';
            supportVolume = NMImagingVolumeAccess.withData( ...
                featureSpaceVolume,supportData,'feature_support_original_grid');
            supportVolume.provenance.source = 'NMImagingFeatureMapAdapter.reconstruct';
            supportVolume.provenance.notes = ...
                'Logical support corresponding exactly to retained feature-vector positions.';

            featureMap = NMImagingContractTools.featureMapTemplate();
            featureMap.featureCount = numel(featureValues);
            featureMap.featureSpaceGridId = featureSpaceVolume.gridId;
            featureMap.maskSelection = maskSelection;
            featureMap.supportVoxelCountBeforeBadcoords = beforeCount;
            featureMap.supportVoxelCountAfterBadcoords = afterCount;
            featureMap.badcoordsCount = nnz(excluded);
            featureMap.mappingId = NMImagingContractTools.stableId( ...
                featureSpaceVolume.gridId,maskSelection.operator,maskSelection.threshold, ...
                maskSelection.roundBeforeComparison,beforeCount,afterCount, ...
                NMImagingFeatureMapAdapter.supportHash(supportData));
            featureMap.overlayVolume = overlayVolume;
            featureMap.supportVolume = supportVolume;
            NMImagingFeatureMapAdapter.validateFeatureMap(featureMap);
        end

        function validateFeatureMap(featureMap)
            % validateFeatureMap  Enforce mapping and support invariants.
            template = NMImagingContractTools.featureMapTemplate();
            if ~isstruct(featureMap) || ~isscalar(featureMap) || ...
                    ~isequal(fieldnames(featureMap),fieldnames(template))
                error('NMImagingFeatureMapAdapter:InvalidFeatureMapSchema', ...
                    'Feature map must use the fixed NMImagingFeatureMap schema.');
            end
            if ~strcmp(featureMap.schema,'NMImagingFeatureMap') || featureMap.schemaVersion ~= 1
                error('NMImagingFeatureMapAdapter:UnsupportedFeatureMapVersion', ...
                    'Only NMImagingFeatureMap schema version 1 is supported.');
            end
            NMImagingVolumeAccess.validateVolume(featureMap.overlayVolume);
            NMImagingVolumeAccess.validateVolume(featureMap.supportVolume);
            [sameGrid,~] = NMImagingSpatialReference.sameGrid( ...
                featureMap.overlayVolume.spatialReference, ...
                featureMap.supportVolume.spatialReference);
            if ~sameGrid || ~strcmp(featureMap.featureSpaceGridId,featureMap.overlayVolume.gridId)
                error('NMImagingFeatureMapAdapter:FeatureGridMismatch', ...
                    'Feature overlay, support, and featureSpaceGridId must describe one grid.');
            end
            if ~islogical(featureMap.supportVolume.data)
                error('NMImagingFeatureMapAdapter:NonLogicalSupport', ...
                    'Feature support volume data must be logical.');
            end
            supportCount = nnz(featureMap.supportVolume.data);
            if supportCount ~= featureMap.featureCount || ...
                    supportCount ~= featureMap.supportVoxelCountAfterBadcoords
                error('NMImagingFeatureMapAdapter:SupportCountMismatch', ...
                    'Feature count, retained support count, and logical support must agree exactly.');
            end
            outside = ~featureMap.supportVolume.data;
            overlayData = double(featureMap.overlayVolume.data);
            if any(~isnan(overlayData(outside)))
                error('NMImagingFeatureMapAdapter:OutsideSupportNotNaN', ...
                    'The prepared feature map is inconsistent with its valid image support. Run Preview again and verify the space-defining image or mask.');
            end
            if featureMap.supportVoxelCountBeforeBadcoords - featureMap.badcoordsCount ~= ...
                    featureMap.supportVoxelCountAfterBadcoords
                error('NMImagingFeatureMapAdapter:BadcoordsCountMismatch', ...
                    'Pre-exclusion, badcoords, and retained support counts are inconsistent.');
            end
            NMImagingFeatureMapAdapter.validateMaskSelection(featureMap.maskSelection);
        end
    end

    methods (Static, Access = private)
        function selection = validateMaskSelection(selection)
            template = NMImagingContractTools.maskSelectionTemplate();
            if ~isstruct(selection) || ~isscalar(selection) || ...
                    ~isequal(fieldnames(selection),fieldnames(template))
                error('NMImagingFeatureMapAdapter:InvalidMaskSelectionSchema', ...
                    'Mask selection must use the fixed NMImagingMaskSelection schema.');
            end
            if ~strcmp(selection.schema,'NMImagingMaskSelection') || selection.schemaVersion ~= 1
                error('NMImagingFeatureMapAdapter:UnsupportedMaskSelectionVersion', ...
                    'Only NMImagingMaskSelection schema version 1 is supported.');
            end
            selection.operator = lower(strtrim(char(string(selection.operator))));
            allowed = {'gt','ge','lt','le','eq','ne','all'};
            if ~any(strcmp(selection.operator,allowed))
                error('NMImagingFeatureMapAdapter:UnsupportedMaskOperator', ...
                    'Unsupported mask operator "%s".',selection.operator);
            end
            if ~isscalar(selection.threshold) || ~isnumeric(selection.threshold) || ...
                    ~isreal(selection.threshold) || ~isfinite(selection.threshold)
                error('NMImagingFeatureMapAdapter:InvalidMaskThreshold', ...
                    'Mask threshold must be one finite numeric scalar.');
            end
            if ~isscalar(selection.roundBeforeComparison) || ...
                    ~(islogical(selection.roundBeforeComparison) || isnumeric(selection.roundBeforeComparison)) || ...
                    ~isreal(selection.roundBeforeComparison) || ...
                    ~isfinite(double(selection.roundBeforeComparison)) || ...
                    ~any(double(selection.roundBeforeComparison) == [0 1])
                error('NMImagingFeatureMapAdapter:InvalidRoundFlag', ...
                    'roundBeforeComparison must be one logical-compatible scalar.');
            end
            selection.roundBeforeComparison = logical(selection.roundBeforeComparison);
            if ~strcmp(selection.badcoordsConvention,'nonzero_excluded') || ...
                    ~strcmp(selection.linearOrder,'matlab_column_major')
                error('NMImagingFeatureMapAdapter:UnsupportedMappingConvention', ...
                    'Feature mapping requires nonzero_excluded badcoords in MATLAB column-major mask order.');
            end
        end

        function selected = applySelection(maskData, operator, threshold)
            switch operator
                case 'gt'
                    selected = maskData > threshold;
                case 'ge'
                    selected = maskData >= threshold;
                case 'lt'
                    selected = maskData < threshold;
                case 'le'
                    selected = maskData <= threshold;
                case 'eq'
                    selected = maskData == threshold;
                case 'ne'
                    selected = maskData ~= threshold;
                case 'all'
                    selected = isfinite(maskData);
                otherwise
                    error('NMImagingFeatureMapAdapter:UnsupportedMaskOperator', ...
                        'Unsupported mask operator "%s".',operator);
            end
            selected = logical(selected & isfinite(maskData));
        end

        function id = supportHash(support)
            % supportHash  Compact deterministic FNV-1a hash of retained indices.
            retained = uint64(find(support));
            h = uint32(2166136261);
            prime = uint64(16777619);
            modulus = uint64(4294967296);
            chunkSize = 65536;
            for startIndex = 1:chunkSize:numel(retained)
                stopIndex = min(numel(retained),startIndex + chunkSize - 1);
                bytes = typecast(retained(startIndex:stopIndex),'uint8');
                for byteIndex = 1:numel(bytes)
                    h = bitxor(h,uint32(bytes(byteIndex)));
                    h = uint32(mod(uint64(h) * prime,modulus));
                end
            end
            id = lower(dec2hex(h,8));
        end
    end
end

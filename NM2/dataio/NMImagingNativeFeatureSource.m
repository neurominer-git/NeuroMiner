classdef NMImagingNativeFeatureSource
% NMImagingNativeFeatureSource
% -------------------------------------------------------------------------
% Builds and validates the authoritative native-grid feature source exposed
% to browser renderers. It preserves reconstructed feature values, logical
% support, dimensions, affine transforms, mapping identity, and provenance
% without display-grid resampling or threshold classification.
%
% Documentation: docs/NMImagingNativeFeatureSamplingContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function package = initialize(featureMap)
            % initialize  Create one native-grid package from an authoritative map.
            NMImagingFeatureMapAdapter.validateFeatureMap(featureMap);
            support = logical(featureMap.supportVolume.data);
            reference = featureMap.overlayVolume.spatialReference;
            grid = NMImagingNativeFeatureSource.gridTemplate();
            grid.coordinateConvention = reference.coordinateConvention;
            grid.dimensions = double(featureMap.overlayVolume.dimensions);
            grid.spatialReference = reference;
            grid.gridId = char(string(featureMap.overlayVolume.gridId));
            grid.mappingId = char(string(featureMap.mappingId));
            grid.worldToFeatureVoxel = double(reference.affineWorldToVoxel);
            grid.featureVoxelToWorld = double(reference.affineVoxel1ToWorld);
            grid.supportVoxelCount = nnz(support);
            grid.supportContentHash = NMImagingContentIdentity.hashArray(support,'logical');
            grid.supportData = support;
            grid.provenance = struct( ...
                'source','NMImagingFeatureMapAdapter.reconstruct', ...
                'valueAuthority','native_feature_grid', ...
                'supportAuthority','native_logical_support', ...
                'displayResamplingApplied',false, ...
                'thresholdClassificationApplied',false);
            package = NMImagingNativeFeatureSource.packageTemplate();
            package.grid = grid;
            NMImagingNativeFeatureSource.validatePackage(package);
        end

        function package = addOverlay(package, featureMap, measure, sourceVectorHash)
            % addOverlay  Append one measure on the package's authoritative grid.
            NMImagingNativeFeatureSource.validatePackage(package);
            NMImagingFeatureMapAdapter.validateFeatureMap(featureMap);
            if nargin < 3 || ~isstruct(measure) || ~isscalar(measure)
                error('NMImagingNativeFeatureSource:InvalidMeasure', ...
                    'Select exactly one feature measure for native-space display.');
            end
            if nargin < 4, sourceVectorHash = ''; end
            [sameGrid,details] = NMImagingSpatialReference.sameGrid( ...
                package.grid.spatialReference,featureMap.overlayVolume.spatialReference);
            if ~sameGrid || ~strcmp(package.grid.mappingId,char(string(featureMap.mappingId)))
                error('NMImagingNativeFeatureSource:GridOrMappingMismatch', ...
                    ['All native feature overlays must share one authoritative grid and mapping ' ...
                     '(affine error %g).'],details.affineMaximumError);
            end
            support = logical(featureMap.supportVolume.data);
            supportHash = NMImagingContentIdentity.hashArray(support,'logical');
            if ~strcmp(supportHash,package.grid.supportContentHash)
                error('NMImagingNativeFeatureSource:SupportMismatch', ...
                    'All native feature overlays must share exactly the same logical support.');
            end
            measureId = NMImagingNativeFeatureSource.textField(measure,'measureId','');
            if isempty(measureId)
                error('NMImagingNativeFeatureSource:MissingMeasureId', ...
                    'Native feature overlays require a nonempty measureId.');
            end
            if any(strcmp({package.overlays.measureId},measureId))
                error('NMImagingNativeFeatureSource:DuplicateMeasureId', ...
                    'Native feature measureId "%s" is duplicated.',measureId);
            end
            overlay = NMImagingNativeFeatureSource.overlayTemplate();
            overlay.measureId = measureId;
            overlay.label = NMImagingNativeFeatureSource.textField(measure,'label',measureId);
            overlay.sourceField = NMImagingNativeFeatureSource.textField(measure,'sourceField','');
            overlay.valuePolarity = NMImagingNativeFeatureSource.textField(measure,'valuePolarity','signed');
            overlay.valueRange = NMImagingNativeFeatureSource.displayValueRange(measure,double(featureMap.overlayVolume.valueRange));
            overlay.gridId = package.grid.gridId;
            overlay.mappingId = package.grid.mappingId;
            overlay.sourceVectorHash = char(string(sourceVectorHash));
            overlay.contentHash = NMImagingContentIdentity.hashArray(single(featureMap.overlayVolume.data),'single');
            overlay.data = single(featureMap.overlayVolume.data);
            overlay.provenance = struct( ...
                'source','NMImagingFeatureMapAdapter.reconstruct', ...
                'outsideSupportRepresentation','NaN_plus_logical_support', ...
                'displayResamplingApplied',false, ...
                'thresholdClassificationApplied',false);
            NMImagingNativeFeatureSource.validateOverlay(overlay,package.grid);
            package.overlays(end+1) = overlay;
            NMImagingNativeFeatureSource.validatePackage(package);
        end

        function package = initializePrepared(featureVolume, mappingId, supportData, supportVoxelCount, supportContentHash, provenanceSource)
            % initializePrepared  Create a native-grid package from already-authoritative resident support.
            %
            % Purpose:
            %   Allow retained scientific-payload paths to reuse an invariant support/grid materialization without
            %   rerunning feature-map reconstruction, support hashing, or feature-scale content verification.
            %
            % Inputs:
            %   featureVolume       Resident NMImagingVolume supplying only grid/spatial-reference metadata.
            %   mappingId           Established feature-mapping identity from the mounted workspace.
            %   supportData         Resident logical support on that grid.
            %   supportVoxelCount   Established support count from the authoritative mapping.
            %   supportContentHash  Established support content identity from the mounted workspace.
            %   provenanceSource    Text identifying the authoritative prepared materializer.
            %
            % Authority and flow:
            %   This constructor is for data whose grid/support identity was already validated when the resident
            %   workspace was created. It does not discover or infer support. The caller remains responsible for
            %   proving that the supplied identities equal the mounted resident contract.
            %
            % Scientific/state contract:
            %   Values are not present yet; this function cannot change feature support, mapping order or spatial
            %   reference. addPreparedOverlay is the only intended companion for payload-specific values.
            %
            % Materialization and performance:
            %   O(1) metadata checks plus array shape/class inspection. It performs no voxel scan, hash, file IO,
            %   allocation proportional to V, or source read; supportData is retained by MATLAB copy-on-write.
            %
            % Failure semantics:
            %   Missing/mismatched metadata fails explicitly. Content is not rescanned because this path accepts only
            %   identities already established by the authoritative resident materialization.
            if nargin < 6, provenanceSource = 'prepared_native_feature_grid'; end
            if ~isstruct(featureVolume) || ~isscalar(featureVolume) || ...
                    ~isfield(featureVolume,'dimensions') || ~isfield(featureVolume,'spatialReference') || ~isfield(featureVolume,'gridId')
                error('NMImagingNativeFeatureSource:InvalidPreparedVolume','The image-grid information prepared during Preview is missing. Run Preview again.');
            end
            NMImagingSpatialReference.validateReference(featureVolume.spatialReference);
            dimensions = double(featureVolume.dimensions(:)');
            supportSize = size(supportData); if numel(supportSize) < 3, supportSize(end+1:3) = 1; end
            if ~islogical(supportData) || ~isequal(double(supportSize(1:3)),dimensions)
                error('NMImagingNativeFeatureSource:InvalidPreparedSupport','The native-space feature support prepared during Preview is invalid. Run Preview again.');
            end
            if ~isscalar(supportVoxelCount) || ~isnumeric(supportVoxelCount) || ~isfinite(double(supportVoxelCount)) || double(supportVoxelCount) < 1 || ...
                    isempty(mappingId) || isempty(supportContentHash)
                error('NMImagingNativeFeatureSource:InvalidPreparedIdentity','Prepared native feature mapping/support identities are incomplete.');
            end
            reference = featureVolume.spatialReference;
            grid = NMImagingNativeFeatureSource.gridTemplate();
            grid.coordinateConvention = reference.coordinateConvention;
            grid.dimensions = dimensions;
            grid.spatialReference = reference;
            grid.gridId = char(string(featureVolume.gridId));
            grid.mappingId = char(string(mappingId));
            grid.worldToFeatureVoxel = double(reference.affineWorldToVoxel);
            grid.featureVoxelToWorld = double(reference.affineVoxel1ToWorld);
            grid.supportVoxelCount = double(supportVoxelCount);
            grid.supportContentHash = char(string(supportContentHash));
            grid.supportData = supportData;
            grid.provenance = struct( ...
                'source',char(string(provenanceSource)), ...
                'valueAuthority','native_feature_grid', ...
                'supportAuthority','resident_authoritative_support', ...
                'displayResamplingApplied',false, ...
                'thresholdClassificationApplied',false);
            package = NMImagingNativeFeatureSource.packageTemplate();
            package.grid = grid;
            NMImagingNativeFeatureSource.validatePackage(package,false);
        end

        function package = addPreparedOverlay(package, data, measure, sourceVectorHash, contentHash, valueRange, provenanceSource)
            % addPreparedOverlay  Append one already-materialized overlay without rescanning immutable voxel content.
            %
            % Purpose:
            %   Attach payload-specific dense values produced deterministically from a resident authoritative mapping.
            %
            % Inputs:
            %   package          Prepared native-grid package with invariant grid/support.
            %   data             Single-precision dense values on package.grid; NaN outside support by producer contract.
            %   measure          Canonical measure descriptor.
            %   sourceVectorHash Compact identity of the source scientific vector.
            %   contentHash      Provenance-derived identity of this deterministic dense representation.
            %   valueRange       O(R)-derived finite range of the source values.
            %   provenanceSource Producing materializer identity.
            %
            % Authority and flow:
            %   The caller must construct data from the same authoritative mapping represented by package.grid.
            %   This function records that materialization; it does not infer support or reinterpret scientific values.
            %
            % Materialization and performance:
            %   O(1) schema/dimension checks and metadata construction; no V-sized copies, hashes, support scans, or
            %   outside-support verification are repeated. The single dense input is retained by copy-on-write.
            %
            % Failure semantics:
            %   Schema, measure, dimension, identity or storage disagreement fails explicitly. The prepared overlay
            %   records authoritative_derivation identity because its resource identity is defined by the resident
            %   mapping plus compact source-vector identity rather than by rescanning the derived V-sized bytes.
            if nargin < 7, provenanceSource = 'prepared_native_feature_overlay'; end
            NMImagingNativeFeatureSource.validatePackage(package,false);
            if ~isstruct(measure) || ~isscalar(measure)
                error('NMImagingNativeFeatureSource:InvalidMeasure','Select exactly one feature measure for native-space display.');
            end
            measureId = NMImagingNativeFeatureSource.textField(measure,'measureId','');
            if isempty(measureId) || any(strcmp({package.overlays.measureId},measureId))
                error('NMImagingNativeFeatureSource:PreparedMeasureIdentity','Prepared native feature measure ID is missing or duplicated.');
            end
            dataSize = size(data); if numel(dataSize) < 3, dataSize(end+1:3) = 1; end
            if ~isa(data,'single') || ~isequal(double(dataSize(1:3)),double(package.grid.dimensions))
                error('NMImagingNativeFeatureSource:InvalidPreparedOverlayData','The native-space feature data prepared during Preview are invalid. Run Preview again.');
            end
            if isempty(contentHash) || ~isnumeric(valueRange) || numel(valueRange) ~= 2
                error('NMImagingNativeFeatureSource:InvalidPreparedOverlayIdentity','Prepared native overlay content identity or value range is invalid.');
            end
            overlay = NMImagingNativeFeatureSource.overlayTemplate();
            overlay.measureId = measureId;
            overlay.label = NMImagingNativeFeatureSource.textField(measure,'label',measureId);
            overlay.sourceField = NMImagingNativeFeatureSource.textField(measure,'sourceField','');
            overlay.valuePolarity = NMImagingNativeFeatureSource.textField(measure,'valuePolarity','signed');
            overlay.valueRange = NMImagingNativeFeatureSource.displayValueRange(measure,double(valueRange(:)'));
            overlay.gridId = package.grid.gridId;
            overlay.mappingId = package.grid.mappingId;
            overlay.sourceVectorHash = char(string(sourceVectorHash));
            overlay.contentHash = char(string(contentHash));
            overlay.data = data;
            overlay.provenance = struct( ...
                'source',char(string(provenanceSource)), ...
                'outsideSupportRepresentation','NaN_plus_logical_support', ...
                'displayResamplingApplied',false, ...
                'thresholdClassificationApplied',false, ...
                'contentIdentityMode','authoritative_derivation');
            NMImagingNativeFeatureSource.validateOverlay(overlay,package.grid,false);
            package.overlays(end+1) = overlay;
            NMImagingNativeFeatureSource.validatePackage(package,false);
        end

        function payload = browserPayload(package, assets)
            % browserPayload  Convert an in-memory package into a transport descriptor.
            NMImagingNativeFeatureSource.validatePackage(package,false);
            if nargin < 2 || ~isstruct(assets) || ~isscalar(assets) || ...
                    ~isfield(assets,'available') || ~logical(assets.available)
                error('NMImagingNativeFeatureSource:MissingAssets', ...
                    'Native-space display data are unavailable. Run Preview before opening the viewer.');
            end
            if ~isfield(assets,'supportAsset') || ~isfield(assets,'overlayAssets')
                error('NMImagingNativeFeatureSource:InvalidAssets', ...
                    'Native feature assets must contain supportAsset and overlayAssets.');
            end
            if ~isfield(assets,'gridId') || ~strcmp(char(string(assets.gridId)),package.grid.gridId) || ...
                    ~isfield(assets,'mappingId') || ~strcmp(char(string(assets.mappingId)),package.grid.mappingId)
                error('NMImagingNativeFeatureSource:AssetIdentityMismatch', ...
                    'Native feature asset grid and mapping identities must match the package.');
            end
            if double(assets.supportAsset.elementCount) ~= numel(package.grid.supportData) || ...
                    ~strcmp(char(string(assets.supportAsset.contentHash)),package.grid.supportContentHash)
                error('NMImagingNativeFeatureSource:AssetSupportMismatch', ...
                    'Native feature support asset metadata do not match the package.');
            end
            payload = NMImagingNativeFeatureSource.browserPayloadTemplate();
            payload.available = true;
            payload.coordinateConvention = package.grid.coordinateConvention;
            payload.dimensions = package.grid.dimensions;
            payload.spatialReference = package.grid.spatialReference;
            payload.gridId = package.grid.gridId;
            payload.mappingId = package.grid.mappingId;
            payload.worldToFeatureVoxel = package.grid.worldToFeatureVoxel;
            payload.featureVoxelToWorld = package.grid.featureVoxelToWorld;
            payload.supportVoxelCount = package.grid.supportVoxelCount;
            payload.support = struct( ...
                'url',char(string(assets.supportAsset.url)), ...
                'dataType','uint8', ...
                'elementCount',double(assets.supportAsset.elementCount), ...
                'contentHash',package.grid.supportContentHash);
            browserOverlays = repmat(NMImagingNativeFeatureSource.browserOverlayTemplate(),1,numel(package.overlays));
            for ii=1:numel(package.overlays)
                hit = find(strcmp({assets.overlayAssets.measureId},package.overlays(ii).measureId),1,'first');
                if isempty(hit)
                    error('NMImagingNativeFeatureSource:MissingOverlayAsset', ...
                        'No native feature asset was provided for measure "%s".',package.overlays(ii).measureId);
                end
                if double(assets.overlayAssets(hit).elementCount) ~= numel(package.overlays(ii).data) || ...
                        ~strcmp(char(string(assets.overlayAssets(hit).contentHash)),package.overlays(ii).contentHash)
                    error('NMImagingNativeFeatureSource:OverlayAssetMismatch', ...
                        'Native feature asset metadata do not match measure "%s".',package.overlays(ii).measureId);
                end
                browserOverlays(ii).measureId = package.overlays(ii).measureId;
                browserOverlays(ii).label = package.overlays(ii).label;
                browserOverlays(ii).sourceField = package.overlays(ii).sourceField;
                browserOverlays(ii).valuePolarity = package.overlays(ii).valuePolarity;
                browserOverlays(ii).valueRange = package.overlays(ii).valueRange;
                browserOverlays(ii).url = char(string(assets.overlayAssets(hit).url));
                browserOverlays(ii).dataType = 'float32';
                browserOverlays(ii).elementCount = double(assets.overlayAssets(hit).elementCount);
                browserOverlays(ii).contentHash = package.overlays(ii).contentHash;
                browserOverlays(ii).sourceVectorHash = package.overlays(ii).sourceVectorHash;
            end
            payload.overlays = browserOverlays;
            payload.samplingSemantics = struct( ...
                'sourceAuthority','native_feature_grid', ...
                'thresholdEvaluation','after_native_grid_sampling', ...
                'outsideSupport','invalid_transparent', ...
                'displayAlignmentRole','legacy_display_only', ...
                'valueInterpolation','renderer_selected_without_pre_resampling', ...
                'supportInterpolation','renderer_selected_without_pre_resampling');
        end

        function payload = browserIndexedPayload(package, lookupAsset, overlays)
            % browserIndexedPayload  Describe one compact indexed native-grid feature source.
            %
            % The authoritative voxel-to-value lookup is transported once while per-measure values remain compact.
            % Browser hydration reconstructs the same dense native-grid arrays consumed by existing renderers.
            NMImagingNativeFeatureSource.validatePackage(package,false);
            if lookupAsset.elementCount ~= numel(package.grid.supportData)
                error('NMImagingNativeFeatureSource:IndexedLookupDimension', ...
                    'Indexed native feature lookup length must equal the native-grid voxel count.');
            end
            valueCount = numel(overlays(1).values);
            payload = NMImagingNativeFeatureSource.browserPayloadTemplate();
            payload.available = true;
            payload.storageEncoding = 'indexed_lookup_v1';
            payload.coordinateConvention = package.grid.coordinateConvention;
            payload.dimensions = package.grid.dimensions;
            payload.spatialReference = package.grid.spatialReference;
            payload.gridId = package.grid.gridId;
            payload.mappingId = package.grid.mappingId;
            payload.worldToFeatureVoxel = package.grid.worldToFeatureVoxel;
            payload.featureVoxelToWorld = package.grid.featureVoxelToWorld;
            payload.supportVoxelCount = package.grid.supportVoxelCount;
            payload.support = struct('url','','dataType','uint8', ...
                'elementCount',numel(package.grid.supportData),'contentHash',package.grid.supportContentHash);
            payload.indexedLookup = struct('url',lookupAsset.url,'dataType',lookupAsset.dataType, ...
                'elementCount',double(lookupAsset.elementCount),'contentHash',lookupAsset.contentHash, ...
                'unsupportedIndex',1,'firstValueIndex',2,'valueCount',double(valueCount));
            browserOverlays = repmat(NMImagingNativeFeatureSource.browserOverlayTemplate(),1,numel(overlays));
            for ii=1:numel(overlays)
                if numel(overlays(ii).values) ~= valueCount
                    error('NMImagingNativeFeatureSource:IndexedOverlayDimension', ...
                        'Indexed native feature overlays must share one compact value-axis length.');
                end
                browserOverlays(ii).measureId = overlays(ii).measureId;
                browserOverlays(ii).label = overlays(ii).label;
                browserOverlays(ii).sourceField = overlays(ii).sourceField;
                browserOverlays(ii).valuePolarity = overlays(ii).valuePolarity;
                browserOverlays(ii).valueRange = overlays(ii).valueRange;
                browserOverlays(ii).elementCount = numel(package.grid.supportData);
                browserOverlays(ii).contentHash = overlays(ii).contentHash;
                browserOverlays(ii).sourceVectorHash = overlays(ii).sourceVectorHash;
                compactValues = double(overlays(ii).values(:)');
                if any(isinf(compactValues))
                    error('NMImagingNativeFeatureSource:IndexedOverlayInfinite', ...
                        'Indexed native feature values contain infinity and cannot be displayed without changing their meaning.');
                end
                browserOverlays(ii).compactFinite = isfinite(compactValues);
                compactValues(~browserOverlays(ii).compactFinite) = 0;
                browserOverlays(ii).compactValues = compactValues;
            end
            payload.overlays = browserOverlays;
        end

        function validatePackage(package, verifyContent)
            % validatePackage  Enforce native package invariants, with optional feature-scale content verification.
            %
            % verifyContent defaults to true and is intended for authority/test boundaries. Internal transport
            % consumers may pass false only after an authoritative constructor has established array content/identity;
            % that mode validates schemas, dimensions and compact identities without rescanning V-sized arrays.
            if nargin < 2 || isempty(verifyContent), verifyContent = true; end
            verifyContent = logical(verifyContent);
            template = NMImagingNativeFeatureSource.packageTemplate();
            if ~isstruct(package) || ~isscalar(package) || ...
                    ~isequal(fieldnames(package),fieldnames(template))
                error('NMImagingNativeFeatureSource:InvalidPackageSchema', ...
                    'Native feature package must use the fixed schema.');
            end
            if ~strcmp(package.schema,'NMImagingNativeFeaturePackage') || ...
                    package.schemaVersion ~= 1 || ~strcmp(package.contractVersion,'C18d4.7a')
                error('NMImagingNativeFeatureSource:UnsupportedPackageVersion', ...
                    'The native feature package version is not supported by this viewer.');
            end
            NMImagingNativeFeatureSource.validateGrid(package.grid,verifyContent);
            for ii=1:numel(package.overlays)
                NMImagingNativeFeatureSource.validateOverlay(package.overlays(ii),package.grid,verifyContent);
            end
            ids = {package.overlays.measureId};
            if numel(unique(ids)) ~= numel(ids)
                error('NMImagingNativeFeatureSource:DuplicateMeasureId', ...
                    'Native feature package measure IDs must be unique.');
            end
        end

        function template = browserPayloadTemplate()
            template = struct( ...
                'schema','NMImagingNativeFeatureSamplingPayload', ...
                'schemaVersion',1, ...
                'contractVersion','C18d4.7a', ...
                'available',false, ...
                'coordinateConvention','spm_one_based_direct', ...
                'dimensions',[0 0 0], ...
                'spatialReference',NMImagingContractTools.spatialReferenceTemplate(), ...
                'gridId','', ...
                'mappingId','', ...
                'worldToFeatureVoxel',eye(4), ...
                'featureVoxelToWorld',eye(4), ...
                'supportVoxelCount',0, ...
                'storageEncoding','dense_grid_v1', ...
                'support',struct('url','','dataType','uint8','elementCount',0,'contentHash',''), ...
                'indexedLookup',struct('url','','dataType','uint8','elementCount',0,'contentHash','', ...
                    'unsupportedIndex',1,'firstValueIndex',2,'valueCount',0), ...
                'overlays',NMImagingNativeFeatureSource.browserOverlayTemplate([]), ...
                'samplingSemantics',struct( ...
                    'sourceAuthority','native_feature_grid', ...
                    'thresholdEvaluation','after_native_grid_sampling', ...
                    'outsideSupport','invalid_transparent', ...
                    'displayAlignmentRole','legacy_display_only', ...
                    'valueInterpolation','renderer_selected_without_pre_resampling', ...
                    'supportInterpolation','renderer_selected_without_pre_resampling'));
        end
    end

    methods (Static, Access = private)
        function validateGrid(grid,verifyContent)
            if nargin < 2, verifyContent = true; end
            template = NMImagingNativeFeatureSource.gridTemplate();
            if ~isstruct(grid) || ~isscalar(grid) || ...
                    ~isequal(fieldnames(grid),fieldnames(template))
                error('NMImagingNativeFeatureSource:InvalidGridSchema', ...
                    'Native feature grid must use the fixed schema.');
            end
            if ~strcmp(grid.schema,'NMImagingNativeFeatureGrid') || ...
                    grid.schemaVersion ~= 1 || ~strcmp(grid.contractVersion,'C18d4.7a')
                error('NMImagingNativeFeatureSource:UnsupportedGridVersion', ...
                    'The native feature grid version is not supported by this viewer.');
            end
            NMImagingSpatialReference.validateReference(grid.spatialReference);
            if ~strcmp(grid.coordinateConvention,'spm_one_based_direct') || ...
                    ~strcmp(grid.coordinateConvention,grid.spatialReference.coordinateConvention)
                error('NMImagingNativeFeatureSource:CoordinateConventionMismatch', ...
                    'Native feature grid must use spm_one_based_direct coordinates.');
            end
            if ~isequal(double(grid.dimensions),double(grid.spatialReference.dimensions)) || ...
                    ~strcmp(grid.gridId,grid.spatialReference.gridId)
                error('NMImagingNativeFeatureSource:GridIdentityMismatch', ...
                    'Native feature dimensions, spatial reference, and gridId must agree.');
            end
            if isempty(grid.mappingId)
                error('NMImagingNativeFeatureSource:MissingMappingId', ...
                    'Native feature grid requires a nonempty mappingId.');
            end
            supportSize = size(grid.supportData);
            if numel(supportSize) < 3, supportSize(end+1:3) = 1; end
            if ~islogical(grid.supportData) || ...
                    ~isequal(double(supportSize(1:3)),double(grid.dimensions))
                error('NMImagingNativeFeatureSource:InvalidSupport', ...
                    'Native feature support must be a logical array on the native grid.');
            end
            if isempty(grid.supportContentHash)
                error('NMImagingNativeFeatureSource:SupportIdentityMismatch', ...
                    'Native feature support content identity is missing.');
            end
            if verifyContent
                if nnz(grid.supportData) ~= double(grid.supportVoxelCount)
                    error('NMImagingNativeFeatureSource:SupportCountMismatch', ...
                        'Native feature support count does not match the logical support array.');
                end
                actualHash = NMImagingContentIdentity.hashArray(grid.supportData,'logical');
                if ~strcmp(actualHash,grid.supportContentHash)
                    error('NMImagingNativeFeatureSource:SupportIdentityMismatch', ...
                        'Native feature support content identity is inconsistent.');
                end
            end
            if max(abs(double(grid.worldToFeatureVoxel(:))-double(grid.spatialReference.affineWorldToVoxel(:)))) > 1e-10 || ...
                    max(abs(double(grid.featureVoxelToWorld(:))-double(grid.spatialReference.affineVoxel1ToWorld(:)))) > 1e-10
                error('NMImagingNativeFeatureSource:TransformMismatch', ...
                    'Explicit native feature transforms must match the spatial-reference affine pair.');
            end
        end

        function validateOverlay(overlay,grid,verifyContent)
            if nargin < 3, verifyContent = true; end
            template = NMImagingNativeFeatureSource.overlayTemplate();
            if ~isstruct(overlay) || ~isscalar(overlay) || ...
                    ~isequal(fieldnames(overlay),fieldnames(template))
                error('NMImagingNativeFeatureSource:InvalidOverlaySchema', ...
                    'Native feature overlay must use the fixed schema.');
            end
            if ~strcmp(overlay.schema,'NMImagingNativeFeatureOverlay') || ...
                    overlay.schemaVersion ~= 1 || ~strcmp(overlay.contractVersion,'C18d4.7a')
                error('NMImagingNativeFeatureSource:UnsupportedOverlayVersion', ...
                    'The native feature overlay version is not supported by this viewer.');
            end
            if isempty(overlay.measureId) || ~strcmp(overlay.gridId,grid.gridId) || ...
                    ~strcmp(overlay.mappingId,grid.mappingId)
                error('NMImagingNativeFeatureSource:OverlayIdentityMismatch', ...
                    'Native feature overlay identity must match its grid and mapping.');
            end
            overlaySize = size(overlay.data);
            if numel(overlaySize) < 3, overlaySize(end+1:3) = 1; end
            if ~isa(overlay.data,'single') || ...
                    ~isequal(double(overlaySize(1:3)),double(grid.dimensions))
                error('NMImagingNativeFeatureSource:InvalidOverlayData', ...
                    'Native feature overlay data must be single precision on the native grid.');
            end
            if isempty(overlay.contentHash)
                error('NMImagingNativeFeatureSource:OverlayIdentityMismatch', ...
                    'Native feature overlay content identity is missing.');
            end
            if verifyContent
                outside = ~grid.supportData;
                if any(~isnan(double(overlay.data(outside))))
                    error('NMImagingNativeFeatureSource:OutsideSupportNotNaN', ...
                        'Native feature overlay must retain NaN outside logical support.');
                end
                if ~isstruct(overlay.provenance) || ~isscalar(overlay.provenance)
                    error('NMImagingNativeFeatureSource:InvalidOverlayProvenance', ...
                        'The saved native-space display information is invalid. Run Preview again.');
                end
                identityMode = '';
                if isfield(overlay.provenance,'contentIdentityMode') && ~isempty(overlay.provenance.contentIdentityMode)
                    identityMode = char(string(overlay.provenance.contentIdentityMode));
                end
                if ~strcmp(identityMode,'authoritative_derivation')
                    actualHash = NMImagingContentIdentity.hashArray(overlay.data,'single');
                    if ~strcmp(actualHash,overlay.contentHash)
                        error('NMImagingNativeFeatureSource:OverlayIdentityMismatch', ...
                            'Native feature overlay content identity is inconsistent.');
                    end
                end
            end
        end

        function template = packageTemplate()
            template = struct( ...
                'schema','NMImagingNativeFeaturePackage', ...
                'schemaVersion',1, ...
                'contractVersion','C18d4.7a', ...
                'grid',NMImagingNativeFeatureSource.gridTemplate(), ...
                'overlays',NMImagingNativeFeatureSource.overlayTemplate([]));
        end

        function template = gridTemplate()
            template = struct( ...
                'schema','NMImagingNativeFeatureGrid', ...
                'schemaVersion',1, ...
                'contractVersion','C18d4.7a', ...
                'coordinateConvention','spm_one_based_direct', ...
                'dimensions',[0 0 0], ...
                'spatialReference',NMImagingContractTools.spatialReferenceTemplate(), ...
                'gridId','', ...
                'mappingId','', ...
                'worldToFeatureVoxel',eye(4), ...
                'featureVoxelToWorld',eye(4), ...
                'supportVoxelCount',0, ...
                'supportContentHash','', ...
                'supportData',false([]), ...
                'provenance',struct( ...
                    'source','', ...
                    'valueAuthority','native_feature_grid', ...
                    'supportAuthority','native_logical_support', ...
                    'displayResamplingApplied',false, ...
                    'thresholdClassificationApplied',false));
        end

        function template = overlayTemplate(varargin)
            tmpl = struct( ...
                'schema','NMImagingNativeFeatureOverlay', ...
                'schemaVersion',1, ...
                'contractVersion','C18d4.7a', ...
                'measureId','', ...
                'label','', ...
                'sourceField','', ...
                'valuePolarity','signed', ...
                'valueRange',[NaN NaN], ...
                'gridId','', ...
                'mappingId','', ...
                'sourceVectorHash','', ...
                'contentHash','', ...
                'data',single([]), ...
                'provenance',struct( ...
                    'source','', ...
                    'outsideSupportRepresentation','NaN_plus_logical_support', ...
                    'displayResamplingApplied',false, ...
                    'thresholdClassificationApplied',false));
            if nargin > 0 && isequal(varargin{1},[]), template=tmpl([]); else, template=tmpl; end
        end

        function template = browserOverlayTemplate(varargin)
            tmpl = struct( ...
                'measureId','', ...
                'label','', ...
                'sourceField','', ...
                'valuePolarity','signed', ...
                'valueRange',[NaN NaN], ...
                'url','', ...
                'dataType','float32', ...
                'elementCount',0, ...
                'contentHash','', ...
                'sourceVectorHash','', ...
                'compactValues',[], ...
                'compactFinite',[]);
            if nargin > 0 && isequal(varargin{1},[]), template=tmpl([]); else, template=tmpl; end
        end

        function range = displayValueRange(measure,fallback)
            % displayValueRange  Apply an explicitly registered presentation domain without rescanning dense feature data.
            range=double(fallback(:)');
            if isstruct(measure)&&isfield(measure,'displayValueRange')&&~isempty(measure.displayValueRange)
                candidate=double(measure.displayValueRange(:)');
                if numel(candidate)~=2||any(~isfinite(candidate))||candidate(2)<candidate(1)
                    error('NMImagingNativeFeatureSource:InvalidDisplayRange','Measure displayValueRange must contain two finite ordered values.');
                end
                range=candidate;
            end
        end

        function value = textField(s,name,defaultValue)
            value = defaultValue;
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                raw = s.(name);
                if ischar(raw) || (isstring(raw) && isscalar(raw))
                    value = char(string(raw));
                end
            end
        end
    end
end

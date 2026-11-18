classdef NMImagingSpatialReference
% NMImagingSpatialReference
% -------------------------------------------------------------------------
% Renderer-independent spatial-reference and coordinate operations for imaging.
% The authoritative convention is direct one-based SPM voxel coordinates:
% world_mm = V.mat * [i; j; k; 1]. Coordinates are never clamped.
%
% Documentation: docs/NMImagingSpatialReferenceContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function reference = create(dimensions, affineVoxel1ToWorld, sourceLabel)
            % create  Build and validate one fixed spatial-reference contract.
            if nargin < 3, sourceLabel = ''; end
            dimensions = NMImagingSpatialReference.normalizeDimensions(dimensions);
            affineVoxel1ToWorld = NMImagingSpatialReference.normalizeAffine(affineVoxel1ToWorld);

            linearPart = affineVoxel1ToWorld(1:3,1:3);
            voxelSizeMm = sqrt(sum(linearPart.^2,1));
            if any(~isfinite(voxelSizeMm)) || any(voxelSizeMm <= 0)
                error('NMImagingSpatialReference:InvalidVoxelSize', ...
                    'The affine must define three finite nonzero voxel axes.');
            end
            axisUnitVectors = linearPart ./ voxelSizeMm;
            gram = axisUnitVectors' * axisUnitVectors;
            orthogonalityError = max(abs(gram(~eye(3))));
            cardinalAlignmentError = max(abs(1 - max(abs(axisUnitVectors),[],1)));
            determinant = det(linearPart);
            if determinant > 0
                handedness = 'right_handed';
            elseif determinant < 0
                handedness = 'left_handed';
            else
                error('NMImagingSpatialReference:SingularAffine', ...
                    'The spatial affine has a zero determinant.');
            end

            reference = NMImagingContractTools.spatialReferenceTemplate();
            reference.dimensions = dimensions;
            reference.affineVoxel1ToWorld = affineVoxel1ToWorld;
            reference.affineWorldToVoxel = inv(affineVoxel1ToWorld);
            reference.voxelSizeMm = voxelSizeMm;
            reference.axisUnitVectors = axisUnitVectors;
            reference.determinant = determinant;
            reference.handedness = handedness;
            reference.orthogonalityError = orthogonalityError;
            reference.cardinalAlignmentError = cardinalAlignmentError;
            reference.isOblique = orthogonalityError > 1e-6 || cardinalAlignmentError > 1e-6;
            reference.sourceLabel = char(string(sourceLabel));
            reference.gridId = NMImagingContractTools.stableId( ...
                'NMImagingSpatialReference',reference.schemaVersion,dimensions,affineVoxel1ToWorld);
            NMImagingSpatialReference.validateReference(reference);
        end

        function reference = fromVolume(volume)
            % fromVolume  Resolve a spatial reference from an NM or SPM volume.
            if ~isstruct(volume) || ~isscalar(volume)
                error('NMImagingSpatialReference:InvalidVolume', ...
                    'Volume input must be a scalar struct.');
            end
            if isfield(volume,'schema') && strcmp(volume.schema,'NMImagingSpatialReference')
                % A spatial-reference contract may return through JSON/browser
                % transport with one-dimensional numeric vectors decoded as
                % columns. Validate the transported scientific values first,
                % then restore the canonical MATLAB row-vector representation
                % required by downstream grid allocation and coordinate code.
                reference = volume;
                NMImagingSpatialReference.validateReference(reference);
                reference.dimensions = NMImagingSpatialReference.normalizeDimensions(reference.dimensions);
                reference.voxelSizeMm = double(reference.voxelSizeMm(:)');
                NMImagingSpatialReference.validateReference(reference);
                return;
            end
            if isfield(volume,'spatialReference') && isstruct(volume.spatialReference)
                reference = volume.spatialReference;
                NMImagingSpatialReference.validateReference(reference);
                return;
            end
            if isfield(volume,'dimensions')
                dimensions = volume.dimensions;
            elseif isfield(volume,'dim')
                dimensions = volume.dim;
            else
                error('NMImagingSpatialReference:MissingDimensions', ...
                    'Volume input contains neither dimensions nor dim.');
            end
            if isfield(volume,'affineVoxel1ToWorld')
                affine = volume.affineVoxel1ToWorld;
            elseif isfield(volume,'mat')
                affine = volume.mat;
            else
                error('NMImagingSpatialReference:MissingAffine', ...
                    'Volume input contains neither affineVoxel1ToWorld nor mat.');
            end
            sourceLabel = '';
            if isfield(volume,'role'), sourceLabel = volume.role; end
            if isfield(volume,'fname') && ~isempty(volume.fname), sourceLabel = volume.fname; end
            reference = NMImagingSpatialReference.create(dimensions,affine,sourceLabel);
        end

        function worldMm = voxelToWorld(reference, voxelCoordinates)
            % voxelToWorld  Transform N-by-3 direct one-based voxel coordinates.
            NMImagingSpatialReference.validateReference(reference);
            voxelCoordinates = NMImagingSpatialReference.normalizeCoordinates(voxelCoordinates,'voxel');
            homogeneous = [double(voxelCoordinates) ones(size(voxelCoordinates,1),1)];
            mapped = (reference.affineVoxel1ToWorld * homogeneous')';
            worldMm = mapped(:,1:3);
        end

        function voxelCoordinates = worldToVoxel(reference, worldMm)
            % worldToVoxel  Transform N-by-3 world-mm coordinates without rounding.
            NMImagingSpatialReference.validateReference(reference);
            worldMm = NMImagingSpatialReference.normalizeCoordinates(worldMm,'world');
            homogeneous = [double(worldMm) ones(size(worldMm,1),1)];
            mapped = (reference.affineWorldToVoxel * homogeneous')';
            voxelCoordinates = mapped(:,1:3);
        end

        function inside = containsVoxel(reference, voxelCoordinates, tolerance)
            % containsVoxel  Test direct voxel coordinates without clamping.
            if nargin < 3 || isempty(tolerance), tolerance = 0; end
            if ~isscalar(tolerance) || ~isnumeric(tolerance) || ~isfinite(tolerance) || tolerance < 0
                error('NMImagingSpatialReference:InvalidTolerance', ...
                    'Voxel-bound tolerance must be one finite nonnegative scalar.');
            end
            NMImagingSpatialReference.validateReference(reference);
            voxelCoordinates = NMImagingSpatialReference.normalizeCoordinates(voxelCoordinates,'voxel');
            lo = 1 - double(tolerance);
            hi = double(reference.dimensions) + double(tolerance);
            inside = all(isfinite(voxelCoordinates),2) & ...
                all(voxelCoordinates >= lo,2) & all(voxelCoordinates <= hi,2);
        end

        function [same, details] = sameGrid(firstReference, secondReference, tolerance)
            % sameGrid  Compare dimensions and affines under an explicit tolerance.
            if nargin < 3 || isempty(tolerance), tolerance = 1e-8; end
            if ~isscalar(tolerance) || ~isnumeric(tolerance) || ~isfinite(tolerance) || tolerance < 0
                error('NMImagingSpatialReference:InvalidTolerance', ...
                    'Grid-comparison tolerance must be one finite nonnegative scalar.');
            end
            firstReference = NMImagingSpatialReference.fromVolume(firstReference);
            secondReference = NMImagingSpatialReference.fromVolume(secondReference);
            dimensionsEqual = isequal(double(firstReference.dimensions),double(secondReference.dimensions));
            affineMaximumError = max(abs(firstReference.affineVoxel1ToWorld(:) - ...
                secondReference.affineVoxel1ToWorld(:)));
            same = dimensionsEqual && affineMaximumError <= tolerance;
            details = struct( ...
                'dimensionsEqual',dimensionsEqual, ...
                'affineMaximumError',affineMaximumError, ...
                'tolerance',double(tolerance), ...
                'firstGridId',firstReference.gridId, ...
                'secondGridId',secondReference.gridId);
        end

        function validateReference(reference)
            % validateReference  Enforce the fixed imaging spatial schema.
            template = NMImagingContractTools.spatialReferenceTemplate();
            if ~isstruct(reference) || ~isscalar(reference) || ...
                    ~isequal(fieldnames(reference),fieldnames(template))
                error('NMImagingSpatialReference:InvalidReferenceSchema', ...
                    'Spatial reference must use the fixed NMImagingSpatialReference schema.');
            end
            if ~strcmp(reference.schema,'NMImagingSpatialReference') || reference.schemaVersion ~= 1
                error('NMImagingSpatialReference:UnsupportedReferenceVersion', ...
                    'Only NMImagingSpatialReference schema version 1 is supported.');
            end
            if ~strcmp(reference.coordinateConvention,'spm_one_based_direct')
                error('NMImagingSpatialReference:UnsupportedCoordinateConvention', ...
                    'The spatial reference must use the accepted spm_one_based_direct coordinate convention.');
            end
            dimensions = NMImagingSpatialReference.normalizeDimensions(reference.dimensions);
            affine = NMImagingSpatialReference.normalizeAffine(reference.affineVoxel1ToWorld);
            inverseAffine = NMImagingSpatialReference.normalizeAffine(reference.affineWorldToVoxel);
            inverseResidual = inverseAffine * affine - eye(4);
            inverseError = max(abs(inverseResidual(:)));
            if inverseError > 1e-8
                error('NMImagingSpatialReference:AffineInverseMismatch', ...
                    'affineWorldToVoxel is inconsistent with affineVoxel1ToWorld (maximum error %g).',inverseError);
            end
            linearPart = affine(1:3,1:3);
            expectedVoxelSize = sqrt(sum(linearPart.^2,1));
            expectedAxes = linearPart ./ expectedVoxelSize;
            expectedGram = expectedAxes' * expectedAxes;
            expectedOrthogonalityError = max(abs(expectedGram(~eye(3))));
            expectedCardinalError = max(abs(1 - max(abs(expectedAxes),[],1)));
            expectedDeterminant = det(linearPart);
            if expectedDeterminant > 0
                expectedHandedness = 'right_handed';
            else
                expectedHandedness = 'left_handed';
            end
            expectedOblique = expectedOrthogonalityError > 1e-6 || expectedCardinalError > 1e-6;
            metadataError = max([ ...
                max(abs(double(reference.voxelSizeMm(:))-expectedVoxelSize(:))), ...
                max(abs(double(reference.axisUnitVectors(:))-expectedAxes(:))), ...
                abs(double(reference.determinant)-expectedDeterminant), ...
                abs(double(reference.orthogonalityError)-expectedOrthogonalityError), ...
                abs(double(reference.cardinalAlignmentError)-expectedCardinalError)]);
            if ~isfinite(metadataError) || metadataError > 1e-8 || ...
                    ~strcmp(reference.handedness,expectedHandedness) || ...
                    logical(reference.isOblique) ~= expectedOblique
                error('NMImagingSpatialReference:DerivedMetadataMismatch', ...
                    'Spatial-reference derived metadata is inconsistent with its affine.');
            end
            expectedGridId = NMImagingContractTools.stableId( ...
                'NMImagingSpatialReference',reference.schemaVersion,dimensions,affine);
            if isempty(reference.gridId) || ~strcmp(reference.gridId,expectedGridId)
                error('NMImagingSpatialReference:GridIdentityMismatch', ...
                    'Spatial gridId is absent or inconsistent with dimensions and affine.');
            end
        end
    end

    methods (Static, Access = private)
        function dimensions = normalizeDimensions(dimensions)
            if ~isnumeric(dimensions) || isempty(dimensions) || ~isreal(dimensions)
                error('NMImagingSpatialReference:InvalidDimensions', ...
                    'Spatial dimensions must be a finite numeric three-vector.');
            end
            dimensions = double(dimensions(:)');
            if numel(dimensions) < 3
                dimensions(end+1:3) = 1;
            elseif numel(dimensions) > 3
                dimensions = dimensions(1:3);
            end
            if any(~isfinite(dimensions)) || any(dimensions < 1) || any(dimensions ~= round(dimensions))
                error('NMImagingSpatialReference:InvalidDimensions', ...
                    'Spatial dimensions must contain three positive integer values.');
            end
        end

        function affine = normalizeAffine(affine)
            if ~isnumeric(affine) || ~isreal(affine) || ~isequal(size(affine),[4 4]) || any(~isfinite(affine(:)))
                error('NMImagingSpatialReference:InvalidAffine', ...
                    'Spatial affine must be one finite numeric 4-by-4 matrix.');
            end
            affine = double(affine);
            if max(abs(affine(4,:) - [0 0 0 1])) > 1e-10
                error('NMImagingSpatialReference:InvalidHomogeneousAffine', ...
                    'Spatial affine must have homogeneous final row [0 0 0 1].');
            end
            if rcond(affine) < 1e-12
                error('NMImagingSpatialReference:SingularAffine', ...
                    'Spatial affine is singular or numerically unstable.');
            end
        end

        function coordinates = normalizeCoordinates(coordinates, coordinateType)
            if ~isnumeric(coordinates) || isempty(coordinates) || ~isreal(coordinates)
                error('NMImagingSpatialReference:InvalidCoordinates', ...
                    '%s coordinates must be a nonempty numeric N-by-3 matrix.',coordinateType);
            end
            coordinates = double(coordinates);
            if isvector(coordinates) && numel(coordinates) == 3
                coordinates = reshape(coordinates,1,3);
            end
            if size(coordinates,2) ~= 3
                error('NMImagingSpatialReference:InvalidCoordinates', ...
                    '%s coordinates must be a numeric N-by-3 matrix.',coordinateType);
            end
        end
    end
end

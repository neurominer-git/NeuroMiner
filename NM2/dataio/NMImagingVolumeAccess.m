classdef NMImagingVolumeAccess
% NMImagingVolumeAccess
% -------------------------------------------------------------------------
% Narrow image-volume access for the renderer-independent imaging backend.
% SPM scaling is applied exactly once by spm_read_vols. This class does not
% resample, render, write images, or mutate NM.
%
% Documentation: docs/NMImagingVolumeAccessContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function volume = read(fileName, role)
            % read  Read one explicit three-dimensional SPM volume.
            if nargin < 2 || isempty(role), role = 'image'; end
            fileName = char(string(fileName));
            if isempty(strtrim(fileName))
                error('NMImagingVolumeAccess:EmptyFileName', ...
                    'A nonempty NIfTI/SPM image filename is required.');
            end
            [resolvedFile,messages,report] = NMDataIOImageFileTools.resolveNiftiFileForSPM( ...
                fileName,'NMImagingVolumeAccess.read',true);
            if ~NMDataIOImageFileTools.existsForSPM(resolvedFile)
                detail = '';
                if isstruct(report) && isfield(report,'message') && ~isempty(report.message)
                    detail = [' ' char(string(report.message))];
                end
                if ~isempty(messages)
                    detail = [detail ' File-resolution diagnostics were returned.']; %#ok<AGROW>
                end
                error('NMImagingVolumeAccess:UnreadableFile', ...
                    'Image file cannot be resolved for SPM: %s.%s',fileName,detail);
            end
            try
                header = spm_vol(resolvedFile);
            catch ME
                cause = MException('NMImagingVolumeAccess:HeaderReadFailed', ...
                    'SPM could not read the image header for %s.',resolvedFile);
                cause = addCause(cause,ME);
                throw(cause);
            end
            if numel(header) ~= 1
                error('NMImagingVolumeAccess:AmbiguousVolumeSelection', ...
                    ['Image source resolved to %d volumes. Supply an explicit SPM volume ' ...
                     'suffix such as ",1" when reading a four-dimensional image.'],numel(header));
            end
            try
                data = spm_read_vols(header);
            catch ME
                cause = MException('NMImagingVolumeAccess:VolumeReadFailed', ...
                    'SPM could not read image values for %s.',resolvedFile);
                cause = addCause(cause,ME);
                throw(cause);
            end
            dataDimensions = size(data);
            if numel(dataDimensions) < 3, dataDimensions(end+1:3) = 1; end
            if numel(dataDimensions) > 3 && any(dataDimensions(4:end) ~= 1)
                error('NMImagingVolumeAccess:UnexpectedDataDimensions', ...
                    'SPM returned non-three-dimensional data %s.',mat2str(size(data)));
            end
            if ~isequal(double(dataDimensions(1:3)),double(header.dim(1:3)))
                error('NMImagingVolumeAccess:UnexpectedDataDimensions', ...
                    'SPM returned dimensions %s for header dimensions %s.', ...
                    mat2str(size(data)),mat2str(header.dim(1:3)));
            end
            volumeIndex = NMImagingVolumeAccess.parseVolumeIndex(resolvedFile);
            volume = NMImagingVolumeAccess.fromArray(data,header.mat,role,resolvedFile);
            volume.provenance.source = 'spm_read_vols';
            volume.provenance.sourceFile = fileName;
            volume.provenance.resolvedFile = resolvedFile;
            volume.provenance.volumeIndex = volumeIndex;
            volume.provenance.scalingPolicy = 'spm_read_vols_once';
            volume.provenance.notes = 'No manual pinfo slope/intercept scaling was applied after spm_read_vols.';
            NMImagingVolumeAccess.validateVolume(volume);
        end

        function volume = fromArray(data, affineVoxel1ToWorld, role, sourceFile)
            % fromArray  Wrap one in-memory three-dimensional array.
            if nargin < 3 || isempty(role), role = 'image'; end
            if nargin < 4, sourceFile = ''; end
            if ~(isnumeric(data) || islogical(data)) || isempty(data) || ~isreal(data)
                error('NMImagingVolumeAccess:InvalidData', ...
                    'Volume data must be a nonempty real numeric or logical array.');
            end
            dimensions = size(data);
            if numel(dimensions) < 3
                dimensions(end+1:3) = 1;
            end
            if numel(dimensions) > 3 && any(dimensions(4:end) ~= 1)
                error('NMImagingVolumeAccess:NonThreeDimensionalData', ...
                    'The imaging volume must contain one three-dimensional array.');
            end
            dimensions = double(dimensions(1:3));
            data = reshape(data,dimensions);
            reference = NMImagingSpatialReference.create(dimensions,affineVoxel1ToWorld,role);
            volume = NMImagingContractTools.volumeTemplate();
            volume.role = char(string(role));
            volume.data = data;
            volume.dataClass = class(data);
            volume.dimensions = dimensions;
            volume.spatialReference = reference;
            volume.gridId = reference.gridId;
            finiteMask = isfinite(double(data));
            volume.finiteValueCount = nnz(finiteMask);
            if any(finiteMask(:))
                finiteValues = double(data(finiteMask));
                volume.valueRange = [min(finiteValues) max(finiteValues)];
            end
            volume.provenance.source = 'in_memory_array';
            volume.provenance.sourceFile = char(string(sourceFile));
            volume.provenance.resolvedFile = char(string(sourceFile));
            volume.provenance.scalingPolicy = 'none';
            NMImagingVolumeAccess.validateVolume(volume);
        end

        function output = withData(referenceVolume, data, role)
            % withData  Replace data while retaining the exact reference grid.
            if nargin < 3 || isempty(role), role = referenceVolume.role; end
            NMImagingVolumeAccess.validateVolume(referenceVolume);
            if ~isequal(double(size(data)),double(referenceVolume.dimensions))
                dataSize = size(data);
                if numel(dataSize) < 3, dataSize(end+1:3) = 1; end
                if ~isequal(double(dataSize(1:3)),double(referenceVolume.dimensions))
                    error('NMImagingVolumeAccess:DataGridMismatch', ...
                        'Replacement data dimensions %s do not match reference dimensions %s.', ...
                        mat2str(dataSize),mat2str(referenceVolume.dimensions));
                end
            end
            output = NMImagingVolumeAccess.fromArray(data, ...
                referenceVolume.spatialReference.affineVoxel1ToWorld,role, ...
                referenceVolume.provenance.sourceFile);
            output.provenance = referenceVolume.provenance;
            output.provenance.source = 'derived_in_memory';
            output.provenance.interpolation = 'none';
            output.provenance.outsideValue = NaN;
            NMImagingVolumeAccess.validateVolume(output);
        end

        function validateVolume(volume)
            % validateVolume  Enforce the fixed NMImagingVolume schema.
            template = NMImagingContractTools.volumeTemplate();
            if ~isstruct(volume) || ~isscalar(volume) || ...
                    ~isequal(fieldnames(volume),fieldnames(template))
                error('NMImagingVolumeAccess:InvalidVolumeSchema', ...
                    'Volume must use the fixed NMImagingVolume schema.');
            end
            if ~strcmp(volume.schema,'NMImagingVolume') || volume.schemaVersion ~= 1
                error('NMImagingVolumeAccess:UnsupportedVolumeVersion', ...
                    'Only NMImagingVolume schema version 1 is supported.');
            end
            if ~(isnumeric(volume.data) || islogical(volume.data)) || isempty(volume.data) || ~isreal(volume.data)
                error('NMImagingVolumeAccess:InvalidData', ...
                    'Volume data must be a nonempty real numeric or logical array.');
            end
            if ~ischar(volume.role) || size(volume.role,1) ~= 1
                error('NMImagingVolumeAccess:InvalidRole', ...
                    'Volume role must be one character row vector.');
            end
            reference = NMImagingSpatialReference.fromVolume(volume);
            dimensions = double(volume.dimensions(:)');
            if ~isequal(dimensions,double(reference.dimensions))
                error('NMImagingVolumeAccess:ReferenceDimensionMismatch', ...
                    'Volume dimensions disagree with its spatial reference.');
            end
            dataSize = size(volume.data);
            if numel(dataSize) < 3, dataSize(end+1:3) = 1; end
            if numel(dataSize) > 3 && any(dataSize(4:end) ~= 1)
                error('NMImagingVolumeAccess:NonThreeDimensionalData', ...
                    'Volume data must be three-dimensional.');
            end
            if ~isequal(double(dataSize(1:3)),dimensions)
                error('NMImagingVolumeAccess:DataDimensionMismatch', ...
                    'Volume data dimensions disagree with the fixed dimensions field.');
            end
            if ~strcmp(volume.gridId,reference.gridId)
                error('NMImagingVolumeAccess:GridIdentityMismatch', ...
                    'Volume gridId disagrees with its spatial-reference gridId.');
            end
            if ~strcmp(volume.dataClass,class(volume.data))
                error('NMImagingVolumeAccess:DataClassMismatch', ...
                    'Volume dataClass disagrees with the in-memory array class.');
            end
            finiteMask = isfinite(double(volume.data));
            expectedFiniteCount = nnz(finiteMask);
            if volume.finiteValueCount ~= expectedFiniteCount
                error('NMImagingVolumeAccess:FiniteValueCountMismatch', ...
                    'Volume finiteValueCount disagrees with the in-memory data.');
            end
            if expectedFiniteCount > 0
                finiteValues = double(volume.data(finiteMask));
                expectedRange = [min(finiteValues) max(finiteValues)];
            else
                expectedRange = [NaN NaN];
            end
            if ~isequaln(double(volume.valueRange),expectedRange)
                error('NMImagingVolumeAccess:ValueRangeMismatch', ...
                    'Volume valueRange disagrees with the in-memory data.');
            end
            volumeTemplate = NMImagingContractTools.volumeTemplate();
            provenanceTemplate = volumeTemplate.provenance;
            if ~isstruct(volume.provenance) || ~isscalar(volume.provenance) || ...
                    ~isequal(fieldnames(volume.provenance),fieldnames(provenanceTemplate))
                error('NMImagingVolumeAccess:InvalidProvenanceSchema', ...
                    'Prepared image metadata are invalid. Run Preview again and check the image header if the problem persists.');
            end
        end
    end

    methods (Static, Access = private)
        function index = parseVolumeIndex(fileName)
            token = regexp(char(string(fileName)),',([0-9]+)$','tokens','once');
            if isempty(token)
                index = 1;
            else
                index = str2double(token{1});
            end
        end
    end
end

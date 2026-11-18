classdef NMResultsViewerImagingDescriptorAdapter
% NMResultsViewerImagingDescriptorAdapter
% -------------------------------------------------------------------------
% Normalize current NM2 and inherited NM 1.4 imaging descriptors at one
% explicit adapter boundary. The adapter classifies spatial feature families,
% resolves the space-defining mask source, mask threshold/operator, and
% badcoords, and can load the authoritative feature-space volume from either
% a file or the persisted Vm/Vmvol pair stored in inherited datadescriptors.
%
% It does not inspect VIS measure values, resample images, render graphics,
% serialize browser assets, or mutate NM.
% -------------------------------------------------------------------------

    methods (Static)
        function out = resolve(NM, varind, ~)
            % resolve  Normalize one modality's persisted imaging descriptor.
            %
            % Current modality identity is normalized by NMModalityInfoTools.
            % Canonical ROI provenance terminates resolution when valid. Only
            % non-ROI modalities enter the inherited NM 1.4 mask/Vm boundary.
            out = NMResultsViewerImagingDescriptorAdapter.template();
            validateattributes(varind,{'numeric'},{'scalar','finite','integer','positive'}, ...
                'NMResultsViewerImagingDescriptorAdapter.resolve','varind');
            out.varind = double(varind);
            if out.varind > numel(NM.datadescriptor)
                out.message = sprintf('Imaging descriptor modality %d is unavailable.',out.varind);
                return;
            end
            dd = NM.datadescriptor{out.varind};
            input = dd.input_settings;
            info = NMModalityInfoTools.fromNM(NM,out.varind,struct('ScanInMemory',false));

            out.roiProvenance = NMDataIOROIProvenanceTools.normalizeDescriptor(dd, []);
            if NMDataIOROIProvenanceTools.declaredInDescriptor(dd) && ~out.roiProvenance.ok
                out.message = sprintf('Invalid ROI provenance for modality %d: %s', out.varind, out.roiProvenance.message);
                return;
            end
            if out.roiProvenance.ok
                out.featureKind = 'roi';
                out.sourceFamily = 'roi';
                out.ok = true;
                out.message = sprintf('Resolved modality %d from validated canonical ROI provenance.',out.varind);
                return;
            end

            [out.embeddedFeatureSpaceAvailable,out.embeddedFeatureSpaceProvenance, ...
                out.embeddedFeatureSpaceDimensions,out.embeddedFeatureSpaceAffine] = ...
                NMResultsViewerImagingDescriptorAdapter.embeddedMetadata(dd);

            % nm2-allow: NM2 DataIO spaceDefType is the generation marker separating current spatial state from inherited NM1.4 state
            if isfield(input,'spaceDefType')
                out.spatialContractProvenance = 'dataio_input_settings';
                out.spaceDefType = input.spaceDefType;
                if ~ismember(out.spaceDefType,{'brainmask','atlas','surface_template'})
                    error('NMResultsViewerImagingDescriptorAdapter:InvalidSpaceDefinitionType', ...
                        'DataIO persisted unsupported spaceDefType "%s" for modality %d.',out.spaceDefType,out.varind);
                end
                out.featureSpaceFile = regexprep(input.maskFile,',\d+$','');
                out.featureSpaceFileProvenance = 'dataio_input_settings_maskFile';
                if strcmp(out.spaceDefType,'atlas')
                    out.atlasFile = out.featureSpaceFile;
                    % nm2-allow: NMDataIOImageImportTools conditionally persists resolved atlasInfo after atlas descriptor materialization
                    if isfield(input,'atlasInfo')
                        out.atlasDescriptorFile = input.atlasInfo.labelDescriptor.file;
                    else
                        out.atlasDescriptorFile = input.atlasLabelFile;
                    end
                end
            else
                out.spatialContractProvenance = 'inherited_nm14';
                [out.featureSpaceFile,out.featureSpaceFileProvenance] = ...
                    NMResultsViewerImagingDescriptorAdapter.inheritedFeatureSpaceFile(NM,out.varind);
            end
            out.featureSpaceFileExists = NMResultsViewerImagingDescriptorAdapter.fileExists(out.featureSpaceFile);
            out.featureKind = NMResultsViewerImagingDescriptorAdapter.featureKind(info);
            if strcmp(out.featureKind,'roi')
                error('NMResultsViewerImagingDescriptorAdapter:MissingROIProvenance', ...
                    'Modality %d is normalized as ROI but has no valid canonical ROI provenance.',out.varind);
            end
            out.sourceFamily = NMResultsViewerImagingDescriptorAdapter.sourceFamily(info,out.featureKind);
            out.badcoords = NMResultsViewerImagingDescriptorAdapter.badcoords(NM,out.varind);
            out.maskSelection = NMResultsViewerImagingDescriptorAdapter.maskSelection(dd,out.featureKind);
            out.ok = true;
            out.message = sprintf(['Resolved modality %d as %s using %s feature-space provenance ' ...
                '(file=%d, embedded=%d).'],out.varind,out.featureKind, ...
                NMResultsViewerImagingDescriptorAdapter.featureSpaceProvenance(out), ...
                out.featureSpaceFileExists,out.embeddedFeatureSpaceAvailable);
        end

        function [volume, descriptor] = loadFeatureSpace(NM, varind, requestedFile)
            % loadFeatureSpace  Load the exact mask grid from file or persisted Vm/Vmvol.
            descriptor = NMResultsViewerImagingDescriptorAdapter.resolve(NM,varind,struct());
            if ~descriptor.ok
                error('NMResultsViewerImagingDescriptorAdapter:DescriptorUnavailable','%s',descriptor.message);
            end
            requestedFile = NMResultsViewerImagingDescriptorAdapter.requestText(requestedFile,'requestedFile');
            if ~isempty(requestedFile) && NMResultsViewerImagingDescriptorAdapter.fileExists(requestedFile)
                volume = NMImagingVolumeAccess.read(requestedFile,'feature_space_mask');
                volume.provenance.notes = ['Feature-space mask resolved from the selected spatial descriptor. ' ...
                    volume.provenance.notes];
                return;
            end
            if descriptor.featureSpaceFileExists
                volume = NMImagingVolumeAccess.read(descriptor.featureSpaceFile,'feature_space_mask');
                volume.provenance.notes = sprintf('Feature-space mask resolved through %s. %s', ...
                    descriptor.featureSpaceFileProvenance,volume.provenance.notes);
                return;
            end
            [data,affine,provenance] = NMResultsViewerImagingDescriptorAdapter.embeddedData(NM,varind);
            if isempty(data)
                if isempty(requestedFile), attempted = descriptor.featureSpaceFile; else, attempted = requestedFile; end
                error('NMResultsViewerImagingDescriptorAdapter:FeatureSpaceUnavailable', ...
                    ['No readable space-defining image and no valid persisted Vm/Vmvol pair are ' ...
                     'available for modality %d. Resolved file: %s'],varind,attempted);
            end
            volume = NMImagingVolumeAccess.fromArray(data,affine,'feature_space_mask','');
            volume.provenance.source = 'inherited_datadescriptor_Vmvol';
            volume.provenance.sourceFile = provenance;
            volume.provenance.resolvedFile = '';
            volume.provenance.scalingPolicy = 'persisted_values_no_rescaling';
            volume.provenance.notes = ['Inherited NM 1.4 feature-space mask reconstructed from the ' ...
                'persisted Vm/Vmvol pair because the original file was unavailable.'];
        end

        function identity = featureSpaceIdentity(NM, varind, requestedFile, descriptor)
            % featureSpaceIdentity  Identify one selected modality's exact feature-space source.
            if ~descriptor.ok
                error('NMResultsViewerImagingDescriptorAdapter:DescriptorUnavailable', ...
                    'A valid normalized descriptor is required for feature-space identity.');
            end
            requestedFile = regexprep(NMResultsViewerImagingDescriptorAdapter.requestText(requestedFile,'requestedFile'),',\d+$','');
            if ~isempty(requestedFile) && NMResultsViewerImagingDescriptorAdapter.fileExists(requestedFile)
                identity = ['requested_file:' NMImagingContentIdentity.fileFingerprint(requestedFile)];
                return;
            end
            if descriptor.featureSpaceFileExists
                identity = ['descriptor_file:' NMImagingContentIdentity.fileFingerprint(descriptor.featureSpaceFile)];
                return;
            end
            [data,affine,provenance] = NMResultsViewerImagingDescriptorAdapter.embeddedData(NM,varind);
            if isempty(data)
                error('NMResultsViewerImagingDescriptorAdapter:FeatureSpaceUnavailable', ...
                    'Modality %d has no file-backed or persisted feature-space source.',round(double(varind)));
            end
            dataHash = NMImagingContentIdentity.hashArray(double(data),'double');
            affineHash = NMImagingContentIdentity.hashArray(double(affine),'double');
            identity = strjoin({'embedded',provenance,dataHash,affineHash},'|');
        end

        function out = template()
            out = struct( ...
                'schema','NMResultsViewerImagingDescriptor', ...
                'schemaVersion',1, ...
                'contractVersion','C18b2a', ...
                'ok',false, ...
                'message','', ...
                'varind',0, ...
                'featureKind','tabular', ...
                'sourceFamily','unknown', ...
                'spatialContractProvenance','none', ...
                'spaceDefType','legacy', ...
                'featureSpaceFile','', ...
                'featureSpaceFileProvenance','none', ...
                'atlasFile','', ...
                'atlasDescriptorFile','', ...
                'featureSpaceFileExists',false, ...
                'embeddedFeatureSpaceAvailable',false, ...
                'embeddedFeatureSpaceProvenance','none', ...
                'embeddedFeatureSpaceDimensions',[0 0 0], ...
                'embeddedFeatureSpaceAffine',eye(4), ...
                'badcoords',[], ...
                'roiProvenance',NMDataIOROIProvenanceTools.template(), ...
                'maskSelection',NMImagingContractTools.maskSelectionTemplate());
        end
    end

    methods (Static, Access = private)
        function kind = featureKind(info)
            % featureKind  Map the normalized NM2 modality authority to one renderer family.
            if strcmp(info.sourceType,'connectivity')
                kind = 'connectivity_edge';
            elseif strcmp(info.sourceType,'roi')
                kind = 'roi';
            elseif strcmp(info.datasource,'surf') || strcmp(info.sourceType,'surface-list')
                kind = 'surface_vertex';
            elseif ismember(info.datasource,{'spm','nifti','image'}) || strcmp(info.sourceType,'image-list')
                kind = 'voxel';
            elseif info.typeCode == 0
                kind = 'tabular';
            else
                error('NMResultsViewerImagingDescriptorAdapter:UnsupportedModalityIdentity', ...
                    'Normalized modality %d has unsupported datasource/sourceType identity (%s / %s).', ...
                    info.modalityIndex,info.datasource,info.sourceType);
            end
        end

        function family = sourceFamily(info,featureKind)
            switch featureKind
                case 'connectivity_edge'
                    family = 'connectivity';
                case 'roi'
                    family = 'roi';
                otherwise
                    family = info.datasource;
            end
            if isempty(family) || strcmp(family,'unknown')
                family = info.sourceType;
            end
        end

        function [fileName,provenance] = inheritedFeatureSpaceFile(NM,varind)
            % inheritedFeatureSpaceFile  Read the inherited NM 1.4 active brainmask authority.
            fileName = '';
            provenance = 'none';
            if varind > numel(NM.brainmask), return; end
            if isempty(NM.brainmask{varind}), return; end
            value = NM.brainmask{varind};
            % nm2-allow: TransferModality2NM permits inherited brainmask to be either file-backed text or in-memory mask material
            if ischar(value)
                fileName = regexprep(value,',\d+$','');
                provenance = 'inherited_nm_brainmask';
            % nm2-allow: TransferModality2NM may preserve a MATLAB string path at the inherited brainmask boundary
            elseif isstring(value) && isscalar(value)
                fileName = regexprep(char(value),',\d+$','');
                provenance = 'inherited_nm_brainmask';
            end
        end

        function [available,provenance,dimensions,affine] = embeddedMetadata(dd)
            available=false; provenance='none'; dimensions=[0 0 0]; affine=eye(4);
            % nm2-allow: TransferModality2NM conditionally writes Vm and Vmvol only for inherited imaging modalities
            if ~isfield(dd,'Vm') || ~isfield(dd,'Vmvol') || isempty(dd.Vmvol)
                return;
            end
            [valid,dimensions,affine] = NMResultsViewerImagingDescriptorAdapter.validateEmbeddedPair(dd.Vm,dd.Vmvol);
            if valid
                available=true;
                provenance='datadescriptor_Vmvol';
            end
        end

        function [data,affine,provenance] = embeddedData(NM,varind)
            data=[]; affine=[]; provenance='';
            dd=NM.datadescriptor{varind};
            % nm2-allow: TransferModality2NM conditionally writes Vm and Vmvol only for inherited imaging modalities
            if ~isfield(dd,'Vm') || ~isfield(dd,'Vmvol') || isempty(dd.Vmvol)
                return;
            end
            [valid,dimensions,affine] = NMResultsViewerImagingDescriptorAdapter.validateEmbeddedPair(dd.Vm,dd.Vmvol);
            if ~valid, return; end
            data=reshape(dd.Vmvol,dimensions);
            provenance='datadescriptor_Vmvol';
        end

        function [valid,dimensions,affine] = validateEmbeddedPair(header,data)
            % validateEmbeddedPair  Verify persisted inherited Vm/Vmvol geometry before reuse.
            valid=false; dimensions=[0 0 0]; affine=eye(4);
            % nm2-allow: inherited TransferModality2NM Vm header is validated before persisted geometry materialization
            if ~isstruct(header) || ~isfield(header,'mat'), return; end
            % nm2-allow: inherited TransferModality2NM Vmvol payload is validated before persisted geometry materialization
            if ~(isnumeric(data)||islogical(data)) || isempty(data) || ~isreal(data), return; end
            sz=size(data); if numel(sz)<3, sz(end+1:3)=1; end
            % nm2-allow: inherited Vm/Vmvol persistence boundary validates that feature-space material is one 3-D volume
            if numel(sz)>3 && any(sz(4:end)~=1), return; end
            dimensions=double(sz(1:3));
            if any(~isfinite(dimensions)) || any(dimensions<1) || any(mod(dimensions,1)~=0), return; end
            % nm2-allow: SPM Vm writer normally supplies dim; persisted historical headers are validated when that optional header field is present
            if isfield(header,'dim') && ~isempty(header.dim)
                headerDimensions=double(header.dim(:).');
                % nm2-allow: inherited Vm header dimensions must match persisted Vmvol geometry exactly
                if numel(headerDimensions)<3 || any(~isfinite(headerDimensions(1:3))) || ...
                        ~isequal(round(headerDimensions(1:3)),dimensions)
                    return;
                end
            end
            affine=double(header.mat);
            % nm2-allow: inherited SPM Vm affine is validated at the persisted geometry boundary before reuse
            if ~isequal(size(affine),[4 4]) || any(~isfinite(affine(:))) || abs(det(affine))<=eps
                return;
            end
            valid=true;
        end

        function bad = badcoords(NM,varind)
            bad = NM.badcoords{varind};
            if isempty(bad), return; end
            bad = bad(:);
        end

        function selection = maskSelection(dd,featureKind)
            selection=NMImagingContractTools.maskSelectionTemplate();
            if ~ismember(featureKind,{'voxel','surface_vertex'}), return; end
            selection.threshold=double(dd.threshval);
            op=dd.threshop{1};
            % nm2-allow: nk_DataIO3_SpaceDefImage_config is the inherited writer of exactly gt/ge/eq/lt/le mask operators
            if ~ismember(op,{'gt','ge','eq','lt','le'})
                error('NMResultsViewerImagingDescriptorAdapter:UnsupportedMaskOperator', ...
                    'Persisted mask operator "%s" is unsupported.',op);
            end
            selection.operator=op;
        end

        function txt = requestText(value,name)
            if isempty(value), txt=''; return; end
            % nm2-allow: public imaging-resource request boundary accepts MATLAB character or scalar-string path transport
            if ischar(value)
                txt=value;
            % nm2-allow: public imaging-resource request boundary accepts MATLAB character or scalar-string path transport
            elseif isstring(value) && isscalar(value)
                txt=char(value);
            else
                error('NMResultsViewerImagingDescriptorAdapter:InvalidRequestText', ...
                    '%s must be a character vector or scalar string.',name);
            end
        end

        function tf = fileExists(fileName)
            tf=false;
            if isempty(fileName), return; end
            tf=NMDataIOImageFileTools.existsForSPM(fileName);
        end

        function provenance = featureSpaceProvenance(out)
            if out.featureSpaceFileExists
                provenance=out.featureSpaceFileProvenance;
            elseif out.embeddedFeatureSpaceAvailable
                provenance=out.embeddedFeatureSpaceProvenance;
            else
                provenance='unavailable';
            end
        end
    end
end

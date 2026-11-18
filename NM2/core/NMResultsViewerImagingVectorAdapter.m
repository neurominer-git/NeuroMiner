classdef NMResultsViewerImagingVectorAdapter
% NMResultsViewerImagingVectorAdapter
% -------------------------------------------------------------------------
% Narrow adapter from the authoritative selected feature-vector
% contract to the shared volumetric imaging workspace. It admits native voxel
% vectors and canonical volumetric ROI vectors. Voxel contexts additionally
% receive DataIO mask-selection normalization; ROI contexts remain regional
% here and are expanded exactly through canonical ROI provenance by the
% imaging workspace.
%
% Materialization and performance: this adapter does not read image or atlas
% files. It resolves one resident Feature Inspection or MLI vector. Descriptor
% normalization is performed only for voxel contexts that need mask-selection
% metadata. Canonical volumetric ROI contexts do not reopen DataIO provenance.
% Safe on Results Viewer workspace initialization paths.
% -------------------------------------------------------------------------

    methods (Static)
        function out = resolve(NM, spec, measureId, inspection)
            % resolve  Return one exact volumetric feature vector.
            %
            % Inputs/outputs: NM/spec/measureId/inspection follow the public
            % shared Results Viewer feature-vector contract. The output preserves that
            % scientific identity and adds voxel mask-selection metadata only
            % for native voxel contexts.
            %
            % Authority and scientific contract: native voxel contexts and
            % canonical volumetric ROI contexts are the only admissible
            % volumetric domains. ROI eligibility is established exclusively
            % from the canonical context projection (volume + canonical_roi +
            % atlas_label_id); this adapter does not infer ROI status.
            %
            % Materialization/performance: no files, atlas labels, meshes,
            % voxels or vertices are read or scanned here. Canonical ROI values
            % remain ROI-level and are expanded later by the provenance-owned
            % exact mapping authority. Safe on interactive workspace startup.
            %
            % Failure semantics: unsupported domains and invalid voxel
            % descriptors return an explicit non-ok result; spatial domains and feature kinds are never substituted.
            out = struct( ...
                'schema','NMResultsViewerImagingVector', ...
                'schemaVersion',1, ...
                'contractVersion','C18b2a', ...
                'ok',false, ...
                'message','', ...
                'scientificContractVersion','', ...
                'scientificAnnotation',struct(), ...
                'resolvedSelection',struct(), ...
                'analysisIndex',0, ...
                'targetIndex',0, ...
                'resultTargetIndex',NaN, ...
                'classifierIndex',0, ...
                'context',struct(), ...
                'measure',struct(), ...
                'spatialMap',struct(), ...
                'component',struct(), ...
                'values',[], ...
                'badcoords',[], ...
                'maskSelection',NMImagingContractTools.maskSelectionTemplate(), ...
                'diagnostic',struct());
            base = NMResultsViewerFeatureVectorAuthority.vector(NM,spec,measureId,inspection);
            out.scientificContractVersion = base.scientificContractVersion;
            out.scientificAnnotation = base.scientificAnnotation;
            out.resolvedSelection = base.resolvedSelection;
            out.analysisIndex = base.analysisIndex;
            out.targetIndex = base.targetIndex;
            out.resultTargetIndex = base.resultTargetIndex;
            out.classifierIndex = base.classifierIndex;
            out.context = base.context;
            out.measure = base.measure;
            out.spatialMap = base.spatialMap;
            out.component = base.component;
            out.values = base.values;
            out.badcoords = base.badcoords;
            out.diagnostic = base.diagnostic;
            if ~base.ok
                out.message = base.message;
                return;
            end
            kind = base.context.featureKind;
            isVoxel = strcmp(kind,'voxel');
            isCanonicalVolumeROI = strcmp(kind,'roi') && ...
                strcmp(base.context.roiSpatialDomain,'volume') && ...
                strcmp(base.context.roiSpatialSemantics,'canonical_roi') && ...
                strcmp(base.context.roiIdentityModel,'atlas_label_id');
            if ~(isVoxel || isCanonicalVolumeROI)
                out.message = sprintf(['The volumetric imaging viewer requires a voxel context or canonical volumetric ROI provenance; ' ...
                    'selected context is %s.'],kind);
                return;
            end
            if isCanonicalVolumeROI
                out.ok = true;
                out.message = sprintf('Resolved exact canonical volumetric ROI vector %s with %d value(s).', ...
                    base.measure.measureId,numel(base.values));
                return;
            end
            varind = round(double(base.context.varind));
            descriptor = NMResultsViewerImagingDescriptorAdapter.resolve(NM,varind,struct());
            if ~descriptor.ok
                out.message = descriptor.message;
                return;
            end
            out.maskSelection = descriptor.maskSelection;
            if isempty(out.badcoords) && ~isempty(descriptor.badcoords)
                out.badcoords = descriptor.badcoords;
            end
            out.ok = true;
            out.message = sprintf('Resolved exact voxel vector %s with %d value(s).', ...
                base.measure.measureId,numel(base.values));
        end
    end
end

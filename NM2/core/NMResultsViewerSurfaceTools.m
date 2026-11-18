classdef NMResultsViewerSurfaceTools
% NMResultsViewerSurfaceTools
% -------------------------------------------------------------------------
% Viewer-local native-surface adapter for the NM 2.0 Results Viewer.
%
% This class does not extend or mutate the DataIO descriptor contract. It
% consumes authoritative surface geometry and canonical spatial provenance,
% transports resident vertex values and indexed geometry to the browser, and
% materializes annotation labels at the explicit viewer-workspace boundary.
%
% Native vertex payloads may use viewer-selected FreeSurfer annotations.
% Canonical surface-ROI payloads instead load the producer-owned annotation and
% display mesh automatically; that annotation is fixed because hemisphere +
% source annotation ID is part of the scientific feature identity. The mesh
% supplies geometry only and is never an ROI-identity authority.
%
% Contract version: NM-RESULTS-SURFACE-STAGE4B-V1
% -------------------------------------------------------------------------

    methods (Static)
        function payload = buildWorkspace(NM, req, tmpDir, inspection, context, diagnostics)
            % buildWorkspace  Materialize native-vertex or canonical surface-ROI data for the shared 3-D surface viewer.
            %
            % Purpose:
            %   Reuse the existing native-surface Results Viewer for both vertexwise payloads and canonical
            %   surface ROI payloads. ROI parcels are expanded only by exact hemisphere + annotation-ID
            %   membership; no mesh geometry, anatomical names, smoothing, or positional inference defines ROI identity.
            %
            % Authority and flow:
            %   Scientific Annotation selects the spatial domain. Native vertex data uses the persisted DataIO
            %   surface geometry contract. Canonical ROI data resolves its authoritative annotation/display-mesh
            %   pair from NMDataIOROIProvenanceTools and expands ROI values through that provenance authority.
            %
            % Materialization and performance:
            %   This is an explicit viewer-workspace materialization boundary. It may read surface meshes and
            %   annotations and creates vertex-scale browser assets. It must not execute during interactive
            %   navigation, camera changes, threshold changes, or subject/measure switching inside a resident workspace.
            %
            % Failure semantics:
            %   Missing/ambiguous provenance files, annotation/mesh vertex disagreement, missing canonical ROI IDs,
            %   or feature-length disagreement fail explicitly. Atlas substitution and ROI-name inference are not permitted.
            % nm2-allow: Scientific Capability provider boundary permits one-argument interrogation
            if nargin>=1 && NMResultsViewerScientificCapability.isQuery(NM)
                p=[NMResultsViewerScientificCapability.provide('surface_workspace','scientific_artefact','surface','surface_workspace'), ...
                    NMResultsViewerScientificCapability.provide('surface_data_3d','visualization','',''), ...
                    NMResultsViewerScientificCapability.provide('roi_spider','visualization','','')];
                payload=NMResultsViewerScientificCapability.contract('surface_workspace',{{'surface_feature_map','roi_feature_map'}},p); return;
            end
            payload = NMResultsViewerSurfaceTools.workspaceTemplate();
            payload.diagnostics = diagnostics;
            try
                adapterSelection = NMResultsViewerFeatureVectorAuthority.selection(req,inspection);
                requestedIds = adapterSelection.measureIds;
                resolvedVectors = cell(1,numel(requestedIds));
                for measureIndex = 1:numel(requestedIds)
                    vectorSpec = req;
                    vectorSpec.measureId = requestedIds{measureIndex};
                    vectorSpec.measureIds = [];
                    resolvedVectors{measureIndex} = NMResultsViewerFeatureVectorAuthority.vector( ...
                        NM,vectorSpec,requestedIds{measureIndex},inspection);
                    if ~resolvedVectors{measureIndex}.ok
                        error('NMResultsViewerSurfaceTools:SurfaceVectorUnavailable','%s',resolvedVectors{measureIndex}.message);
                    end
                end
                firstVector = resolvedVectors{1};
                canonicalContext = firstVector.context;
                if ~isempty(context)
                    suppliedContextId = context.contextId;
                    canonicalContextId = canonicalContext.contextId;
                    if ~strcmp(suppliedContextId,canonicalContextId)
                        error('NMResultsViewerSurfaceTools:SurfaceContextMismatch', ...
                            'Supplied surface context %s does not match canonical context %s.',suppliedContextId,canonicalContextId);
                    end
                end
                context = canonicalContext;
                featureKind = context.featureKind;
                isCanonicalROI = strcmp(featureKind,'roi');
                if isCanonicalROI
                    if ~strcmp(context.roiSpatialDomain,'surface')
                        error('NMResultsViewerSurfaceTools:ROISurfaceDomainMismatch', ...
                            'Canonical ROI surface workspace construction requires roiSpatialDomain=surface.');
                    end
                elseif ~strcmp(featureKind,'surface_vertex')
                    error('NMResultsViewerSurfaceTools:NotSurfaceContext', ...
                        'Shared surface workspace construction requires surface_vertex or canonical surface ROI provenance.');
                end

                varind = context.varind;
                sourceVectors = resolvedVectors;
                canonicalAtlas = NMResultsViewerSurfaceTools.emptySelectedAtlas();
                if isCanonicalROI
                    descriptor = NMResultsViewerImagingDescriptorAdapter.resolve(NM,varind,struct());
                    if ~descriptor.ok || ~descriptor.roiProvenance.ok
                        error('NMResultsViewerSurfaceTools:ROIProvenanceUnavailable', ...
                            'Canonical surface ROI provenance is unavailable for modality %d: %s',varind,descriptor.message);
                    end
                    projection = NMDataIOROIProvenanceTools.spatialProjection(descriptor.roiProvenance);
                    if ~strcmp(projection.spatialDomain,'surface')
                        error('NMResultsViewerSurfaceTools:ROIProvenanceDomainMismatch', ...
                            'Canonical ROI provenance does not resolve to the surface spatial domain.');
                    end
                    [geometry,annotationParts,atlasCodes,annotationPaths] = ...
                        NMResultsViewerSurfaceTools.resolveCanonicalROISurfaceGeometry(descriptor.roiProvenance);
                    for ii=1:numel(resolvedVectors)
                        roiValues = double(resolvedVectors{ii}.values(:));
                        if numel(roiValues) ~= descriptor.roiProvenance.nColumns
                            error('NMResultsViewerSurfaceTools:ROIFeatureCountMismatch', ...
                                'Measure %s has %g ROI values but canonical provenance defines %g ROI columns.', ...
                                requestedIds{ii},numel(roiValues),descriptor.roiProvenance.nColumns);
                        end
                        resolvedVectors{ii}.values = NMResultsViewerSurfaceTools.expandCanonicalROISurfaceValues( ...
                            descriptor.roiProvenance,roiValues,annotationParts,geometry.vertexCount);
                    end
                    canonicalAtlas = NMResultsViewerSurfaceTools.canonicalROISurfaceAtlas( ...
                        tmpDir,descriptor.roiProvenance,geometry,atlasCodes,annotationPaths,projection.spatialReferenceIdentity);
                else
                    expectedVertices = numel(firstVector.values);
                    geometry = NMResultsViewerSurfaceTools.resolveGeometry(NM,varind,expectedVertices);
                end
                package = NMResultsViewerSurfaceTools.writeSurfacePackage(tmpDir,geometry,resolvedVectors);

                overlayTemplate = struct('measureId','','label','','sourceField','','valuePolarity','signed', ...
                    'valueRange',[NaN NaN],'displayDefaults',struct(),'url','','dataType','float32', ...
                    'elementCount',0,'contentHash','','mapKind',featureKind,'contextId','');
                overlays = repmat(overlayTemplate,1,numel(requestedIds));
                for ii = 1:numel(requestedIds)
                    vector = sourceVectors{ii};
                    sourceValues = double(vector.values(:));
                    finiteValues = sourceValues(isfinite(sourceValues));
                    range = [NaN NaN];
                    if ~isempty(finiteValues), range = [min(finiteValues) max(finiteValues)]; end
                    overlays(ii).measureId = vector.measure.measureId;
                    overlays(ii).label = vector.measure.label;
                    overlays(ii).sourceField = vector.measure.sourceField;
                    overlays(ii).valuePolarity = vector.measure.valuePolarity;
                    displayDefaults = NMImagingColorMapping.defaults(sourceValues,vector.measure);
                    overlays(ii).valueRange = displayDefaults.valueRange;
                    overlays(ii).displayDefaults = displayDefaults;
                    overlays(ii).url = package.overlayAssets(ii).url;
                    overlays(ii).elementCount = geometry.vertexCount;
                    overlays(ii).contentHash = package.overlayAssets(ii).contentHash;
                    overlays(ii).contextId = context.contextId;
                end

                geometryCatalogue = struct('templateId',{},'geometryId',{},'label',{},'enabled',{},'disabledReason',{},'isDefault',{});
                geometryCatalogue(1) = struct('templateId','native','geometryId',geometry.native.geometryId, ...
                    'label','Native','enabled',true,'disabledReason','','isDefault',true);
                inflatedReason = geometry.inflated.disabledReason;
                if ~geometry.inflated.declared && isempty(inflatedReason)
                    inflatedReason = 'No validated inflated geometry is configured for this surface modality.';
                end
                geometryCatalogue(2) = struct('templateId','inflated','geometryId',geometry.inflated.geometryId, ...
                    'label','Inflated','enabled',geometry.inflated.available, ...
                    'disabledReason',inflatedReason,'isDefault',false);
                selectedGeometryId = lower(req.selectedTemplateId);
                if ~any(strcmp({geometryCatalogue.templateId},selectedGeometryId) & [geometryCatalogue.enabled])
                    selectedGeometryId = 'native';
                end

                identityParts = {'NM-RESULTS-SURFACE-STAGE4B-V2', ...
                    ['context=' context.contextId],['measures=' strjoin(requestedIds,'>')], ...
                    ['geometry=' geometry.native.geometryId],['topology=' geometry.topologyIdentity], ...
                    ['vertexOrder=' geometry.vertexOrderIdentity],['overlayHashes=' strjoin({package.overlayAssets.contentHash},'>')]};
                if isCanonicalROI, identityParts{end+1}=['roiSpatial=' projection.spatialReferenceIdentity]; end %#ok<AGROW>
                contentId = NMImagingContentIdentity.hashText(strjoin(identityParts,'|'));

                payload.ok = true;
                if isCanonicalROI
                    payload.message = sprintf('Prepared %d canonical surface-ROI overlay(s) on %g annotation-labelled vertices.',numel(overlays),geometry.vertexCount);
                else
                    payload.message = sprintf('Prepared %d native-surface overlay(s) on %g authoritative vertices.',numel(overlays),geometry.vertexCount);
                end
                payload.contentId = contentId;
                payload.sourceDomain = 'surface';
                payload.scientificContractVersion = firstVector.scientificContractVersion;
                payload.scientificAnnotation = firstVector.scientificAnnotation;
                payload.resolvedSelection = firstVector.resolvedSelection;
                payload.analysisIndex = firstVector.analysisIndex;
                payload.targetIndex = firstVector.targetIndex;
                payload.resultTargetIndex = firstVector.resultTargetIndex;
                payload.classifierIndex = firstVector.classifierIndex;
                payload.resultSourceId = req.source;
                payload.selectedFeatureContextId = context.contextId;
                payload.surfaceModalityIndex = varind;
                payload.dimensions = [geometry.vertexCount 1 1];
                payload.templateCatalogue = geometryCatalogue;
                selected = geometryCatalogue(strcmp({geometryCatalogue.templateId},selectedGeometryId));
                payload.selectedTemplate = struct('available',true,'templateId',selectedGeometryId, ...
                    'label',selected.label,'provenance','authoritative_surface_geometry','gridId',geometry.topologyIdentity);
                payload.overlays = overlays;
                if isCanonicalROI
                    canonicalROIValues = cellfun(@(vector)double(vector.values(:)'),sourceVectors,'UniformOutput',false);
                    payload.canonicalROI = NMDataIOROIProvenanceTools.viewerMaterialization( ...
                        descriptor.roiProvenance,requestedIds,canonicalROIValues);
                end
                payload.surface = NMResultsViewerSurfaceTools.browserGeometryPayload(geometry,package,selectedGeometryId);
                payload.support = struct('url',package.supportAsset.url,'dataType','uint8', ...
                    'elementCount',geometry.vertexCount,'contentHash',package.supportAsset.contentHash);
                if isCanonicalROI
                    payload.atlasCatalogue = struct('atlasId',canonicalAtlas.atlasId,'label',canonicalAtlas.label, ...
                        'file','','fileExists',false,'descriptorFile','','descriptorFileExists',false, ...
                        'lutFile','','lutFileExists',false,'lutProvenance','canonical_roi_provenance', ...
                        'provenance','canonical_roi_provenance','enabled',true,'disabledReason','');
                    payload.selectedAtlas = canonicalAtlas;
                else
                    payload.atlasCatalogue = struct('atlasId','surface_annot_file','label','Load FreeSurfer .annot atlas…', ...
                        'file','','fileExists',false,'descriptorFile','','descriptorFileExists',false, ...
                        'lutFile','','lutFileExists',false,'lutProvenance','embedded_annotation_colortable', ...
                        'provenance','viewer_selected_freesurfer_annot_pair','enabled',true,'disabledReason','');
                    payload.selectedAtlas = NMResultsViewerSurfaceTools.emptySelectedAtlas();
                end
                payload.capabilities = NMResultsViewerSurfaceTools.surfaceCapabilities(isCanonicalROI);
                payload.initialVoxel = [1 1 1];
                payload.initialWorldMm = geometry.native.bounds.center;
                payload.spatialReference = struct('schema','NMSurfaceSpatialReference','schemaVersion',1, ...
                    'gridId',geometry.topologyIdentity,'coordinateSpace','world_mm', ...
                    'geometryIdentity',geometry.native.geometryId,'topologyIdentity',geometry.topologyIdentity, ...
                    'vertexOrderIdentity',geometry.vertexOrderIdentity,'surfaceTemplate',geometry.surfaceTemplate, ...
                    'surfaceHemisphere',geometry.surfaceHemisphere);
            % nm2-allow: Results Viewer materialization boundary converts failure into the returned diagnostic payload
            catch ME
                payload.ok = false;
                payload.message = sprintf('%s: %s',ME.identifier,ME.message);
                payload.diagnostics = NMImagingContractTools.diagnostic( ...
                    'error','surface_workspace_failure','NMResultsViewerSurfaceTools.buildWorkspace', ...
                    payload.message,'',ME);
            end
        end

        function payload = buildFeatureResource(NM, req, tmpDir, inspection, context, diagnostics)
            % buildFeatureResource  Materialize only mutable vertex feature assets for a resident surface workspace.
            %
            % Purpose:
            %   Resolve a new measure selection without revalidating/repackaging unchanged surface geometry.
            %
            % Inputs:
            %   NM and canonical Feature Inspection selection; the imaging request (NMResultsViewerImagingTools.imagingRequest)
            %   carrying the resident surface geometry/topology/vertex-order identities and vertex count;
            %   browser-session tmpDir; optional metadata/context.
            %
            % Outputs:
            %   NMImagingFeatureResourcePayload containing only overlay/support transport assets plus scientific
            %   selection metadata and the exact resident-geometry contract that was validated.
            %
            % Authority and flow:
            %   Feature vectors remain owned by NMResultsViewerTools. Native vertex geometry identity is validated
            %   against persisted DataIO identity; canonical ROI surfaces continue to expand only through provenance
            %   annotation membership. No mesh is written or returned by this operation.
            %
            % Materialization and performance:
            %   Native vertex payloads read no geometry files and write only feature/support arrays. Canonical ROI
            %   payloads may read the authoritative annotation/geometry needed for exact ROI expansion, but still do
            %   not package geometry. This operation is safe on retained measure-switch paths, not camera/navigation.
            %
            % Failure semantics:
            %   Any authoritative geometry identity disagreement sets requiresWorkspace=true so the caller may execute the
            %   full authoritative workspace lifecycle; scientific mismatches otherwise fail explicitly.
            payload = struct('schema','NMImagingFeatureResourcePayload','schemaVersion',1, ...
                'contractVersion','NM-RESULTS-IMAGING-FEATURE-RESOURCE-V1','ok',false,'requiresWorkspace',false, ...
                'message','','sourceDomain','surface','scientificContractVersion','', ...
                'scientificAnnotation',struct(),'resolvedSelection',struct(),'analysisIndex',0,'targetIndex',0, ...
                'resultTargetIndex',NaN,'classifierIndex',0,'selectedFeatureContextId','', ...
                'contentId','','overlays',struct([]),'support',struct(),'nativeFeatureSampling',struct(), ...
                'canonicalROI',NMDataIOROIProvenanceTools.viewerMaterialization(), ...
                'capabilities',struct(),'residentContract',struct(),'diagnostics',diagnostics);
            try
                adapterSelection = NMResultsViewerFeatureVectorAuthority.selection(req,inspection);
                requestedIds = adapterSelection.measureIds;
                resolvedVectors = cell(1,numel(requestedIds));
                for ii=1:numel(requestedIds)
                    vectorSpec=req; vectorSpec.measureId=requestedIds{ii}; vectorSpec.measureIds=[];
                    resolvedVectors{ii}=NMResultsViewerFeatureVectorAuthority.vector(NM,vectorSpec,requestedIds{ii},inspection);
                    if ~resolvedVectors{ii}.ok
                        error('NMResultsViewerSurfaceTools:SurfaceVectorUnavailable','%s',resolvedVectors{ii}.message);
                    end
                end
                firstVector=resolvedVectors{1}; canonicalContext=firstVector.context;
                if ~isempty(context) && ~strcmp(context.contextId, ...
                        canonicalContext.contextId)
                    error('NMResultsViewerSurfaceTools:SurfaceContextMismatch','Supplied surface context does not match the canonical context.');
                end
                context=canonicalContext; contextId=context.contextId;
                featureKind=context.featureKind;
                isCanonicalROI=strcmp(featureKind,'roi');
                if ~isCanonicalROI && ~strcmp(featureKind,'surface_vertex')
                    error('NMResultsViewerSurfaceTools:NotSurfaceContext','Surface feature resources require surface_vertex or canonical surface ROI provenance.');
                end
                sourceVectors=resolvedVectors; varind=context.varind;
                projection=struct(); descriptor=struct();
                if isCanonicalROI
                    if ~strcmp(context.roiSpatialDomain,'surface')
                        error('NMResultsViewerSurfaceTools:ROISurfaceDomainMismatch','Canonical ROI feature resources require surface provenance.');
                    end
                    descriptor=NMResultsViewerImagingDescriptorAdapter.resolve(NM,varind,struct());
                    if ~descriptor.ok || ~descriptor.roiProvenance.ok
                        error('NMResultsViewerSurfaceTools:ROIProvenanceUnavailable','Canonical surface ROI provenance is unavailable for modality %d.',varind);
                    end
                    projection=NMDataIOROIProvenanceTools.spatialProjection(descriptor.roiProvenance);
                    [geometry,annotationParts,~,~]=NMResultsViewerSurfaceTools.resolveCanonicalROISurfaceGeometry(descriptor.roiProvenance);
                    for ii=1:numel(resolvedVectors)
                        roiValues=double(resolvedVectors{ii}.values(:));
                        if numel(roiValues)~=descriptor.roiProvenance.nColumns
                            error('NMResultsViewerSurfaceTools:ROIFeatureCountMismatch','Measure %s does not match canonical ROI column count.',requestedIds{ii});
                        end
                        resolvedVectors{ii}.values=NMResultsViewerSurfaceTools.expandCanonicalROISurfaceValues( ...
                            descriptor.roiProvenance,roiValues,annotationParts,geometry.vertexCount);
                    end
                    geometryId=geometry.native.geometryId; topologyId=geometry.topologyIdentity;
                    vertexOrderId=geometry.vertexOrderIdentity; nVertices=geometry.vertexCount;
                else
                    descriptorFields=NMResultsViewerSurfaceTools.descriptorFields(NM,varind);
                    geometryId=descriptorFields.nativeGeometryIdentity; topologyId=descriptorFields.topologyIdentity;
                    vertexOrderId=descriptorFields.vertexOrderIdentity; nVertices=numel(firstVector.values);
                    if isempty(geometryId)||isempty(topologyId)||isempty(vertexOrderId)
                        payload.ok=true; payload.requiresWorkspace=true; payload.message='Persisted surface geometry identity is unavailable for retained feature replacement.'; return;
                    end
                end
                residentVertices=req.residentSurfaceVertexCount;
                residentGeometry=req.residentSurfaceGeometryIdentity;
                residentTopology=req.residentSurfaceTopologyIdentity;
                residentOrder=req.residentSurfaceVertexOrderIdentity;
                if ~isfinite(residentVertices)||residentVertices~=nVertices||~strcmp(residentGeometry,geometryId)|| ...
                        ~strcmp(residentTopology,topologyId)||~strcmp(residentOrder,vertexOrderId)
                    payload.ok=true; payload.requiresWorkspace=true; payload.message='The authoritative surface geometry differs from the resident workspace.'; return;
                end

                overlayTemplate=struct('measureId','','label','','sourceField','','valuePolarity','signed', ...
                    'valueRange',[NaN NaN],'displayDefaults',struct(),'displayContentHash','','data',[]);
                overlayData=repmat(overlayTemplate,1,numel(requestedIds)); support=false(nVertices,1);
                for ii=1:numel(requestedIds)
                    values=single(resolvedVectors{ii}.values(:));
                    if numel(values)~=nVertices
                        error('NMResultsViewerSurfaceTools:SurfaceFeatureCountMismatch','Measure %s has %d values; expected %d vertices.',requestedIds{ii},numel(values),nVertices);
                    end
                    support=support|isfinite(values); vector=sourceVectors{ii}; sourceValues=double(vector.values(:));
                    finiteValues=sourceValues(isfinite(sourceValues)); range=[NaN NaN];
                    if ~isempty(finiteValues), range=[min(finiteValues) max(finiteValues)]; end
                    overlayData(ii).measureId=vector.measure.measureId;
                    overlayData(ii).label=vector.measure.label;
                    overlayData(ii).sourceField=vector.measure.sourceField;
                    overlayData(ii).valuePolarity=vector.measure.valuePolarity;
                    displayDefaults=NMImagingColorMapping.defaults(sourceValues,vector.measure);
                    overlayData(ii).valueRange=displayDefaults.valueRange;
                    overlayData(ii).displayDefaults=displayDefaults;
                    overlayData(ii).displayContentHash=NMImagingContentIdentity.hashArray(values,'single');
                    overlayData(ii).data=values;
                end
                identityParts={'NM-RESULTS-SURFACE-STAGE4B-V2',['context=' contextId], ...
                    ['measures=' strjoin(requestedIds,'>')],['geometry=' geometryId],['topology=' topologyId], ...
                    ['vertexOrder=' vertexOrderId],['overlayHashes=' strjoin({overlayData.displayContentHash},'>')]};
                if isCanonicalROI, identityParts{end+1}=['roiSpatial=' projection.spatialReferenceIdentity]; end %#ok<AGROW>
                contentId=NMImagingContentIdentity.hashText(strjoin(identityParts,'|'));
                assets=NMImagingAssetCache.writeFeatureResource(tmpDir,contentId,overlayData,struct(),support,false);
                browserOverlays=rmfield(overlayData,{'data','displayContentHash'});
                for ii=1:numel(browserOverlays)
                    hit=find(strcmp({assets.overlayAssets.measureId},browserOverlays(ii).measureId),1,'first');
                    browserOverlays(ii).url=assets.overlayAssets(hit).url; browserOverlays(ii).dataType='float32';
                    browserOverlays(ii).elementCount=nVertices; browserOverlays(ii).contentHash=assets.overlayAssets(hit).contentHash;
                end
                payload.ok=true; payload.message=sprintf('Prepared %d retained surface feature resource(s).',numel(browserOverlays));
                payload.scientificContractVersion=firstVector.scientificContractVersion;
                payload.scientificAnnotation=firstVector.scientificAnnotation; payload.resolvedSelection=firstVector.resolvedSelection;
                payload.analysisIndex=firstVector.analysisIndex; payload.targetIndex=firstVector.targetIndex;
                payload.resultTargetIndex=firstVector.resultTargetIndex; payload.classifierIndex=firstVector.classifierIndex;
                payload.selectedFeatureContextId=contextId; payload.contentId=contentId; payload.overlays=browserOverlays;
                payload.support=struct('url',assets.supportAsset.url,'dataType','uint8','elementCount',nVertices, ...
                    'contentHash',assets.supportAsset.contentHash);
                payload.capabilities=NMResultsViewerSurfaceTools.surfaceCapabilities(isCanonicalROI);
                if isCanonicalROI
                    canonicalROIValues=cellfun(@(vector)double(vector.values(:)'),sourceVectors,'UniformOutput',false);
                    payload.canonicalROI=NMDataIOROIProvenanceTools.viewerMaterialization(descriptor.roiProvenance,requestedIds,canonicalROIValues);
                end
                payload.residentContract=struct('sourceDomain','surface','featureContextId',contextId, ...
                    'vertexCount',nVertices,'geometryIdentity',geometryId,'topologyIdentity',topologyId, ...
                    'vertexOrderIdentity',vertexOrderId);
            % nm2-allow: Results Viewer feature-resource boundary converts failure into the returned diagnostic payload
            catch ME
                payload.ok=false; payload.message=sprintf('%s: %s',ME.identifier,ME.message);
                payload.diagnostics=NMImagingContractTools.diagnostic('error','surface_feature_resource_failure', ...
                    'NMResultsViewerSurfaceTools.buildFeatureResource',payload.message,'',ME);
            end
        end

        function payload = loadAnnotationAtlas(NM, spec, tmpDir)
            payload = struct('schema','NMSurfaceAtlasPayload','schemaVersion',1, ...
                'contractVersion','NM-RESULTS-SURFACE-ATLAS-V1','ok',false,'message','', ...
                'atlasId','','selectionId','surface_annot_file','label','','selectedPath','','lhPath','','rhPath','', ...
                'url','','dataType','uint32','elementCount',0,'contentHash','', ...
                'roiLabels',struct(),'roiRecords',struct([]),'partVertexOffsets',[], ...
                'alignmentAudit',struct(),'geometryIdentity','','topologyIdentity','','vertexOrderIdentity','');
            try
                req = NMResultsViewerImagingTools.imagingRequest(spec);
                selectedPath = req.surfaceAtlasPath;
                [lhPath,rhPath,atlasStem] = NMResultsViewerSurfaceTools.resolveAnnotationPair(selectedPath);
                varind = req.varind;
                expectedVertices = req.surfaceVertexCount;
                geometry = NMResultsViewerSurfaceTools.resolveGeometry(NM,varind,expectedVertices);
                [lhLabels,lhTable] = NMResultsViewerSurfaceTools.readAnnotation(lhPath);
                [rhLabels,rhTable] = NMResultsViewerSurfaceTools.readAnnotation(rhPath);
                hemisphereMap = NMResultsViewerSurfaceTools.resolveAtlasHemisphereMap( ...
                    geometry,numel(lhLabels),numel(rhLabels));
                [lhMapped,lhRecords,nextId] = NMResultsViewerSurfaceTools.mapAnnotationLabels(lhLabels,lhTable,'left',1);
                [rhMapped,rhRecords,~] = NMResultsViewerSurfaceTools.mapAnnotationLabels(rhLabels,rhTable,'right',nextId);
                combined = zeros(geometry.vertexCount,1,'uint32');
                combined(hemisphereMap.leftVertexIndices) = lhMapped;
                combined(hemisphereMap.rightVertexIndices) = rhMapped;
                offsets = [0 numel(lhMapped) numel(lhMapped)+numel(rhMapped)];
                roiRecords = [lhRecords(:);rhRecords(:)];
                labelsStruct = struct();
                for ii=1:numel(roiRecords)
                    labelsStruct.(sprintf('roi_%d',roiRecords(ii).roiCode)) = roiRecords(ii).name;
                end
                atlasIdentity = NMImagingContentIdentity.hashText(strjoin({ ...
                    'NM-RESULTS-SURFACE-ATLAS-V1', ...
                    NMImagingContentIdentity.fileFingerprint(lhPath), ...
                    NMImagingContentIdentity.fileFingerprint(rhPath), ...
                    geometry.topologyIdentity,geometry.vertexOrderIdentity},'|'));
                asset = NMResultsViewerSurfaceTools.writeAtlasAsset(tmpDir,atlasIdentity,combined);
                payload.ok = true;
                payload.message = sprintf('Loaded bilateral surface atlas %s with %d ROI labels.',atlasStem,numel(roiRecords));
                payload.atlasId = ['surface_annot_' atlasIdentity];
                payload.label = atlasStem;
                [~,selectedName,selectedExt] = fileparts(selectedPath);
                if startsWith(lower([selectedName selectedExt]),'lh.')
                    payload.selectedPath = lhPath;
                else
                    payload.selectedPath = rhPath;
                end
                payload.lhPath = lhPath;
                payload.rhPath = rhPath;
                payload.url = asset.url;
                payload.elementCount = numel(combined);
                payload.contentHash = asset.contentHash;
                payload.roiLabels = labelsStruct;
                payload.roiRecords = roiRecords;
                payload.partVertexOffsets = offsets;
                payload.alignmentAudit = hemisphereMap.alignmentAudit;
                payload.geometryIdentity = geometry.native.geometryId;
                payload.topologyIdentity = geometry.topologyIdentity;
                payload.vertexOrderIdentity = geometry.vertexOrderIdentity;
            % nm2-allow: user-selected annotation boundary reports invalid external atlas resources in the payload
            catch ME
                payload.ok = false;
                payload.message = sprintf('%s: %s',ME.identifier,ME.message);
            end
        end

        function availability = catalogueAvailability(NM,varind,nFeatures)
            availability = struct('enabled',false,'disabledReason','','nativeFile','','inflatedDeclared',false);
            try
                descriptor = NMResultsViewerSurfaceTools.descriptorFields(NM,varind);
                availability.nativeFile = descriptor.nativeFile;
                availability.inflatedDeclared = ~isempty(descriptor.inflatedFile);
                if isempty(descriptor.nativeFile)
                    availability.disabledReason = 'No authoritative native surface geometry is configured for this modality.';
                    return;
                end
                files = NMDataIOSurfaceTools.splitSurfaceFileList(descriptor.nativeFile);
                % nm2-allow: surface catalogue boundary verifies persisted external geometry resources
                missing = files(cellfun(@(p)exist(p,'file')~=2,files));
                if ~isempty(missing)
                    availability.disabledReason = sprintf('Authoritative native surface geometry is unavailable: %s',missing{1});
                    return;
                end
                if ~(isfinite(double(nFeatures)) && double(nFeatures)>0)
                    availability.disabledReason = 'The surface feature source declares no vertices.';
                    return;
                end
                availability.enabled = true;
            % nm2-allow: catalogue admission boundary reports unavailable external geometry as disabled capability
            catch ME
                availability.disabledReason = ME.message;
            end
        end
    end

    methods (Static, Access=private)
        function payload = workspaceTemplate()
            payload = struct('schema','NMImagingWorkspacePayload','schemaVersion',3, ...
                'contractVersion','NM-RESULTS-SURFACE-STAGE4B-V1','ok',false,'message','', ...
                'scientificContractVersion','','scientificAnnotation',struct(),'resolvedSelection',struct(), ...
                'contentId','','sourceDomain','surface','analysisIndex',0,'targetIndex',0, ...
                'resultTargetIndex',NaN,'classifierIndex',0,'resultSourceId','', ...
                'selectedFeatureContextId','','surfaceModalityIndex',0,'displayGridPolicy','surface_native', ...
                'dimensions',[0 0 0],'spatialReference',struct(),'planeConvention',struct(), ...
                'templateCatalogue',struct([]),'selectedTemplate',struct('available',false), ...
                'structural',struct(),'support',struct(),'nativeFeatureSampling',struct('available',false), ...
                'overlays',struct([]),'canonicalROI',NMDataIOROIProvenanceTools.viewerMaterialization(), ...
                'surface',struct(),'atlasCatalogue',struct([]), ...
                'selectedAtlas',NMResultsViewerSurfaceTools.emptySelectedAtlas(), ...
                'capabilities',NMResultsViewerSurfaceTools.surfaceCapabilities(false), ...
                'initialVoxel',[NaN NaN NaN],'initialWorldMm',[NaN NaN NaN], ...
                'layoutProfile',NMImagingContractTools.layoutProfileTemplate(), ...
                'alignmentAudit',struct('feature',struct(),'atlas',struct()), ...
                'diagnostics',NMImagingContractTools.diagnosticTemplate([]));
        end

        function selected = emptySelectedAtlas()
            selected = struct('available',false,'atlasId','','selectionId','surface_annot_file','label','','url','', ...
                'dataType','uint32','elementCount',0,'contentHash','', ...
                'roiLabels',struct(),'roiRecords',struct([]),'labelMessage','', ...
                'labelProvenance','viewer_selected_freesurfer_annot_pair', ...
                'alignmentAudit',struct(),'selectedPath','','lhPath','','rhPath','');
        end

        function capabilities = surfaceCapabilities(canonicalROI)
            % surfaceCapabilities  Shared surface-viewer capability profile derived from scientific provenance.
            % Pure O(1) metadata construction; no file IO or spatial materialization. Safe on interactive paths.
            canonicalROI=logical(canonicalROI);
            capabilities = struct('sourceDomain','surface','canonicalROI',canonicalROI,'orthogonal2D',false, ...
                'sliceMontage',false,'surface3D',true,'volumeRaycast',false,'volumeFeatureControls',false, ...
                'volumeBoundarySmoothing',false,'anatomySurfaceDepth',false, ...
                'surfaceProjectionControls',false,'nativeInflatedGeometry',~canonicalROI, ...
                'atlasFileSelection',~canonicalROI,'roiTable',~canonicalROI,'roiSilhouette',true, ...
                'roiMapper',true,'montage3D',true,'videoMaker',true,'clipping',true, ...
                'featureSelection',true,'featureInterpolation',false,'featureSmoothing',~canonicalROI, ...
                'editableColorbar',true,'thresholds',true,'opacity',true,'camera',true,'extrema',true,'picking',true);
        end

        function [geometry,annotationParts,atlasCodes,annotationPaths] = resolveCanonicalROISurfaceGeometry(roi)
            % resolveCanonicalROISurfaceGeometry  Materialize the exact annotation + display-mesh spatial reference for surface ROI data.
            %
            % ROI identity is read only from the canonical annotation labels. Meshes provide coordinates/faces only.
            % Reads one annotation and one mesh per used hemisphere and scans each vertex once. This function belongs
            % only on explicit workspace materialization paths and is not safe for interactive navigation.
            roi=NMDataIOROIProvenanceTools.validate(roi,[]);
            if ~roi.ok, error('NMResultsViewerSurfaceTools:ROIProvenanceInvalid','%s',roi.message); end
            ref=NMDataIOROIProvenanceTools.spatialReference(roi,'surface_annotation');
            annotByHemi=ref.annotationFilesByHemisphere;
            geomByHemi=ref.surfaceGeometryFilesByHemisphere;
            used=unique(roi.hemisphere,'stable');
            vertices=single([]);indices=uint32([]);atlasCodes=uint32([]);
            annotationParts=repmat(struct('hemisphere','','labels',[],'vertexOffset',0,'vertexCount',0),1,0);
            parts=repmat(struct('partIndex',0,'hemisphere','','vertexOffset',0,'vertexCount',0,'faceCount',0,'file',''),1,0);
            annotationPaths=struct('lh','','rh','');
            geometryPaths=cell(1,0);annotationFileList=cell(1,0);offset=0;
            for hh=1:numel(used)
                token=used{hh};
                if ~ismember(token,{'lh','rh'})
                    error('NMResultsViewerSurfaceTools:ROISurfaceHemisphereInvalid','Unsupported canonical surface ROI hemisphere: %s.',token);
                end
                annotFiles=annotByHemi.(token);
                geomFiles=geomByHemi.(token);
                % nm2-allow: validated ROI spatial-reference boundary requires one file per used hemisphere
                if numel(annotFiles)~=1||numel(geomFiles)~=1
                    error('NMResultsViewerSurfaceTools:ROISurfaceDisplayReferenceAmbiguous', ...
                        'Canonical %s ROI provenance requires exactly one annotation and one display mesh.',upper(token));
                end
                % nm2-allow: canonical ROI materialization boundary verifies producer-owned annotation and mesh resources
                if exist(annotFiles{1},'file')~=2||exist(geomFiles{1},'file')~=2
                    error('NMResultsViewerSurfaceTools:ROISurfaceDisplayReferenceMissing', ...
                        'Canonical %s annotation/display-mesh file is unavailable.',upper(token));
                end
                [labels,~]=NMDataIOSurfaceTools.readAnnotationLabels(annotFiles{1});
                [v,f]=NMDataIOSurfaceTools.readSurfaceGeometry(geomFiles{1});
                labels=double(labels(:));v=single(v);f=double(f);
                if numel(labels)~=size(v,1)
                    error('NMResultsViewerSurfaceTools:ROISurfaceVertexMismatch', ...
                        '%s annotation has %g labels but its display mesh has %g vertices.',upper(token),numel(labels),size(v,1));
                end
                canonicalColumns=NMDataIOROIProvenanceTools.expandSurfaceValues(roi,1:roi.nColumns,token,labels);
                localAtlas=zeros(numel(labels),1,'uint32');finiteMask=isfinite(canonicalColumns);
                localAtlas(finiteMask)=uint32(canonicalColumns(finiteMask));
                if any(f(:)<0)||any(f(:)>=size(v,1))
                    error('NMResultsViewerSurfaceTools:ROISurfaceFaceIndexOutOfRange','%s display mesh contains an out-of-range face index.',upper(token));
                end
                combinedFaces=uint32(f+offset);
                vertices=[vertices;v]; %#ok<AGROW>
                indices=[indices;reshape(combinedFaces.',[],1)]; %#ok<AGROW>
                atlasCodes=[atlasCodes;localAtlas]; %#ok<AGROW>
                browserHemi='left';if strcmp(token,'rh'),browserHemi='right';end
                annotationParts(end+1)=struct('hemisphere',token,'labels',labels,'vertexOffset',offset,'vertexCount',numel(labels)); %#ok<AGROW>
                parts(end+1)=struct('partIndex',hh,'hemisphere',browserHemi,'vertexOffset',offset, ...
                    'vertexCount',size(v,1),'faceCount',size(f,1),'file',geomFiles{1}); %#ok<AGROW>
                annotationPaths.(token)=annotFiles{1};
                geometryPaths{end+1}=geomFiles{1};annotationFileList{end+1}=annotFiles{1}; %#ok<AGROW>
                offset=offset+size(v,1);
            end
            geomIdentity=NMImagingContentIdentity.hashText(strjoin(cellfun(@(f)NMImagingContentIdentity.fileFingerprint(f),geometryPaths,'UniformOutput',false),'|'));
            topologyIdentity=NMImagingContentIdentity.hashArray(indices,'uint32');
            vertexOrderIdentity=NMImagingContentIdentity.hashArray(vertices,'single');
            inflated=struct('declared',false,'available',false,'geometryId','','vertices',single([]), ...
                'bounds',struct(),'disabledReason','Canonical surface ROI provenance defines only its explicit native display mesh.');
            surfaceHemisphere='bilateral';if numel(used)==1,surfaceHemisphere=used{1};end
            geometry=struct('surfaceTemplate','canonical_roi_provenance','surfaceHemisphere',surfaceHemisphere, ...
                'vertexCount',size(vertices,1),'faceCount',numel(indices)/3,'partCount',numel(parts),'parts',parts, ...
                'indices',indices,'topologyIdentity',topologyIdentity,'vertexOrderIdentity',vertexOrderIdentity, ...
                'native',struct('available',true,'geometryId',geomIdentity,'vertices',vertices,'bounds',NMResultsViewerSurfaceTools.bounds(vertices)), ...
                'inflated',inflated);
        end

        function expanded = expandCanonicalROISurfaceValues(roi,roiValues,annotationParts,totalVertices)
            % Pure O(V+R) exact expansion over resident annotation labels; performs no IO and no smoothing.
            expanded=nan(totalVertices,1);
            for ii=1:numel(annotationParts)
                part=annotationParts(ii);
                values=NMDataIOROIProvenanceTools.expandSurfaceValues(roi,roiValues,part.hemisphere,part.labels);
                idx=part.vertexOffset+(1:part.vertexCount);
                expanded(idx)=values;
            end
        end

        function selected = canonicalROISurfaceAtlas(tmpDir,roi,geometry,atlasCodes,annotationPaths,spatialIdentity)
            % Materialize the provenance annotation as the viewer's fixed atlas. No user atlas substitution is permitted.
            identity=NMImagingContentIdentity.hashText(strjoin({'canonical_roi_surface_atlas',spatialIdentity,geometry.topologyIdentity,geometry.vertexOrderIdentity},'|'));
            asset=NMResultsViewerSurfaceTools.writeAtlasAsset(tmpDir,identity,atlasCodes);
            labels=struct();
            recordTemplate=struct('roiCode',0,'name','','hemisphere','','sourceStructureIndex',0,'sourceAnnotationCode',0,'rgba',[0 0 0 0]);
            records=repmat(recordTemplate,roi.nColumns,1);
            for ii=1:roi.nColumns
                code=ii;labels.(sprintf('roi_%d',code))=roi.roiNames{ii};
                hemi=roi.hemisphere{ii};browserHemi='left';if strcmp(hemi,'rh'),browserHemi='right';end
                records(ii)=struct('roiCode',code,'name',roi.roiNames{ii},'hemisphere',browserHemi, ...
                    'sourceStructureIndex',0,'sourceAnnotationCode',double(roi.roiIDs(ii)),'rgba',[0 0 0 0]);
            end
            lh=annotationPaths.lh;rh=annotationPaths.rh;
            selected=NMResultsViewerSurfaceTools.emptySelectedAtlas();
            selected.available=true;selected.atlasId=['canonical_roi_' identity];selected.selectionId='canonical_roi_provenance';
            selected.label='Provenance annotation';selected.url=asset.url;selected.elementCount=numel(atlasCodes);selected.contentHash=asset.contentHash;
            selected.roiLabels=labels;selected.roiRecords=records;selected.labelMessage='Canonical ROI annotation loaded from scientific provenance.';
            selected.labelProvenance='canonical_roi_provenance';selected.selectedPath=lh;if isempty(selected.selectedPath),selected.selectedPath=rh;end
            selected.lhPath=lh;selected.rhPath=rh;
        end

        function geometry = resolveGeometry(NM,varind,expectedVertices)
            descriptor = NMResultsViewerSurfaceTools.descriptorFields(NM,varind);
            if isempty(descriptor.nativeFile)
                error('NMResultsViewerSurfaceTools:SurfaceGeometryUnavailable', ...
                    'No authoritative native surface geometry is configured for modality %d.',varind);
            end
            options = struct('surfaceTemplate',descriptor.surfaceTemplate, ...
                'surfaceHemisphere',descriptor.surfaceHemisphere);

            % Native geometry is authoritative and must always validate. The
            % optional inflated variant is validated separately so that a
            % missing or stale inflated file cannot suppress a valid native
            % surface.
            nativeContract = NMDataIOSurfaceTools.validateSurfaceGeometryContract( ...
                descriptor.nativeFile,'',expectedVertices,options);
            NMResultsViewerSurfaceTools.assertPersistedIdentity( ...
                'native geometry',descriptor.nativeGeometryIdentity,nativeContract.nativeGeometryIdentity);
            NMResultsViewerSurfaceTools.assertPersistedIdentity( ...
                'topology',descriptor.topologyIdentity,nativeContract.topologyIdentity);
            NMResultsViewerSurfaceTools.assertPersistedIdentity( ...
                'vertex order',descriptor.vertexOrderIdentity,nativeContract.vertexOrderIdentity);
            [nativeVertices,indices,parts,nativeBounds] = ...
                NMResultsViewerSurfaceTools.combineGeometry(nativeContract.nativeFiles,nativeContract.parts);

            inflated = struct('declared',~isempty(descriptor.inflatedFile),'available',false, ...
                'disabledReason','','geometryId','','vertices',single([]),'bounds',struct());
            if inflated.declared
                if ~descriptor.inflatedValidated
                    inflated.disabledReason = ...
                        'Inflated geometry is declared but Stage 4A correspondence validation is absent.';
                else
                    try
                        inflatedContract = NMDataIOSurfaceTools.validateSurfaceGeometryContract( ...
                            descriptor.nativeFile,descriptor.inflatedFile,expectedVertices,options);
                        NMResultsViewerSurfaceTools.assertPersistedIdentity( ...
                            'inflated geometry',descriptor.inflatedGeometryIdentity, ...
                            inflatedContract.inflatedGeometryIdentity);
                        NMResultsViewerSurfaceTools.assertPersistedIdentity( ...
                            'inflated topology',descriptor.topologyIdentity, ...
                            inflatedContract.topologyIdentity);
                        NMResultsViewerSurfaceTools.assertPersistedIdentity( ...
                            'inflated vertex order',descriptor.vertexOrderIdentity, ...
                            inflatedContract.vertexOrderIdentity);
                        if ~inflatedContract.inflatedValidated
                            error('NMResultsViewerSurfaceTools:InflatedCorrespondenceUnvalidated', ...
                                'Inflated geometry correspondence was not validated.');
                        end
                        [inflatedVertices,inflatedIndices,~,inflatedBounds] = ...
                            NMResultsViewerSurfaceTools.combineGeometry( ...
                            inflatedContract.inflatedFiles,inflatedContract.parts);
                        if ~isequal(indices,inflatedIndices)
                            error('NMResultsViewerSurfaceTools:InflatedTopologyMismatch', ...
                                'Validated inflated geometry did not preserve the native indexed triangle array.');
                        end
                        inflated.available = true;
                        inflated.geometryId = inflatedContract.inflatedGeometryIdentity;
                        inflated.vertices = inflatedVertices;
                        inflated.bounds = inflatedBounds;
                    % nm2-allow: optional inflated-geometry resource failure disables only that optional representation
                    catch ME
                        inflated.disabledReason = sprintf( ...
                            'Inflated geometry is unavailable: %s',ME.message);
                    end
                end
            end
            geometry = struct('surfaceTemplate',descriptor.surfaceTemplate, ...
                'surfaceHemisphere',descriptor.surfaceHemisphere, ...
                'vertexCount',nativeContract.vertexCount,'faceCount',nativeContract.faceCount, ...
                'partCount',nativeContract.partCount,'parts',parts,'indices',indices, ...
                'topologyIdentity',nativeContract.topologyIdentity, ...
                'vertexOrderIdentity',nativeContract.vertexOrderIdentity, ...
                'native',struct('available',true,'geometryId',nativeContract.nativeGeometryIdentity, ...
                    'vertices',nativeVertices,'bounds',nativeBounds), ...
                'inflated',inflated);
        end

        function descriptor = descriptorFields(NM,varind)
            % descriptorFields  Project the persisted DataIO surface state into the viewer geometry contract.
            dd = NM.datadescriptor{varind};
            state = NMDataIOStateTools.ioToState(dd.input_settings);
            img = state.image;
            descriptor = struct('nativeFile',img.surfaceGeometryFile, ...
                'inflatedFile',img.surfaceInflatedGeometryFile, ...
                'surfaceTemplate',img.surfaceTemplate, ...
                'surfaceHemisphere',img.surfaceHemisphere, ...
                'inflatedValidated',img.surfaceInflatedValidated, ...
                'nativeGeometryIdentity',img.surfaceGeometryIdentity, ...
                'inflatedGeometryIdentity',img.surfaceInflatedGeometryIdentity, ...
                'topologyIdentity',img.surfaceTopologyIdentity, ...
                'vertexOrderIdentity',img.surfaceVertexOrderIdentity);
            if isempty(descriptor.nativeFile) && ~isempty(NM.brainmask{varind})
                % NM 1.4 TransferModality2NM persists the selected surface geometry in NM.brainmask.
                descriptor.nativeFile = strjoin(NMDataIOSurfaceTools.splitSurfaceFileList(NM.brainmask{varind}),';');
            end
        end

        function mapping = resolveAtlasHemisphereMap(geometry,lhCount,rhCount)
            % Resolve one logical bilateral atlas onto the authoritative mesh.
            % Two-file geometry uses its persisted part offsets directly. A
            % single combined geometry file is accepted only when indexed
            % topology proves that it contains exactly two disconnected,
            % contiguous vertex components whose x centroids distinguish the
            % hemispheres. This remains viewer-local and does not extend DataIO.
            lhCount = double(lhCount);
            rhCount = double(rhCount);
            if any(~isfinite([lhCount rhCount])) || any([lhCount rhCount]<1) || ...
                    any([lhCount rhCount]~=round([lhCount rhCount]))
                error('NMResultsViewerSurfaceTools:AtlasVertexCountInvalid', ...
                    'Surface annotation vertex counts must be positive integers.');
            end
            if lhCount+rhCount ~= geometry.vertexCount
                error('NMResultsViewerSurfaceTools:AtlasBilateralVertexMismatch', ...
                    ['The annotation pair contains %g vertices (%g left + %g right), ', ...
                     'but the authoritative surface contains %g vertices.'], ...
                    lhCount+rhCount,lhCount,rhCount,geometry.vertexCount);
            end

            mode = '';
            componentCount = 2;
            leftPartIndex = 0;
            rightPartIndex = 0;
            if geometry.partCount == 2
                partOrder = {geometry.parts.hemisphere};
                leftPartIndex = find(strcmp(partOrder,'left'),1,'first');
                rightPartIndex = find(strcmp(partOrder,'right'),1,'first');
                if isempty(leftPartIndex) || isempty(rightPartIndex) || ...
                        leftPartIndex == rightPartIndex
                    error('NMResultsViewerSurfaceTools:AtlasHemisphereOrderUnknown', ...
                        'The authoritative geometry does not declare one left and one right hemisphere part.');
                end
                leftPart = geometry.parts(leftPartIndex);
                rightPart = geometry.parts(rightPartIndex);
                leftVertexIndices = double(leftPart.vertexOffset)+(1:double(leftPart.vertexCount));
                rightVertexIndices = double(rightPart.vertexOffset)+(1:double(rightPart.vertexCount));
                mode = 'authoritative_geometry_parts';
            elseif geometry.partCount == 1
                [componentIds,componentSizes] = NMResultsViewerSurfaceTools.indexedSurfaceComponents( ...
                    geometry.indices,geometry.vertexCount);
                componentCount = numel(componentSizes);
                if componentCount ~= 2
                    error('NMResultsViewerSurfaceTools:AtlasCombinedGeometryComponents', ...
                        ['A paired lh/rh annotation atlas requires either two authoritative geometry parts ', ...
                         'or one indexed mesh with exactly two disconnected components; %g components were found.'], ...
                        componentCount);
                end
                componentVertices = cell(1,2);
                componentCentroidX = zeros(1,2);
                for ii=1:2
                    componentVertices{ii} = find(componentIds==ii);
                    componentCentroidX(ii) = mean(double(geometry.native.vertices(componentVertices{ii},1)));
                end
                xSpan = double(max(geometry.native.vertices(:,1))-min(geometry.native.vertices(:,1)));
                minimumSeparation = max(1e-6,0.02*max(1,xSpan));
                if abs(diff(componentCentroidX)) <= minimumSeparation
                    error('NMResultsViewerSurfaceTools:AtlasHemisphereCentroidAmbiguous', ...
                        ['The two disconnected surface components cannot be assigned unambiguously to ', ...
                         'left and right hemispheres from their x-coordinate centroids.']);
                end
                [~,order] = sort(componentCentroidX,'ascend');
                leftVertexIndices = componentVertices{order(1)};
                rightVertexIndices = componentVertices{order(2)};
                NMResultsViewerSurfaceTools.assertContiguousAtlasOrder(leftVertexIndices,'left');
                NMResultsViewerSurfaceTools.assertContiguousAtlasOrder(rightVertexIndices,'right');
                mode = 'topology_recovered_combined_mesh';
            else
                error('NMResultsViewerSurfaceTools:AtlasRequiresBilateralGeometry', ...
                    ['A paired lh/rh annotation atlas requires two authoritative geometry parts or ', ...
                     'one recoverable bilateral indexed mesh; the geometry declares %g parts.'], ...
                    geometry.partCount);
            end

            leftVertexIndices = double(leftVertexIndices(:));
            rightVertexIndices = double(rightVertexIndices(:));
            if numel(leftVertexIndices) ~= lhCount
                error('NMResultsViewerSurfaceTools:AtlasLeftVertexMismatch', ...
                    'Left annotation contains %g labels, but the left surface component has %g vertices.', ...
                    lhCount,numel(leftVertexIndices));
            end
            if numel(rightVertexIndices) ~= rhCount
                error('NMResultsViewerSurfaceTools:AtlasRightVertexMismatch', ...
                    'Right annotation contains %g labels, but the right surface component has %g vertices.', ...
                    rhCount,numel(rightVertexIndices));
            end
            coveredVertexIndices = [leftVertexIndices;rightVertexIndices];
            NMResultsViewerSurfaceTools.assertAtlasHemisphereCoverage( ...
                coveredVertexIndices,geometry.vertexCount);
            leftCentroidX = mean(double(geometry.native.vertices(leftVertexIndices,1)));
            rightCentroidX = mean(double(geometry.native.vertices(rightVertexIndices,1)));
            if ~(leftCentroidX < rightCentroidX)
                error('NMResultsViewerSurfaceTools:AtlasHemisphereOrientation', ...
                    'Recovered left-hemisphere vertices must have a smaller x centroid than right-hemisphere vertices.');
            end
            mapping = struct('leftVertexIndices',leftVertexIndices, ...
                'rightVertexIndices',rightVertexIndices, ...
                'coveredVertexIndices',coveredVertexIndices, ...
                'alignmentAudit',struct('mode',mode,'componentCount',componentCount, ...
                    'leftPartIndex',leftPartIndex,'rightPartIndex',rightPartIndex, ...
                    'leftVertexCount',numel(leftVertexIndices), ...
                    'rightVertexCount',numel(rightVertexIndices), ...
                    'leftCentroidX',leftCentroidX,'rightCentroidX',rightCentroidX, ...
                    'leftVertexIndexRange',[min(leftVertexIndices) max(leftVertexIndices)], ...
                    'rightVertexIndexRange',[min(rightVertexIndices) max(rightVertexIndices)]));
        end

        function [componentIds,componentSizes] = indexedSurfaceComponents(indices,nVertices)
            nVertices = double(nVertices);
            flatIndices = double(indices(:));
            if mod(numel(flatIndices),3) ~= 0
                error('NMResultsViewerSurfaceTools:SurfaceTriangleIndexShape', ...
                    'The indexed surface triangle array must contain a multiple of three indices.');
            end
            faces = reshape(flatIndices,3,[]).'+1;
            if any(~isfinite(faces(:))) || any(faces(:)~=round(faces(:))) || ...
                    any(faces(:)<1) || any(faces(:)>nVertices)
                error('NMResultsViewerSurfaceTools:SurfaceFaceIndexOutOfRange', ...
                    'The indexed surface contains a face index outside the authoritative vertex range.');
            end
            from = [faces(:,1);faces(:,2);faces(:,3)];
            to = [faces(:,2);faces(:,3);faces(:,1)];
            identity = (1:nVertices).';
            adjacencyFrom = [from;to;identity];
            adjacencyTo = [to;from;identity];
            adjacency = sparse(adjacencyFrom,adjacencyTo, ...
                ones(numel(adjacencyFrom),1),nVertices,nVertices);
            [permutation,~,blockStarts,~] = dmperm(adjacency);
            componentSizes = diff(blockStarts);
            componentIds = zeros(nVertices,1,'uint32');
            for ii=1:numel(componentSizes)
                members = permutation(blockStarts(ii):blockStarts(ii+1)-1);
                componentIds(members) = uint32(ii);
            end
            if any(componentIds==0)
                error('NMResultsViewerSurfaceTools:SurfaceComponentCoverage', ...
                    'Indexed surface component recovery did not cover every authoritative vertex.');
            end
        end

        function assertContiguousAtlasOrder(vertexIndices,hemisphere)
            vertexIndices = sort(double(vertexIndices(:)));
            if isempty(vertexIndices) || any(diff(vertexIndices)~=1)
                error('NMResultsViewerSurfaceTools:AtlasVertexOrderUnverifiable', ...
                    ['The %s surface component is not stored as one contiguous vertex range. ', ...
                     'FreeSurfer annotation vertex order therefore cannot be verified.'],hemisphere);
            end
        end

        function assertAtlasHemisphereCoverage(vertexIndices,nVertices)
            vertexIndices = double(vertexIndices(:));
            nVertices = double(nVertices);
            if any(~isfinite(vertexIndices)) || any(vertexIndices~=round(vertexIndices)) || ...
                    any(vertexIndices<1) || any(vertexIndices>nVertices)
                error('NMResultsViewerSurfaceTools:AtlasVertexMapOutOfRange', ...
                    'Recovered annotation vertex maps contain indices outside the authoritative surface.');
            end
            % nm2-allow: surface topology validator requires exact one-to-one authoritative vertex coverage
            if numel(vertexIndices)~=nVertices || numel(unique(vertexIndices))~=nVertices || ...
                    ~isequal(sort(vertexIndices),(1:nVertices).')
                error('NMResultsViewerSurfaceTools:AtlasVertexMapCoverage', ...
                    'Recovered annotation vertex maps must cover every authoritative vertex exactly once.');
            end
        end

        function assertPersistedIdentity(label,persisted,resolved)
            
            if ~isempty(persisted) && ~strcmp(persisted,resolved)
                error('NMResultsViewerSurfaceTools:PersistedSurfaceIdentityMismatch', ...
                    'Persisted %s identity does not match the resolved authoritative geometry.',label);
            end
        end

        function [vertices,indices,parts,bounds] = combineGeometry(files,contractParts)
            vertices = single([]);
            indices = uint32([]);
            parts = repmat(struct('partIndex',0,'hemisphere','','vertexOffset',0, ...
                'vertexCount',0,'faceCount',0,'file',''),numel(files),1);
            offset = 0;
            for ii=1:numel(files)
                [v,f] = NMDataIOSurfaceTools.readSurfaceGeometry(files{ii});
                v = single(v);
                % readSurfaceGeometry already normalizes every part to
                % zero-based local indices. Apply only the bilateral vertex
                % offset here; a second -1 conversion corrupts topology and
                % underflows local vertex zero to uint32(4294967295).
                localFaces = double(f);
                if any(localFaces(:)<0) || any(localFaces(:)>=size(v,1))
                    error('NMResultsViewerSurfaceTools:SurfaceFaceIndexOutOfRange', ...
                        'Normalized surface faces are outside the local vertex range for %s.',files{ii});
                end
                f = uint32(localFaces+offset);
                vertices = [vertices;v]; %#ok<AGROW>
                % Browser mesh buffers are interleaved by triangle, whereas
                % MATLAB linear indexing is column-major. Transpose first so
                % fwrite/(:) emits [i1 i2 i3] for each indexed face.
                faceIndexColumn = reshape(f.',[],1);
                indices = [indices;faceIndexColumn]; %#ok<AGROW>
                hemi = contractParts(ii).hemisphere;
                parts(ii) = struct('partIndex',ii,'hemisphere',hemi,'vertexOffset',offset, ...
                    'vertexCount',size(v,1),'faceCount',size(f,1),'file',files{ii});
                offset = offset+size(v,1);
            end
            if ~isempty(indices)
                maximumIndex = double(max(indices));
                if maximumIndex >= offset
                    error('NMResultsViewerSurfaceTools:CombinedSurfaceFaceIndexOutOfRange', ...
                        'Combined surface face index %g exceeds the %g-vertex mesh.',maximumIndex,offset);
                end
            end
            bounds = NMResultsViewerSurfaceTools.bounds(vertices);
        end

        function out = bounds(vertices)
            lo = double(min(vertices,[],1)); hi = double(max(vertices,[],1));
            center = (lo+hi)/2;
            radius = max(sqrt(sum((double(vertices)-center).^2,2)));
            out = struct('min',lo,'max',hi,'center',center,'radius',radius);
        end

        function package = writeSurfacePackage(tmpDir,geometry,resolvedVectors)
            [assetDir,urlBase] = NMResultsViewerSurfaceTools.assetDirectory(tmpDir);
            measureIds = cellfun(@(vector)vector.measure.measureId, ...
                resolvedVectors,'UniformOutput',false);
            vectorHashes = cell(1,numel(resolvedVectors));
            vectors = cell(1,numel(resolvedVectors));
            for ii=1:numel(resolvedVectors)
                vectors{ii}=single(resolvedVectors{ii}.values(:));
                vectorHashes{ii}=NMImagingContentIdentity.hashArray(vectors{ii},'single');
            end
            tokenHash = NMImagingContentIdentity.hashText(strjoin([{geometry.native.geometryId,geometry.topologyIdentity},vectorHashes],'|'));
            token = ['surface_' tokenHash]; if numel(token)>100, token=token(1:100); end
            pkgDir = fullfile(assetDir,token);
            % nm2-allow: browser asset boundary creates the external cache directory when absent
            if exist(pkgDir,'dir')~=7, mkdir(pkgDir); end
            nativeName='geometry_native_vertices_f32.bin';indexName='geometry_indices_u32.bin';supportName='surface_support_u8.bin';
            NMResultsViewerSurfaceTools.writeBinary(fullfile(pkgDir,nativeName),single(geometry.native.vertices.'),'single');
            NMResultsViewerSurfaceTools.writeBinary(fullfile(pkgDir,indexName),uint32(geometry.indices(:)),'uint32');
            support=false(geometry.vertexCount,1);
            for jj=1:numel(vectors), support=support|isfinite(vectors{jj}); end
            support=uint8(support);
            NMResultsViewerSurfaceTools.writeBinary(fullfile(pkgDir,supportName),support,'uint8');
            inflatedUrl='';
            if geometry.inflated.available
                inflatedName='geometry_inflated_vertices_f32.bin';
                NMResultsViewerSurfaceTools.writeBinary(fullfile(pkgDir,inflatedName),single(geometry.inflated.vertices.'),'single');
                inflatedUrl=sprintf('%s/%s/%s',urlBase,token,inflatedName);
            end
            overlayAssets = repmat(struct('measureId','','url','','contentHash',''),1,numel(measureIds));
            for ii=1:numel(measureIds)
                name=sprintf('surface_overlay_%03d_f32.bin',ii);
                NMResultsViewerSurfaceTools.writeBinary(fullfile(pkgDir,name),vectors{ii},'single');
                overlayAssets(ii)=struct('measureId',measureIds{ii}, ...
                    'url',sprintf('%s/%s/%s',urlBase,token,name),'contentHash',vectorHashes{ii});
            end
            package = struct('token',token, ...
                'nativeVerticesUrl',sprintf('%s/%s/%s',urlBase,token,nativeName), ...
                'inflatedVerticesUrl',inflatedUrl, ...
                'indicesUrl',sprintf('%s/%s/%s',urlBase,token,indexName), ...
                'supportAsset',struct('url',sprintf('%s/%s/%s',urlBase,token,supportName), ...
                    'contentHash',NMImagingContentIdentity.hashArray(support,'uint8')), ...
                'overlayAssets',overlayAssets);
        end

        function payload = browserGeometryPayload(geometry,package,selectedGeometryId)
            native = struct('geometryId',geometry.native.geometryId,'label','Native','available',true, ...
                'verticesUrl',package.nativeVerticesUrl,'indicesUrl',package.indicesUrl, ...
                'vertexDataType','float32','indexDataType','uint32', ...
                'nVertices',geometry.vertexCount,'nTriangles',geometry.faceCount, ...
                'bounds',geometry.native.bounds);
            inflated = struct('geometryId',geometry.inflated.geometryId,'label','Inflated', ...
                'declared',geometry.inflated.declared,'available',geometry.inflated.available, ...
                'disabledReason',geometry.inflated.disabledReason, ...
                'verticesUrl',package.inflatedVerticesUrl,'indicesUrl',package.indicesUrl, ...
                'vertexDataType','float32','indexDataType','uint32', ...
                'nVertices',geometry.vertexCount,'nTriangles',geometry.faceCount, ...
                'bounds',geometry.inflated.bounds);
            payload = struct('available',true,'coordinateSpace','world_mm', ...
                'selectedGeometryId',selectedGeometryId,'native',native,'inflated',inflated, ...
                'topologyIdentity',geometry.topologyIdentity, ...
                'vertexOrderIdentity',geometry.vertexOrderIdentity, ...
                'surfaceTemplate',geometry.surfaceTemplate,'surfaceHemisphere',geometry.surfaceHemisphere, ...
                'partCount',geometry.partCount,'parts',geometry.parts);
        end

        function [lhPath,rhPath,stem] = resolveAnnotationPair(selectedPath)
            
            % nm2-allow: user-selected annotation boundary verifies the external file resource
            if isempty(selectedPath) || exist(selectedPath,'file')~=2
                error('NMResultsViewerSurfaceTools:AnnotationSelectionMissing', ...
                    'Select one existing lh.*.annot or rh.*.annot file.');
            end
            [ok,attributes] = fileattrib(selectedPath);
            if ok
                selectedPath = attributes.Name;
            end
            [folder,name,ext] = fileparts(selectedPath);
            fullName = [name ext];
            if ~strcmpi(ext,'.annot')
                error('NMResultsViewerSurfaceTools:AnnotationExtension', ...
                    'Surface ROI atlases must use the FreeSurfer .annot format.');
            end
            if startsWith(lower(fullName),'lh.')
                lhPath=selectedPath; counterpart=['rh.' fullName(4:end)]; rhPath=fullfile(folder,counterpart);
                stem=fullName(4:end-numel(ext));
            elseif startsWith(lower(fullName),'rh.')
                rhPath=selectedPath; counterpart=['lh.' fullName(4:end)]; lhPath=fullfile(folder,counterpart);
                stem=fullName(4:end-numel(ext));
            else
                error('NMResultsViewerSurfaceTools:AnnotationHemispherePrefix', ...
                    'Annotation filenames must begin with lh. or rh.');
            end
            if isempty(strtrim(stem))
                error('NMResultsViewerSurfaceTools:AnnotationAtlasStem', ...
                    'Annotation filenames must contain an atlas name between the hemisphere prefix and .annot extension.');
            end
            % nm2-allow: user-selected annotation boundary verifies the paired external annotation resources
            if exist(lhPath,'file')~=2 || exist(rhPath,'file')~=2
                error('NMResultsViewerSurfaceTools:AnnotationCounterpartMissing', ...
                    'The exact counterpart annotation file was not found in the same directory. Required pair: %s | %s',lhPath,rhPath);
            end
            stem = strrep(stem,'_',' ');
        end

        function [labels,table] = readAnnotation(filename)
            fid=fopen(filename,'r','ieee-be');
            if fid<0, error('NMResultsViewerSurfaceTools:AnnotationOpenFailed','Could not open %s.',filename); end
            cleaner=onCleanup(@()fclose(fid)); %#ok<NASGU>
            nVertices=fread(fid,1,'int32=>double');
            if isempty(nVertices)||~isfinite(nVertices)||nVertices<1
                error('NMResultsViewerSurfaceTools:AnnotationHeader','Invalid annotation vertex count in %s.',filename);
            end
            pairs=fread(fid,[2 nVertices],'int32=>double')';
            if size(pairs,1)~=nVertices
                error('NMResultsViewerSurfaceTools:AnnotationTruncated','Annotation vertex table is truncated: %s',filename);
            end
            expected=(0:nVertices-1)';
            if ~isequal(pairs(:,1),expected)
                error('NMResultsViewerSurfaceTools:AnnotationVertexOrder', ...
                    'Annotation vertex indices must be complete, unique, and ordered from 0 to N-1: %s',filename);
            end
            labels=pairs(:,2);
            hasTable=fread(fid,1,'int32=>double');
            if isempty(hasTable)||hasTable==0
                error('NMResultsViewerSurfaceTools:AnnotationColorTableMissing', ...
                    'Annotation file has no embedded colour table: %s',filename);
            end
            marker=fread(fid,1,'int32=>double');
            if isempty(marker), error('NMResultsViewerSurfaceTools:AnnotationColorTableTruncated','Colour table is truncated: %s',filename); end
            if marker>=0
                error('NMResultsViewerSurfaceTools:AnnotationLegacyColorTable', ...
                    'Only version-2 FreeSurfer annotation colour tables are supported by the Results Viewer: %s',filename);
            end
            version=-marker;
            if version~=2
                error('NMResultsViewerSurfaceTools:AnnotationColorTableVersion', ...
                    'Unsupported FreeSurfer annotation colour-table version %g in %s.',version,filename);
            end
            maxEntries=fread(fid,1,'int32=>double');
            if isempty(maxEntries)||~isfinite(maxEntries)||maxEntries<1||maxEntries~=round(maxEntries)
                error('NMResultsViewerSurfaceTools:AnnotationColorTableTruncated','Invalid maximum colour-table entry count in %s.',filename);
            end
            originLength=fread(fid,1,'int32=>double');
            if isempty(originLength)||~isfinite(originLength)||originLength<0||originLength~=round(originLength)||originLength>1048576
                error('NMResultsViewerSurfaceTools:AnnotationColorTableTruncated','Invalid colour-table origin length in %s.',filename);
            end
            if originLength>0
                originBytes=fread(fid,originLength,'uint8=>uint8');
                if numel(originBytes)~=originLength
                    error('NMResultsViewerSurfaceTools:AnnotationColorTableTruncated','Colour-table origin is truncated in %s.',filename);
                end
            end
            nEntries=fread(fid,1,'int32=>double');
            if isempty(nEntries)||~isfinite(nEntries)||nEntries<1||nEntries~=round(nEntries)||nEntries>maxEntries
                error('NMResultsViewerSurfaceTools:AnnotationColorTableTruncated','Invalid populated colour-table entry count in %s.',filename);
            end
            entryTemplate=struct('structureIndex',0,'name','','rgba',[0 0 0 0],'annotationCode',0);
            table=repmat(entryTemplate,nEntries,1);
            for ii=1:nEntries
                structureIndex=fread(fid,1,'int32=>double');
                nameLength=fread(fid,1,'int32=>double');
                if isempty(structureIndex)||isempty(nameLength)||~isfinite(structureIndex)||~isfinite(nameLength)|| ...
                        structureIndex<0||structureIndex>=maxEntries||structureIndex~=round(structureIndex)|| ...
                        nameLength<0||nameLength~=round(nameLength)||nameLength>1048576
                    error('NMResultsViewerSurfaceTools:AnnotationColorTableTruncated','Colour table is truncated in %s.',filename);
                end
                bytes=fread(fid,nameLength,'uint8=>uint8')';
                if numel(bytes)~=nameLength, error('NMResultsViewerSurfaceTools:AnnotationColorTableTruncated','Colour-table name is truncated.'); end
                if ~isempty(bytes)&&bytes(end)==0, bytes=bytes(1:end-1); end
                rgba=fread(fid,4,'int32=>double')';
                if numel(rgba)~=4, error('NMResultsViewerSurfaceTools:AnnotationColorTableTruncated','Colour-table RGBA row is truncated.'); end
                if any(~isfinite(rgba))||any(rgba(1:3)<0)||any(rgba(1:3)>255)||any(rgba(1:3)~=round(rgba(1:3)))
                    error('NMResultsViewerSurfaceTools:AnnotationColorTableValue','Invalid RGB colour-table value in %s.',filename);
                end
                code=rgba(1)+rgba(2)*256+rgba(3)*65536;
                table(ii)=struct('structureIndex',structureIndex,'name',char(bytes), ...
                    'rgba',rgba,'annotationCode',double(code));
            end
            structureIndices=[table.structureIndex];
            annotationCodes=[table.annotationCode];
            if numel(unique(structureIndices))~=numel(structureIndices)
                error('NMResultsViewerSurfaceTools:AnnotationDuplicateStructure','Annotation colour table contains duplicate structure indices in %s.',filename);
            end
            if numel(unique(annotationCodes))~=numel(annotationCodes)
                error('NMResultsViewerSurfaceTools:AnnotationDuplicateCode','Annotation colour table contains duplicate packed RGB codes in %s.',filename);
            end
        end

        function [mapped,records,nextId] = mapAnnotationLabels(labels,table,hemisphere,startId)
            mapped=zeros(numel(labels),1,'uint32');
            recordTemplate=struct('roiCode',0,'name','','hemisphere','','sourceStructureIndex',0, ...
                'sourceAnnotationCode',0,'rgba',[0 0 0 0]);
            records=repmat(recordTemplate,0,1);
            nextId=startId;
            codeToId=containers.Map('KeyType','double','ValueType','double');
            for ii=1:numel(table)
                row=table(ii);
                if row.structureIndex==0
                    codeToId(row.annotationCode)=0;
                    continue;
                end
                roiCode=nextId; nextId=nextId+1;
                name=strtrim(row.name);
                if isempty(name), name=sprintf('%s ROI %d',hemisphere,row.structureIndex); end
                prefix='lh';if strcmp(hemisphere,'right'),prefix='rh';end
                if ~startsWith(lower(name),'lh_')&&~startsWith(lower(name),'rh_')
                    name=sprintf('%s_%s',prefix,name);
                end
                codeToId(row.annotationCode)=roiCode;
                records(end+1,1)=struct('roiCode',roiCode,'name',name,'hemisphere',hemisphere, ...
                    'sourceStructureIndex',row.structureIndex,'sourceAnnotationCode',row.annotationCode, ...
                    'rgba',row.rgba); %#ok<AGROW>
            end
            uniqueCodes=unique(labels(:));
            for ii=1:numel(uniqueCodes)
                code=double(uniqueCodes(ii));
                if ~isKey(codeToId,code)
                    error('NMResultsViewerSurfaceTools:AnnotationCodeMissingFromTable', ...
                        'Annotation code %g is not represented in the embedded colour table.',code);
                end
                mapped(labels==code)=uint32(codeToId(code));
            end
        end

        function asset = writeAtlasAsset(tmpDir,identity,data)
            [assetDir,urlBase]=NMResultsViewerSurfaceTools.assetDirectory(tmpDir);
            token=['surface_atlas_' identity];if numel(token)>100,token=token(1:100);end
            pkgDir=fullfile(assetDir,token);
            % nm2-allow: browser atlas-asset boundary creates the external cache directory when absent
            if exist(pkgDir,'dir')~=7,mkdir(pkgDir);end
            name='surface_atlas_u32.bin';NMResultsViewerSurfaceTools.writeBinary(fullfile(pkgDir,name),uint32(data(:)),'uint32');
            asset=struct('url',sprintf('%s/%s/%s',urlBase,token,name), ...
                'contentHash',NMImagingContentIdentity.hashArray(uint32(data),'uint32'));
        end

        function [assetDir,urlBase] = assetDirectory(tmpDir)
            
            % nm2-allow: browser-session boundary validates the caller-supplied external temporary directory
            if isempty(tmpDir)||exist(tmpDir,'dir')~=7
                error('NMResultsViewerSurfaceTools:InvalidSessionDirectory','A valid browser-session tmpDir is required.');
            end
            webDir=fileparts(tmpDir);
            assetDir=fullfile(webDir,'results_imaging_cache');
            % nm2-allow: browser asset boundary creates the external cache directory when absent
            if exist(assetDir,'dir')~=7
                [ok,msg]=mkdir(assetDir);if ~ok,error('NMResultsViewerSurfaceTools:CreateDirectory','Could not create %s: %s',assetDir,msg);end
            end
            urlBase='results_imaging_cache';
        end

        function writeBinary(path,data,precision)
            bytesPerElement=struct('single',4,'uint32',4,'uint8',1);
            expected=numel(data)*bytesPerElement.(precision);
            % nm2-allow: browser asset writer checks whether the external binary resource already exists
            if exist(path,'file')==2
                info=dir(path);if ~isempty(info)&&double(info(1).bytes)==expected,return;end
            end
            fid=fopen(path,'w','ieee-le');if fid<0,error('NMResultsViewerSurfaceTools:FileWrite','Could not open %s.',path);end
            cleaner=onCleanup(@()fclose(fid)); %#ok<NASGU>
            count=fwrite(fid,data,precision);if count~=numel(data),error('NMResultsViewerSurfaceTools:FileWrite','Could not write all elements to %s.',path);end
        end
    end
end

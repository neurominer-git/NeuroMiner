classdef NMResultsViewerImagingTools
% NMResultsViewerImagingTools
% -------------------------------------------------------------------------
% Results Viewer orchestration for imaging catalogue and orthogonal workspaces.
%
% This class translates an authoritative Results Viewer feature-vector selection
% (Feature Inspection or MLI) into fixed imaging-catalogue entries and browser-ready volume assets.
% Scientific reconstruction, spatial alignment, atlas preparation, colour defaults,
% and asset packaging are delegated to narrow backend services. It does not render
% browser HTML, own viewer state, generate meshes, or mutate NM.
%
% Documentation: docs/NMResultsViewerImagingKnowledgeIndex.md
% -------------------------------------------------------------------------

    methods (Static)
        function payload = getImagingCatalogue(NM, spec)
            % getImagingCatalogue  List spatial maps for one authoritative feature selection.
            %
            % Catalogue construction is metadata-only. It does not materialize
            % feature tables, relation matrices, graph payloads, or metric vectors.
            % nm2-allow: public imaging catalogue API intentionally supports omitted request state
            if nargin < 2 || isempty(spec), spec = struct(); end
            payload = NMImagingContractTools.cataloguePayloadTemplate();
            doProfile = NMResultsViewerTools.profileEnabled(spec);
            tCatalogueTotal = tic;
            profileCleanup = onCleanup(@() NMResultsViewerImagingTools.profileLog(doProfile, ...
                '[nm-prof] imaging catalogue EXIT: %.3fs\n',toc(tCatalogueTotal))); %#ok<NASGU>
            % nm2-allow: public imaging catalogue API validates external request transport before canonical dispatch
            % nm2-allow: public imaging atlas-resource API validates external request transport before canonical dispatch
            if ~isstruct(spec) || ~isscalar(spec)
                payload.message = 'Imaging catalogue specification must be a scalar struct.';
                payload.diagnostics = NMImagingContractTools.diagnostic( ...
                    'error','invalid_spec','NMResultsViewerImagingTools.getImagingCatalogue', ...
                    payload.message,'spec',[]);
                return;
            end
            req = NMResultsViewerImagingTools.imagingRequest(spec);
            try
                selectedGridPolicy = NMImagingContractTools.normalizeDisplayGridPolicy(req.displayGridPolicy);
                payload.selectedDisplayGridPolicy = selectedGridPolicy;
                sourceId = req.source;
                payload.resultSourceId = sourceId;
                tStage = tic;
                inspection = NMResultsViewerFeatureVectorAuthority.metadata(NM,req);
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging catalogue metadata payload:   %.3fs (contexts=%d measures=%d spatialMaps=%d)\n', ...
                    toc(tStage),double(numel(inspection.contexts)),double(numel(inspection.measures)), ...
                    double(numel(inspection.spatialMaps)));
                payload.scientificContractVersion = inspection.scientificContractVersion;
                payload.scientificAnnotation = inspection.scientificAnnotation;
                payload.resolvedSelection = inspection.resolvedSelection;
                payload.analysisIndex = inspection.analysisIndex;
                payload.targetIndex = inspection.targetIndex;
                payload.resultTargetIndex = inspection.resultTargetIndex;
                payload.classifierIndex = inspection.classifierIndex;
                if ~inspection.ok
                    payload.message = inspection.message;
                    if isempty(payload.message), payload.message = 'The selected feature-vector payload is unavailable.'; end
                    return;
                end
                adapterSelection = NMResultsViewerFeatureVectorAuthority.selection(req,inspection);
                payload.selectedFeatureContextId = adapterSelection.context.contextId;
                if isempty(inspection.spatialMaps)
                    payload.message = 'The selected feature source exposes no spatial-map descriptor.';
                    payload.diagnostics = NMImagingContractTools.diagnostic( ...
                        'warning','no_spatial_descriptor','NMResultsViewerImagingTools.getImagingCatalogue', ...
                        payload.message,'featureContextId',[]);
                    return;
                end
                tStage = tic;
                [entries,diagnostics] = NMResultsViewerImagingTools.catalogueEntriesFromInspection( ...
                    NM,inspection,sourceId,selectedGridPolicy);
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging catalogue descriptor normalization: %.3fs (entries=%d)\n', ...
                    toc(tStage),double(numel(entries)));
                payload.entries = entries;
                payload.diagnostics = diagnostics;
                selectedIndex = NMResultsViewerImagingTools.selectEntry(entries,req.imagingModalityId);
                if selectedIndex > 0, payload.selectedImagingEntryId = entries(selectedIndex).imagingEntryId; end
                payload.ok = ~isempty(entries);
                if isempty(entries)
                    payload.message = 'The selected feature-vector context contains no normalized spatial-map entries.';
                elseif any([entries.enabled])
                    payload.message = sprintf('Imaging catalogue contains %d spatial map(s), including %d enabled spatial map(s).', ...
                        numel(entries),nnz([entries.enabled]));
                else
                    payload.message = sprintf('Imaging catalogue contains %d spatial map(s), but none is currently enabled.',numel(entries));
                end
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof] imaging catalogue SUCCESS: %.3fs (entries=%d enabled=%d)\n', ...
                    toc(tCatalogueTotal),double(numel(entries)),double(nnz([entries.enabled])));
            % nm2-allow: public imaging catalogue boundary converts failures into the documented diagnostic payload
            catch ME
                payload.ok = false;
                payload.message = sprintf('%s: %s',ME.identifier,ME.message);
                payload.diagnostics = NMImagingContractTools.diagnostic( ...
                    'error','imaging_catalogue_failure','NMResultsViewerImagingTools.getImagingCatalogue', ...
                    payload.message,'',ME);
            end
        end

        function payload = getImagingWorkspace(NM, spec, tmpDir)
            % nm2-allow: capability-provider overload intentionally accepts the registry query as the first and only argument
            if nargin>=1 && NMResultsViewerScientificCapability.isQuery(NM)
                p=[NMResultsViewerScientificCapability.provide('imaging_workspace','scientific_artefact','imaging','imaging_workspace'), ...
                    NMResultsViewerScientificCapability.provide('imaging_2d_planes','visualization','',''), ...
                    NMResultsViewerScientificCapability.provide('imaging_3d_volume','visualization','',''), ...
                    NMResultsViewerScientificCapability.provide('imaging_3d_surface_projection','visualization','',''), ...
                    NMResultsViewerScientificCapability.provide('roi_spider','visualization','','')];
                payload=NMResultsViewerScientificCapability.contract('imaging_workspace',{{'voxel_feature_map','roi_feature_map','surface_feature_map'}},p); return;
            end
            % getImagingWorkspace  Build browser-ready orthogonal volume assets.
            %
            % The demand-driven workspace path includes one
            % native-grid feature source: one metadata pass resolves the selected
            % physical context, only requested measure vectors are loaded, atlas
            % data are loaded only after explicit selection, and interactive volume
            % features remain on their native grid. Report/export publication uses
            % the same browser-native workspace authority.
            % nm2-allow: public imaging workspace API intentionally supports omitted request state
            if nargin < 2 || isempty(spec), spec = struct(); end
            % nm2-allow: public imaging workspace API intentionally supports omitted temporary asset root
            payload = struct( ...
                'schema','NMImagingWorkspacePayload', ...
                'schemaVersion',2, ...
                'contractVersion','C18d4.7a', ...
                'ok',false, ...
                'message','', ...
                'scientificContractVersion','', ...
                'scientificAnnotation',struct(), ...
                'resolvedSelection',struct(), ...
                'analysisIndex',0, ...
                'targetIndex',0, ...
                'resultTargetIndex',NaN, ...
                'classifierIndex',0, ...
                'selectedFeatureContextId','', ...
                'contentId','', ...
                'displayGridPolicy','structural_reference', ...
                'dimensions',[0 0 0], ...
                'spatialReference',NMImagingContractTools.spatialReferenceTemplate(), ...
                'planeConvention',struct('schema','NMImagingPlaneConvention','schemaVersion',1,'mode','','coordinateConvention','spm_one_based_direct','gridId','','planes',struct([])), ...
                'templateCatalogue',struct('templateId',{},'label',{},'file',{},'fileExists',{},'provenance',{},'isDefault',{},'enabled',{},'disabledReason',{}), ...
                'selectedTemplate',struct('available',false,'templateId','','label','','provenance','','gridId',''), ...
                'structural',struct('url','','dataType','float32','window',[NaN NaN],'valueRange',[NaN NaN]), ...
                'support',struct('url','','dataType','uint8'), ...
                'residentMaterialization',struct('structuralKey','','featureSpaceKey','','displayScaffoldKey','','featureMappingId','','catalogueRevision',''), ...
                'nativeFeatureSampling',NMImagingNativeFeatureSource.browserPayloadTemplate(), ...
                'overlays',struct('measureId',{},'label',{},'sourceField',{},'valuePolarity',{},'valueRange',{},'displayDefaults',{},'url',{},'dataType',{}), ...
                'canonicalROI',NMDataIOROIProvenanceTools.viewerMaterialization(), ...
                'atlasCatalogue',struct('atlasId',{},'label',{},'file',{},'fileExists',{},'descriptorFile',{},'descriptorFileExists',{},'lutFile',{},'lutFileExists',{},'lutProvenance',{},'provenance',{},'enabled',{},'disabledReason',{}), ...
                'selectedAtlas',struct('available',false,'atlasId','','label','','url','','dataType','uint32','roiLabels',struct(),'labelMessage','','labelProvenance','','alignmentAudit',struct()), ...
                'initialVoxel',[NaN NaN NaN], ...
                'initialWorldMm',[NaN NaN NaN], ...
                'layoutProfile',NMImagingContractTools.layoutProfileTemplate(), ...
                'alignmentAudit',struct('atlas',struct()), ...
                'capabilities',NMResultsViewerImagingTools.volumeCapabilities(false), ...
                'diagnostics',NMImagingContractTools.diagnosticTemplate([]));
            doProfile = NMResultsViewerTools.profileEnabled(spec);
            req = NMResultsViewerImagingTools.imagingRequest(spec);
            tWorkspaceTotal = tic;
            profileCleanup = onCleanup(@() NMResultsViewerImagingTools.profileLog(doProfile, ...
                '[nm-prof] imaging workspace EXIT: %.3fs\n',toc(tWorkspaceTotal))); %#ok<NASGU>
            NMResultsViewerImagingTools.profileLog(doProfile, ...
                '[nm-prof] imaging workspace ENTER analysis=%g classifier=%g target=%g context=%s component=%s\n', ...
                req.analysisIndex,req.classifierIndex,req.targetIndex,req.featureContextId,req.backprojectionComponentId);
            try
                tStage = tic;
                inspection = NMResultsViewerFeatureVectorAuthority.metadata(NM,req);
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging metadata selection TOTAL:     %.3fs (contexts=%d measures=%d spatialMaps=%d)\n', ...
                    toc(tStage),double(numel(inspection.contexts)),double(numel(inspection.measures)), ...
                    double(numel(inspection.spatialMaps)));
                if ~inspection.ok
                    payload.message = inspection.message;
                    return;
                end

                adapterSelection = NMResultsViewerFeatureVectorAuthority.selection(req,inspection);
                context = adapterSelection.context;
                requestedIds = adapterSelection.measureIds;
                payload.scientificContractVersion = adapterSelection.scientificContractVersion;
                payload.scientificAnnotation = adapterSelection.scientificAnnotation;
                payload.resolvedSelection = adapterSelection.resolvedSelection;
                payload.analysisIndex = double(adapterSelection.resolvedSelection.analysisIndex);
                payload.targetIndex = double(adapterSelection.resolvedSelection.targetIndex);
                payload.resultTargetIndex = double(adapterSelection.resolvedSelection.resultTargetIndex);
                payload.classifierIndex = double(adapterSelection.resolvedSelection.classifierIndex);
                payload.selectedFeatureContextId = context.contextId;
                descriptor = NMResultsViewerImagingDescriptorAdapter.resolve(NM,context.varind,struct());
                isCanonicalROI = strcmpi(context.featureKind,'roi');
                roiProjection = struct();
                if isCanonicalROI
                    if ~descriptor.ok || ~descriptor.roiProvenance.ok
                        payload.message = sprintf('Canonical ROI provenance is unavailable for context %s.',context.contextId);
                        return;
                    end
                    roiProjection = NMDataIOROIProvenanceTools.spatialProjection(descriptor.roiProvenance);
                end
                if strcmpi(context.featureKind,'surface_vertex') || ...
                        (isCanonicalROI && strcmp(roiProjection.spatialDomain,'surface'))
                    payload = NMResultsViewerSurfaceTools.buildWorkspace( ...
                        NM,req,tmpDir,inspection,context,payload.diagnostics);
                    return;
                end
                if ~strcmpi(context.featureKind,'voxel') && ...
                        ~(isCanonicalROI && strcmp(roiProjection.spatialDomain,'volume'))
                    payload.message = sprintf('The imaging viewer does not support selected context %s.',context.featureKind);
                    return;
                end

                % Interactive volumetric workspaces share the native feature
                % authority. Canonical ROI values remain authoritative on their
                % provenance-atlas grid and are sampled voxel-faithfully there.
                if isCanonicalROI
                    policy = 'structural_reference';
                else
                    policy = NMImagingContractTools.normalizeDisplayGridPolicy(req.displayGridPolicy);
                end
                payload.displayGridPolicy = policy;
                compactCanonicalROI = isCanonicalROI;
                sourceId = req.source;
                tStage = tic;
                [entries,catalogueDiagnostics] = NMResultsViewerImagingTools.catalogueEntriesFromInspection( ...
                    NM,inspection,sourceId,policy);
                entryHit = find(arrayfun(@(x)strcmp(x.identity.featureContextId,context.contextId) && ...
                    strcmp(x.identity.measureId,requestedIds{1}) && strcmp(x.spatialDomain,'volume'),entries),1,'first');
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging selected-entry metadata:      %.3fs (entries=%d requested=%d)\n', ...
                    toc(tStage),double(numel(entries)),double(numel(requestedIds)));
                if isempty(entryHit)
                    payload.message = 'The selected volumetric context has no enabled imaging-catalogue entry.';
                    payload.diagnostics = catalogueDiagnostics;
                    return;
                end
                entry = entries(entryHit);
                payload.capabilities = NMResultsViewerImagingTools.volumeCapabilities(isCanonicalROI);
                if ~entry.enabled
                    error('NMResultsViewerImagingTools:ImagingEntryUnavailable', ...
                        '%s',entry.disabledReason);
                end

                tStage = tic;
                templateCatalogue = NMImagingTemplateService.catalogue( ...
                    entry.structuralReferenceFile,fileparts(entry.structuralReferenceFile),{});
                [selectedTemplate,selectedTemplateIndex] = NMImagingTemplateService.select( ...
                    templateCatalogue,req.selectedTemplateId);
                if selectedTemplateIndex == 0 || ~selectedTemplate.enabled
                    error('NMResultsViewerImagingTools:StructuralTemplateUnavailable', ...
                        'No enabled structural template is available for the selected imaging context.');
                end
                structuralKey = NMResultsViewerImagingTools.structuralCacheKey(selectedTemplate.file);
                [structuralOriginal,structuralHit] = NMImagingRuntimeCache.get('structural',structuralKey);
                if ~structuralHit
                    structuralOriginal = NMImagingVolumeAccess.read(selectedTemplate.file,'structural_original');
                    NMImagingRuntimeCache.put('structural',structuralKey,structuralOriginal);
                end
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging structural template/volume:   %.3fs (cacheHit=%d template=%s dims=%s)\n', ...
                    toc(tStage),double(structuralHit),selectedTemplate.templateId, ...
                    mat2str(double(structuralOriginal.dimensions)));

                tStage = tic;
                featureKey = NMResultsViewerImagingTools.featureSpaceCacheKey(NM,context.varind,entry.featureSpaceFile);
                [featurePackage,featureHit] = NMImagingRuntimeCache.get('feature_space',featureKey);
                if ~featureHit
                    if isCanonicalROI
                        featureSpace = NMImagingVolumeAccess.read(entry.featureSpaceFile,'canonical_roi_atlas');
                        canonicalROIMapping = NMDataIOROIProvenanceTools.prepareVolumetricMapping( ...
                            descriptor.roiProvenance,featureSpace.data,featureKey);
                        featurePackage = struct('volume',featureSpace,'descriptor',descriptor, ...
                            'canonicalROIVolumetricMapping',canonicalROIMapping);
                    else
                        [featureSpace,featureDescriptor] = NMResultsViewerImagingDescriptorAdapter.loadFeatureSpace( ...
                            NM,context.varind,entry.featureSpaceFile);
                        featurePackage = struct('volume',featureSpace,'descriptor',featureDescriptor);
                    end
                    NMImagingRuntimeCache.put('feature_space',featureKey,featurePackage);
                end
                featureSpace = featurePackage.volume;
                canonicalROIMapping = struct();
                if isCanonicalROI
                    canonicalROIMapping = featurePackage.canonicalROIVolumetricMapping;
                end
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging feature-space volume:         %.3fs (cacheHit=%d dims=%s)\n', ...
                    toc(tStage),double(featureHit),mat2str(double(featureSpace.dimensions)));

                overlayTemplate = struct('measureId','','label','','sourceField','','valuePolarity','signed', ...
                    'valueRange',[NaN NaN],'displayDefaults',struct(),'sourceVectorHash','', ...
                    'mappingId','','displayContentHash','','data',[]);
                overlayData = repmat(overlayTemplate,1,numel(requestedIds));
                displayStructural = [];
                displaySupport = [];
                displayReference = [];
                scaffoldKey = '';
                scaffoldStructuralHash = '';
                scaffoldSupportHash = '';
                structuralWindow = [NaN NaN];
                nativeFeaturePackage = struct();
                indexedOverlays = struct([]);
                canonicalROIValues = cell(1,numel(requestedIds));

                if compactCanonicalROI
                    [canonicalROIMapping,nativeFeaturePackage,overlayData,indexedOverlays,canonicalROIValues] = ...
                        NMResultsViewerImagingTools.prepareCanonicalROICompact( ...
                            NM,req,inspection,requestedIds,featurePackage,featureKey,doProfile);
                    featureSpace = featurePackage.volume;
                    tPreparedScaffold = tic;
                    [scaffold,scaffoldKey,scaffoldHit] = NMResultsViewerImagingTools.resolveNativeDisplayScaffold( ...
                        structuralOriginal,featureSpace,policy,structuralKey,featureKey, ...
                        nativeFeaturePackage.grid.mappingId,nativeFeaturePackage.grid.supportContentHash,doProfile);
                    displayStructural = scaffold.structuralVolume;
                    displayReference = scaffold.spatialReference;
                    scaffoldStructuralHash = scaffold.structuralContentHash;
                    scaffoldSupportHash = scaffold.supportContentHash;
                    structuralWindow = scaffold.structuralWindow;
                    NMResultsViewerImagingTools.profileLog(doProfile, ...
                        '[nm-prof]   canonical ROI native display scaffold: %.3fs (cacheHit=%d mapping=%s)\n', ...
                        toc(tPreparedScaffold),double(scaffoldHit),nativeFeaturePackage.grid.mappingId);
                else
                    for ii=1:numel(requestedIds)
                        tOverlayTotal = tic;
                        vectorSpec = req;
                        vectorSpec.measureId = requestedIds{ii};
                        tOverlayStage = tic;
                        vector = NMResultsViewerImagingVectorAdapter.resolve(NM,vectorSpec,requestedIds{ii},inspection);
                        if ~vector.ok
                            error('NMResultsViewerImagingTools:FeatureVectorUnavailable','%s',vector.message);
                        end
                        sourceVectorHash = NMImagingContentIdentity.hashArray(double(vector.values),'double');
                        if isCanonicalROI, canonicalROIValues{ii} = double(vector.values(:)'); end
                        NMResultsViewerImagingTools.profileLog(doProfile, ...
                            '[nm-prof]     imaging overlay %d/%d vector+hash:       %.3fs (%s features=%d)\n', ...
                            ii,numel(requestedIds),toc(tOverlayStage),requestedIds{ii},double(numel(vector.values)));

                        tOverlayStage = tic;
                        featureMap = NMImagingFeatureMapAdapter.reconstruct( ...
                            vector.values,featureSpace,vector.badcoords,vector.maskSelection);
                        [nativeFeaturePackage,displayDefaults] = ...
                            NMResultsViewerImagingTools.appendPreparedNativeOverlay( ...
                                nativeFeaturePackage,featureMap,vector.values,vector.measure,sourceVectorHash);
                        if isempty(scaffoldKey)
                            [scaffold,scaffoldKey,scaffoldHit] = NMResultsViewerImagingTools.resolveNativeDisplayScaffold( ...
                                structuralOriginal,featureMap.overlayVolume,policy,structuralKey,featureKey, ...
                                featureMap.mappingId,nativeFeaturePackage.grid.supportContentHash,doProfile);
                            displayStructural = scaffold.structuralVolume;
                            displayReference = scaffold.spatialReference;
                            scaffoldStructuralHash = scaffold.structuralContentHash;
                            scaffoldSupportHash = scaffold.supportContentHash;
                            structuralWindow = scaffold.structuralWindow;
                        end
                        nativeOverlay = nativeFeaturePackage.overlays(end);
                        displayContentHash = nativeOverlay.contentHash;
                        displayData = [];
                        NMResultsViewerImagingTools.profileLog(doProfile, ...
                            '[nm-prof]     imaging overlay %d/%d native interactive payload: %.3fs (scaffoldCacheHit=%d mapping=%s)\n', ...
                            ii,numel(requestedIds),toc(tOverlayStage),double(scaffoldHit),featureMap.mappingId);


                        overlayData(ii).measureId = vector.measure.measureId;
                        overlayData(ii).label = vector.measure.label;
                        overlayData(ii).sourceField = vector.measure.sourceField;
                        overlayData(ii).valuePolarity = vector.measure.valuePolarity;
                        overlayData(ii).valueRange = displayDefaults.valueRange;
                        overlayData(ii).displayDefaults = displayDefaults;
                        overlayData(ii).sourceVectorHash = sourceVectorHash;
                        overlayData(ii).mappingId = featureMap.mappingId;
                        overlayData(ii).displayContentHash = displayContentHash;
                        overlayData(ii).data = displayData;
                        NMResultsViewerImagingTools.profileLog(doProfile, ...
                            '[nm-prof]     imaging overlay %d/%d TOTAL:             %.3fs (%s)\n', ...
                            ii,numel(requestedIds),toc(tOverlayTotal),requestedIds{ii});
                    end
                end

                selectedAtlasId = req.selectedAtlasId;
                atlasTargetReference = displayReference;
                if compactCanonicalROI, atlasTargetReference = featureSpace.spatialReference; end
                [atlasCatalogue,preparedAtlas,atlasContentHash,atlasHit] = ...
                    NMResultsViewerImagingTools.resolveAtlasResource( ...
                        entry,selectedAtlasId,atlasTargetReference,doProfile,req.volumeAtlasPath, ...
                        req.volumeAtlasDelimiter,req.volumeAtlasNameColumn,req.volumeAtlasDescriptorFile);
                if ~isempty(fieldnames(preparedAtlas)), selectedAtlasId = preparedAtlas.atlasId; end
                if isCanonicalROI
                    for rr = 1:descriptor.roiProvenance.nColumns
                        preparedAtlas.roiLabels.(sprintf('roi_%.0f',double(descriptor.roiProvenance.roiIDs(rr)))) = ...
                            descriptor.roiProvenance.roiNames{rr};
                    end
                    preparedAtlas.labelProvenance = 'canonical_roi_provenance';
                    preparedAtlas.labelMessage = sprintf('Canonical DataIO ROI provenance supplied %d ROI label(s).',descriptor.roiProvenance.nColumns);
                end

                measureIdentity = strjoin(requestedIds,'>');
                overlayIdentity = strjoin(arrayfun(@(x)sprintf('%s:%s:%s:%s', ...
                    x.measureId,x.sourceVectorHash,x.mappingId,x.displayContentHash), ...
                    overlayData,'UniformOutput',false),'>');
                if compactCanonicalROI
                    nativeOverlayHashes = {indexedOverlays.contentHash};
                else
                    nativeOverlayHashes = {nativeFeaturePackage.overlays.contentHash};
                end
                resolvedSelection = adapterSelection.resolvedSelection;
                contentIdentityText = strjoin({ ...
                    sprintf('analysis=%d',round(double(resolvedSelection.analysisIndex))), ...
                    ['source=' sourceId], ...
                    sprintf('target=%d',round(double(resolvedSelection.targetIndex))), ...
                    sprintf('resultTarget=%.17g',double(resolvedSelection.resultTargetIndex)), ...
                    sprintf('classifier=%d',round(double(resolvedSelection.classifierIndex))), ...
                    ['context=' context.contextId], ...
                    ['component=' resolvedSelection.backprojectionComponentId], ...
                    ['measures=' measureIdentity],['overlays=' overlayIdentity], ...
                    ['policy=' policy],['grid=' displayReference.gridId], ...
                    ['templateId=' selectedTemplate.templateId], ...
                    ['structural=' scaffoldStructuralHash],['support=' scaffoldSupportHash], ...
                    ['featureSpace=' featureKey],['atlasId=' selectedAtlasId],['atlas=' atlasContentHash], ...
                    ['nativeGrid=' nativeFeaturePackage.grid.gridId], ...
                    ['nativeMapping=' nativeFeaturePackage.grid.mappingId], ...
                    ['nativeSupport=' nativeFeaturePackage.grid.supportContentHash], ...
                    ['nativeOverlays=' strjoin(nativeOverlayHashes,'>')], ...
                    ['catalogueRevision=' entry.identity.contentRevision], ...
                    'contract=C18d4.7a'},'|');
                contentId = NMImagingContentIdentity.hashText(contentIdentityText);
                contentHashes = struct( ...
                    'structural',scaffoldStructuralHash, ...
                    'atlas',atlasContentHash);
                tStage = tic;
                if compactCanonicalROI
                    assets = NMImagingAssetCache.writeWorkspace( ...
                        tmpDir,contentId,displayStructural,struct(),doProfile,contentHashes,struct());
                    lookupContentHash = NMImagingContentIdentity.hashText(strjoin({ ...
                        'canonical_roi_lookup_v1',canonicalROIMapping.materializationIdentity},'|'));
                    lookupAsset = NMImagingAssetCache.writeIndexedLookup(tmpDir,canonicalROIMapping.materializationIdentity, ...
                        canonicalROIMapping.lookupIndex,lookupContentHash,doProfile);
                    nativePayload = NMImagingNativeFeatureSource.browserIndexedPayload( ...
                        nativeFeaturePackage,lookupAsset,indexedOverlays);
                    maxAtlasId = max([0 double(preparedAtlas.roiIds)]);
                    if maxAtlasId <= double(intmax('uint8'))
                        nativeAtlasData = uint8(preparedAtlas.data);
                    elseif maxAtlasId <= double(intmax('uint16'))
                        nativeAtlasData = uint16(preparedAtlas.data);
                    else
                        nativeAtlasData = uint32(preparedAtlas.data);
                    end
                    compactAtlasAsset = NMImagingAssetCache.writeIndexedLookup(tmpDir, ...
                        NMImagingContentIdentity.hashText(['canonical_roi_atlas_native_v1|' atlasContentHash]), ...
                        nativeAtlasData,atlasContentHash,doProfile);
                    NMResultsViewerImagingTools.profileLog(doProfile, ...
                        '[nm-prof]   imaging compact ROI asset package TOTAL: %.3fs (token=%s overlays=%d atlasBytes=%d)\n', ...
                        toc(tStage),assets.packageToken,double(numel(overlayData)),double(numel(nativeAtlasData))*double(numel(typecast(cast(0,class(nativeAtlasData)), 'uint8'))));
                else
                    assets = NMImagingAssetCache.writeWorkspace( ...
                        tmpDir,contentId,displayStructural,preparedAtlas,doProfile,contentHashes,nativeFeaturePackage);
                    nativePayload = NMImagingNativeFeatureSource.browserPayload(nativeFeaturePackage,assets.nativeFeatureAssets);
                    NMResultsViewerImagingTools.profileLog(doProfile, ...
                        '[nm-prof]   imaging asset package TOTAL:          %.3fs (token=%s)\n', ...
                        toc(tStage),assets.packageToken);
                end

                browserOverlays = rmfield(overlayData,{'data','sourceVectorHash','mappingId','displayContentHash'});
                for ii=1:numel(browserOverlays)
                    browserOverlays(ii).url = '';
                    browserOverlays(ii).dataType = 'float32';
                    browserOverlays(ii).contentHash = overlayData(ii).displayContentHash;
                end

                initialVoxel = max([1 1 1],round((double(displayStructural.dimensions)+1)/2));
                initialWorld = NMImagingSpatialReference.voxelToWorld(displayReference,initialVoxel);
                payload.ok = true;
                payload.message = sprintf('Prepared %d imaging overlay page(s) on the %s grid.',numel(browserOverlays),strrep(policy,'_',' '));
                payload.contentId = contentId;
                payload.dimensions = double(displayStructural.dimensions);
                payload.spatialReference = displayReference;
                payload.planeConvention = NMImagingSliceService.planeConvention(displayReference);
                payload.templateCatalogue = templateCatalogue;
                payload.selectedTemplate = struct('available',true, ...
                    'templateId',selectedTemplate.templateId,'label',selectedTemplate.label, ...
                    'provenance',selectedTemplate.provenance,'gridId',displayReference.gridId);
                payload.structural = struct('url',assets.structuralUrl,'dataType','float32', ...
                    'contentHash',assets.structuralContentHash, ...
                    'window',structuralWindow,'valueRange',displayStructural.valueRange);
                payload.support = struct('url','','dataType','uint8', ...
                    'contentHash',scaffoldSupportHash);
                payload.residentMaterialization = struct('structuralKey',structuralKey,'featureSpaceKey',featureKey, ...
                    'displayScaffoldKey',scaffoldKey,'featureMappingId',overlayData(1).mappingId, ...
                    'catalogueRevision',entry.identity.contentRevision);
                payload.nativeFeatureSampling = nativePayload;
                payload.overlays = browserOverlays;
                if isCanonicalROI
                    payload.canonicalROI = NMDataIOROIProvenanceTools.viewerMaterialization( ...
                        descriptor.roiProvenance,requestedIds,canonicalROIValues);
                end
                payload.atlasCatalogue = rmfield(atlasCatalogue,{'descriptorOptions','descriptorCandidates'});
                if ~isempty(fieldnames(preparedAtlas))
                    if compactCanonicalROI
                        displayAtlasContentHash = NMImagingContentIdentity.hashText(strjoin({ ...
                            'canonical_roi_display_atlas_v1',atlasContentHash,displayReference.gridId},'|'));
                        payload.selectedAtlas = struct('available',true,'atlasId',preparedAtlas.atlasId, ...
                            'label',preparedAtlas.label,'url',compactAtlasAsset.url,'dataType',compactAtlasAsset.dataType, ...
                            'elementCount',compactAtlasAsset.elementCount,'storageEncoding','native_nearest_v1', ...
                            'sourceGridId',featureSpace.spatialReference.gridId, ...
                            'sourceContentHash',atlasContentHash,'contentHash',displayAtlasContentHash, ...
                            'roiLabels',preparedAtlas.roiLabels, ...
                            'labelMessage',preparedAtlas.labelMessage, ...
                            'labelProvenance',preparedAtlas.labelProvenance,'alignmentAudit',struct());
                    else
                        payload.selectedAtlas = struct('available',true,'atlasId',preparedAtlas.atlasId, ...
                            'label',preparedAtlas.label,'url',assets.atlasAsset.url,'dataType','uint32', ...
                            'contentHash',assets.atlasAsset.contentHash, ...
                            'roiLabels',preparedAtlas.roiLabels, ...
                            'labelMessage',preparedAtlas.labelMessage, ...
                            'labelProvenance',preparedAtlas.labelProvenance, ...
                            'alignmentAudit',preparedAtlas.alignmentAudit);
                        payload.alignmentAudit.atlas = preparedAtlas.alignmentAudit;
                    end
                    payload.selectedAtlas.descriptorInfo = preparedAtlas.descriptorInfo;
                end
                payload.initialVoxel = initialVoxel;
                payload.initialWorldMm = initialWorld;
                payload.diagnostics = catalogueDiagnostics;
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof] imaging workspace SUCCESS: %.3fs (overlays=%d policy=%s atlas=%d)\n', ...
                    toc(tWorkspaceTotal),double(numel(browserOverlays)),policy,double(payload.selectedAtlas.available));
            % nm2-allow: public imaging workspace boundary converts failures into the documented diagnostic payload
            catch ME
                payload.ok = false;
                payload.message = sprintf('%s: %s',ME.identifier,ME.message);
                payload.diagnostics = NMImagingContractTools.diagnostic( ...
                    'error','imaging_workspace_failure','NMResultsViewerImagingTools.getImagingWorkspace', ...
                    payload.message,'',ME);
            end
        end

        function payload = getImagingFeatureResource(NM, spec, tmpDir)
            % getImagingFeatureResource  Materialize only changed feature assets for a resident imaging workspace.
            %
            % Purpose:
            %   Replace one or more selected feature-vector measures without rebuilding a complete imaging workspace.
            %
            % Inputs:
            %   NM; canonical destination feature-vector spec; browser-session tmpDir. The spec carries the
            %   mounted workspace's actual structural/display/materialization identities. Analysis/context names
            %   identify the destination scientific payload but do not define retained-space equivalence.
            %
            % Outputs:
            %   NMImagingFeatureResourcePayload containing only changed feature/support transport assets and compact
            %   scientific-selection metadata. requiresWorkspace=true means the destination cannot inhabit the
            %   resident physical/display space and the caller must use getImagingWorkspace.
            %
            % Authority and flow:
            %   The selected result family remains the measure/vector authority. Generic voxel payloads retain the established
            %   feature-map/alignment/native-grid services. Canonical ROI payloads consume the exact atlas-label
            %   -> ROI-column authority; a previously unseen ROI feature space is materialized once here rather than
            %   forcing a full workspace solely to seed the runtime cache.
            %   Surface resources delegate to NMResultsViewerSurfaceTools.buildFeatureResource.
            %
            % Scientific/state contract:
            %   This operation may replace feature values, feature mapping and feature support. It never replaces
            %   the structural image, display grid, atlas, surface geometry, topology, or vertex order.
            %
            % Materialization and performance:
            %   The resident structural/scaffold authority is validated first. Destination feature-space/scaffold
            %   materialization then uses the same feature-space and display-scaffold cache authorities as the full
            %   workspace, without rebuilding the workspace catalogue or anatomy. Generic voxel maps reconstruct only
            %   the destination native-grid feature package; the browser samples changed support/values directly from
            %   that authoritative grid without a MATLAB display-space rematerialization. Canonical
            %   volumetric ROI switches establish or reuse one compact voxel-to-column mapping and transport that invariant
            %   integer lookup plus O(R) ROI values; dense renderer arrays are reconstructed browser-side. They do not use
            %   generic feature-map reconstruction/alignment, V-sized feature hashing, or MATLAB-side dense ROI expansion.
            %   Surface payloads retain their domain-specific compact materializer.
            %
            % Failure semantics:
            %   Explicit resident-identity disagreement returns requiresWorkspace. Invalid scientific vectors/mappings
            %   fail with diagnostics; no name/length inference or alternate source lookup is performed.
            % nm2-allow: public imaging feature-resource API intentionally supports omitted request state
            if nargin < 2 || isempty(spec), spec = struct(); end
            % nm2-allow: public imaging feature-resource API intentionally supports omitted temporary asset root
            payload = struct('schema','NMImagingFeatureResourcePayload','schemaVersion',1, ...
                'contractVersion','NM-RESULTS-IMAGING-FEATURE-RESOURCE-V1','ok',false,'requiresWorkspace',false, ...
                'message','','sourceDomain','volume','scientificContractVersion','', ...
                'scientificAnnotation',struct(),'resolvedSelection',struct(),'analysisIndex',0,'targetIndex',0, ...
                'resultTargetIndex',NaN,'classifierIndex',0,'selectedFeatureContextId','', ...
                'contentId','','overlays',struct([]),'support',struct(),'residentMaterialization',struct(),'nativeFeatureSampling',struct(), ...
                'canonicalROI',NMDataIOROIProvenanceTools.viewerMaterialization(), ...
                'capabilities',struct(),'residentContract',struct(), ...
                'diagnostics',NMImagingContractTools.diagnosticTemplate([]));
            doProfile=NMResultsViewerTools.profileEnabled(spec); tTotal=tic;
            req=NMResultsViewerImagingTools.imagingRequest(spec);
            try
                tStage=tic; inspection=NMResultsViewerFeatureVectorAuthority.metadata(NM,req);
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging feature resource metadata:      %.3fs (contexts=%d measures=%d)\n', ...
                    toc(tStage),double(numel(inspection.contexts)),double(numel(inspection.measures)));
                if ~inspection.ok, payload.message=inspection.message; return; end
                adapterSelection=NMResultsViewerFeatureVectorAuthority.selection(req,inspection);
                context=adapterSelection.context; requestedIds=adapterSelection.measureIds;
                contextId=context.contextId;
                isCanonicalROI=strcmpi(context.featureKind,'roi');
                if strcmpi(context.featureKind,'surface_vertex') || ...
                        (isCanonicalROI&&strcmpi(context.roiSpatialDomain,'surface'))
                    payload=NMResultsViewerSurfaceTools.buildFeatureResource(NM,req,tmpDir,inspection,context,payload.diagnostics);
                    return;
                end
                descriptor=NMResultsViewerImagingDescriptorAdapter.resolve(NM,context.varind,struct()); roiProjection=struct();
                if isCanonicalROI
                    if ~descriptor.ok||~descriptor.roiProvenance.ok
                        payload.message=sprintf('Canonical ROI provenance is unavailable for context %s.',contextId); return;
                    end
                    roiProjection=NMDataIOROIProvenanceTools.spatialProjection(descriptor.roiProvenance);
                end
                if ~strcmpi(context.featureKind,'voxel') && ~(isCanonicalROI&&strcmp(roiProjection.spatialDomain,'volume'))
                    payload.message=sprintf('The imaging feature-resource service does not support context %s.',context.featureKind); return;
                end
                policy=NMImagingContractTools.normalizeDisplayGridPolicy(req.displayGridPolicy);
                residentStructuralKey=req.residentStructuralKey;
                residentFeatureKey=req.residentFeatureSpaceKey;
                residentScaffoldKey=req.residentDisplayScaffoldKey;
                residentMappingId=req.residentFeatureMappingId;
                if isempty(residentStructuralKey)||isempty(residentScaffoldKey)
                    payload.ok=true; payload.requiresWorkspace=true; payload.message='The resident structural/display materialization identity is incomplete.'; return;
                end
                [residentScaffold,residentScaffoldHit]=NMImagingRuntimeCache.get('display_scaffold',residentScaffoldKey);
                if ~residentScaffoldHit
                    payload.ok=true; payload.requiresWorkspace=true; payload.message='The resident display-scaffold materialization is no longer available.'; return;
                end
                residentGridId=req.residentDisplayGridId;
                residentStructuralHash=req.residentStructuralContentHash;
                residentSupportHash=req.residentSupportContentHash;
                if isempty(residentGridId)||~strcmp(residentGridId,residentScaffold.spatialReference.gridId)|| ...
                        isempty(residentStructuralHash)||~strcmp(residentStructuralHash,residentScaffold.structuralContentHash)|| ...
                        isempty(residentSupportHash)||~strcmp(residentSupportHash,residentScaffold.supportContentHash)
                    payload.ok=true; payload.requiresWorkspace=true; payload.message='The resident display materialization no longer matches its cache authority.'; return;
                end
                spatialMaps=inspection.spatialMaps;
                spatialHit=find(arrayfun(@(x)strcmp(x.contextId,contextId)&& ...
                    strcmp(x.measureId,requestedIds{1}),spatialMaps),1,'first');
                if isempty(spatialHit)
                    payload.message='The selected volumetric context has no spatial feature descriptor.'; return;
                end
                spatialMap=spatialMaps(spatialHit);
                if ~logical(spatialMap.enabled), payload.message=spatialMap.disabledReason; return; end
                destinationFeatureKey=NMResultsViewerImagingTools.featureSpaceCacheKey(NM,context.varind,spatialMap.maskFile);
                structuralFile=NMImagingTemplateService.structuralReferenceFile(NM);
                templateCatalogue=NMImagingTemplateService.catalogue(structuralFile,fileparts(structuralFile),{});
                [selectedTemplate,selectedTemplateIndex]=NMImagingTemplateService.select( ...
                    templateCatalogue,req.selectedTemplateId);
                if selectedTemplateIndex==0||~selectedTemplate.enabled
                    payload.ok=true; payload.requiresWorkspace=true; payload.message='The destination structural template is unavailable for retained feature replacement.'; return;
                end
                destinationStructuralKey=NMResultsViewerImagingTools.structuralCacheKey(selectedTemplate.file);
                if ~strcmp(destinationStructuralKey,residentStructuralKey)
                    payload.ok=true; payload.requiresWorkspace=true; payload.message='The destination structural resource differs from the resident imaging workspace.'; return;
                end
                canonicalROIMapping=struct();
                [featurePackage,featureHit]=NMImagingRuntimeCache.get('feature_space',destinationFeatureKey);
                if ~featureHit
                    if isCanonicalROI
                        featureSpace=NMImagingVolumeAccess.read(spatialMap.maskFile,'canonical_roi_atlas');
                        canonicalROIMapping=NMDataIOROIProvenanceTools.prepareVolumetricMapping( ...
                            descriptor.roiProvenance,featureSpace.data,destinationFeatureKey);
                        featurePackage=struct('volume',featureSpace,'descriptor',descriptor, ...
                            'canonicalROIVolumetricMapping',canonicalROIMapping);
                    else
                        [featureSpace,featureDescriptor]=NMResultsViewerImagingDescriptorAdapter.loadFeatureSpace( ...
                            NM,context.varind,spatialMap.maskFile);
                        featurePackage=struct('volume',featureSpace,'descriptor',featureDescriptor);
                    end
                    NMImagingRuntimeCache.put('feature_space',destinationFeatureKey,featurePackage);
                end
                featureSpace=featurePackage.volume;
                residentNativeGrid=req.residentNativeGridId;
                residentNativeMapping=req.residentNativeMappingId;
                residentNativeSupport=req.residentNativeSupportContentHash;
                scaffold=struct(); scaffoldKey='';
                indexedOverlays=struct([]); canonicalROIValues=cell(1,numel(requestedIds));

                if isCanonicalROI
                    [canonicalROIMapping,nativeFeaturePackage,overlayData,indexedOverlays,canonicalROIValues] = ...
                        NMResultsViewerImagingTools.prepareCanonicalROICompact( ...
                            NM,req,inspection,requestedIds,featurePackage,destinationFeatureKey,doProfile);
                    featureSpace=featurePackage.volume;
                    storedMappingId=nativeFeaturePackage.grid.mappingId;
                    storedNativeSupportHash=nativeFeaturePackage.grid.supportContentHash;
                    if strcmp(destinationFeatureKey,residentFeatureKey)
                        if isempty(residentMappingId)||~strcmp(storedMappingId,residentMappingId)|| ...
                                ~strcmp(storedMappingId,residentNativeMapping)|| ...
                                ~strcmp(storedNativeSupportHash,residentNativeSupport)|| ...
                                ~strcmp(featureSpace.gridId,residentNativeGrid)
                            payload.ok=true; payload.requiresWorkspace=true; payload.message='The resident canonical ROI mapping/support identity differs from the cached voxel-column materialization.'; return;
                        end
                        scaffold=residentScaffold; scaffoldKey=residentScaffoldKey;
                    else
                        [scaffold,scaffoldKey]=NMResultsViewerImagingTools.resolveRetainedNativeScaffold( ...
                            residentScaffold,storedNativeSupportHash,residentStructuralKey,destinationFeatureKey,storedMappingId,doProfile);
                    end
                else
                    overlayTemplate=struct('measureId','','label','','sourceField','','valuePolarity','signed', ...
                        'valueRange',[NaN NaN],'displayDefaults',struct(),'sourceVectorHash','', ...
                        'mappingId','','displayContentHash','','data',[]);
                    overlayData=repmat(overlayTemplate,1,numel(requestedIds)); nativeFeaturePackage=struct();
                    for ii=1:numel(requestedIds)
                        tOverlay=tic; vectorSpec=req; vectorSpec.measureId=requestedIds{ii};
                        vector=NMResultsViewerImagingVectorAdapter.resolve(NM,vectorSpec,requestedIds{ii},inspection);
                        if ~vector.ok, error('NMResultsViewerImagingTools:FeatureVectorUnavailable','%s',vector.message); end
                        sourceVectorHash=NMImagingContentIdentity.hashArray(double(vector.values),'double');
                        featureMap=NMImagingFeatureMapAdapter.reconstruct(vector.values,featureSpace,vector.badcoords,vector.maskSelection);
                        [nativeFeaturePackage,displayDefaults]=NMResultsViewerImagingTools.appendPreparedNativeOverlay( ...
                            nativeFeaturePackage,featureMap,vector.values,vector.measure,sourceVectorHash);
                        if strcmp(destinationFeatureKey,residentFeatureKey)&&strcmp(featureMap.mappingId,residentMappingId)
                            candidateScaffold=residentScaffold; candidateScaffoldKey=residentScaffoldKey;
                        else
                            [candidateScaffold,candidateScaffoldKey]=NMResultsViewerImagingTools.resolveRetainedNativeScaffold( ...
                                residentScaffold,nativeFeaturePackage.grid.supportContentHash,residentStructuralKey, ...
                                destinationFeatureKey,featureMap.mappingId,doProfile);
                        end
                        if isempty(scaffoldKey)
                            scaffold=candidateScaffold; scaffoldKey=candidateScaffoldKey;
                        elseif ~strcmp(scaffoldKey,candidateScaffoldKey)
                            error('NMResultsViewerImagingTools:OverlaySupportMismatch', ...
                                'Requested overlays do not share one authoritative feature mapping and display scaffold.');
                        end
                        nativeOverlay=nativeFeaturePackage.overlays(end);
                        overlayData(ii).measureId=vector.measure.measureId; overlayData(ii).label=vector.measure.label;
                        overlayData(ii).sourceField=vector.measure.sourceField; overlayData(ii).valuePolarity=vector.measure.valuePolarity;
                        overlayData(ii).valueRange=displayDefaults.valueRange;
                        overlayData(ii).displayDefaults=displayDefaults;
                        overlayData(ii).sourceVectorHash=sourceVectorHash; overlayData(ii).mappingId=featureMap.mappingId;
                        overlayData(ii).displayContentHash=nativeOverlay.contentHash; overlayData(ii).data=[];
                        NMResultsViewerImagingTools.profileLog(doProfile, ...
                            '[nm-prof]     imaging retained native feature %d/%d TOTAL: %.3fs (metric=%s)\n', ...
                            ii,numel(requestedIds),toc(tOverlay),requestedIds{ii});
                    end
                end

                destinationMappingId=overlayData(1).mappingId;
                measureIdentity=strjoin(requestedIds,'>');
                overlayIdentity=strjoin(arrayfun(@(x)sprintf('%s:%s:%s:%s',x.measureId,x.sourceVectorHash,x.mappingId,x.displayContentHash), ...
                    overlayData,'UniformOutput',false),'>');
                if isCanonicalROI
                    nativeOverlayHashes={indexedOverlays.contentHash};
                else
                    nativeOverlayHashes={nativeFeaturePackage.overlays.contentHash};
                end
                resolvedSelection=adapterSelection.resolvedSelection;
                contentIdentityText=strjoin({ ...
                    'feature_resource=RV-L2', ['measures=' measureIdentity],['overlays=' overlayIdentity], ...
                    ['policy=' policy],['scaffold=' scaffoldKey],['structural=' residentStructuralKey], ...
                    ['support=' scaffold.supportContentHash],['featureSpace=' destinationFeatureKey], ...
                    ['nativeGrid=' nativeFeaturePackage.grid.gridId],['nativeMapping=' nativeFeaturePackage.grid.mappingId], ...
                    ['nativeSupport=' nativeFeaturePackage.grid.supportContentHash], ...
                    ['nativeOverlays=' strjoin(nativeOverlayHashes,'>')]},'|');
                contentId=NMImagingContentIdentity.hashText(contentIdentityText);
                browserOverlays=rmfield(overlayData,{'data','sourceVectorHash','mappingId','displayContentHash'});
                if isCanonicalROI
                    lookupContentHash=NMImagingContentIdentity.hashText(strjoin({ ...
                        'canonical_roi_lookup_v1',canonicalROIMapping.materializationIdentity},'|'));
                    lookupAsset=NMImagingAssetCache.writeIndexedLookup(tmpDir,canonicalROIMapping.materializationIdentity, ...
                        canonicalROIMapping.lookupIndex,lookupContentHash,doProfile);
                    for ii=1:numel(browserOverlays)
                        browserOverlays(ii).url=''; browserOverlays(ii).dataType='float32';
                        browserOverlays(ii).contentHash=overlayData(ii).displayContentHash;
                    end
                    nativePayload=NMImagingNativeFeatureSource.browserIndexedPayload( ...
                        nativeFeaturePackage,lookupAsset,indexedOverlays);
                else
                    nativeSupportChanged=isempty(residentNativeGrid)||~strcmp(residentNativeGrid,nativeFeaturePackage.grid.gridId)|| ...
                        isempty(residentNativeMapping)||~strcmp(residentNativeMapping,nativeFeaturePackage.grid.mappingId)|| ...
                        isempty(residentNativeSupport)||~strcmp(residentNativeSupport,nativeFeaturePackage.grid.supportContentHash);
                    assets=NMImagingAssetCache.writeFeatureResource( ...
                        tmpDir,contentId,overlayData([]),nativeFeaturePackage,[],doProfile,nativeSupportChanged);
                    for ii=1:numel(browserOverlays)
                        browserOverlays(ii).url=''; browserOverlays(ii).dataType='float32';
                        browserOverlays(ii).contentHash=overlayData(ii).displayContentHash;
                    end
                    nativePayload=NMImagingNativeFeatureSource.browserPayload(nativeFeaturePackage,assets.nativeFeatureAssets);
                end
                payload.ok=true; payload.message=sprintf('Prepared %d retained imaging feature resource(s).',numel(browserOverlays));
                payload.scientificContractVersion=adapterSelection.scientificContractVersion;
                payload.scientificAnnotation=adapterSelection.scientificAnnotation; payload.resolvedSelection=resolvedSelection;
                payload.analysisIndex=double(resolvedSelection.analysisIndex); payload.targetIndex=double(resolvedSelection.targetIndex);
                payload.resultTargetIndex=double(resolvedSelection.resultTargetIndex); payload.classifierIndex=double(resolvedSelection.classifierIndex);
                payload.selectedFeatureContextId=contextId; payload.contentId=contentId; payload.overlays=browserOverlays;
                payload.support=struct('url','','dataType','uint8','elementCount',numel(nativeFeaturePackage.grid.supportData), ...
                    'contentHash',nativeFeaturePackage.grid.supportContentHash);
                payload.residentMaterialization=struct('structuralKey',residentStructuralKey,'featureSpaceKey',destinationFeatureKey, ...
                    'displayScaffoldKey',scaffoldKey,'featureMappingId',destinationMappingId,'catalogueRevision','');
                payload.nativeFeatureSampling=nativePayload; payload.capabilities=NMResultsViewerImagingTools.volumeCapabilities(isCanonicalROI);
                if isCanonicalROI
                    payload.canonicalROI=NMDataIOROIProvenanceTools.viewerMaterialization(descriptor.roiProvenance,requestedIds,canonicalROIValues);
                end
                payload.residentContract=struct('sourceDomain','volume','featureContextId',contextId, ...
                    'structuralKey',residentStructuralKey,'displayGridId',scaffold.spatialReference.gridId, ...
                    'structuralContentHash',scaffold.structuralContentHash,'supportContentHash',scaffold.supportContentHash, ...
                    'featureSpaceKey',destinationFeatureKey,'displayScaffoldKey',scaffoldKey,'featureMappingId',destinationMappingId, ...
                    'nativeGridId',nativeFeaturePackage.grid.gridId,'nativeMappingId',nativeFeaturePackage.grid.mappingId, ...
                    'nativeSupportContentHash',nativeFeaturePackage.grid.supportContentHash);
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof] imaging feature resource SUCCESS: %.3fs (overlays=%d domain=volume)\n', ...
                    toc(tTotal),double(numel(browserOverlays)));
            % nm2-allow: public imaging feature-resource boundary converts failures into the documented diagnostic payload
            catch ME
                payload.ok=false; payload.message=sprintf('%s: %s',ME.identifier,ME.message);
                payload.diagnostics=NMImagingContractTools.diagnostic('error','imaging_feature_resource_failure', ...
                    'NMResultsViewerImagingTools.getImagingFeatureResource',payload.message,'',ME);
            end
        end

        function payload = getImagingAtlasResource(NM, spec, tmpDir)
            % getImagingAtlasResource  Materialize only one voxel-atlas resource.
            %
            % The mounted imaging workspace supplies its authoritative display
            % spatial reference. This operation performs metadata selection,
            % exact persisted-atlas alignment and atlas-only transport; it does not
            % resolve feature vectors, rebuild feature maps, or package anatomy.
            % nm2-allow: public imaging atlas-resource API intentionally supports omitted request state
            if nargin < 2 || isempty(spec), spec = struct(); end
            % nm2-allow: public imaging atlas-resource API intentionally supports omitted temporary asset root
            payload = struct('schema','NMImagingAtlasResourcePayload','schemaVersion',1, ...
                'contractVersion','PORT1-R1O-B','ok',false,'message','', ...
                'targetGridId','','atlasCatalogue',struct([]), ...
                'selectedAtlas',struct('available',false,'atlasId','','label','','url','', ...
                    'dataType','uint32','contentHash','','roiLabels',struct(), ...
                    'labelMessage','','labelProvenance','','alignmentAudit',struct()), ...
                'diagnostics',NMImagingContractTools.diagnosticTemplate([]));
            doProfile = NMResultsViewerTools.profileEnabled(spec);
            tTotal = tic;
            try
                % nm2-allow: public imaging atlas-resource API validates external request transport before canonical dispatch
                if ~isstruct(spec) || ~isscalar(spec)
                    error('NMResultsViewerImagingTools:InvalidAtlasSpec','Atlas resource specification must be a scalar struct.');
                end
                req = NMResultsViewerImagingTools.imagingRequest(spec);
                selectedAtlasId = req.selectedAtlasId;
                if (isempty(selectedAtlasId) || strcmpi(selectedAtlasId,'none')) && isempty(req.volumeAtlasPath)
                    error('NMResultsViewerImagingTools:MissingAtlasSelection','Atlas resource materialization requires one explicit atlas selection.');
                end
                % nm2-allow: public atlas-resource request boundary requires the retained spatial-reference object supplied by the mounted workspace
                if ~isfield(spec,'atlasTargetReference') || ~isstruct(spec.atlasTargetReference) || ~isscalar(spec.atlasTargetReference)
                    error('NMResultsViewerImagingTools:MissingAtlasTargetReference','The mounted display spatial reference is required for atlas materialization.');
                end
                targetReference = NMImagingSpatialReference.fromVolume(spec.atlasTargetReference);
                requestedGridId = req.atlasTargetGridId;
                if ~isempty(requestedGridId) && ~strcmp(requestedGridId,targetReference.gridId)
                    error('NMResultsViewerImagingTools:AtlasTargetGridMismatch', ...
                        'Requested atlas target grid %s does not match the supplied spatial reference %s.', ...
                        requestedGridId,targetReference.gridId);
                end
                payload.targetGridId = targetReference.gridId;

                cataloguePayload = NMResultsViewerImagingTools.getImagingCatalogue(NM,spec);
                if ~cataloguePayload.ok
                    error('NMResultsViewerImagingTools:AtlasCatalogueUnavailable','%s',cataloguePayload.message);
                end
                entries = cataloguePayload.entries;
                contextId = req.featureContextId;
                measureId = req.measureId;
                if isempty(measureId) && ~isempty(req.measureIds)
                    atlasMeasureIds = string(req.measureIds);
                    measureId = char(atlasMeasureIds(1));
                end
                entryHit = find(arrayfun(@(x)strcmp(x.identity.featureContextId,contextId) && ...
                    strcmp(x.identity.measureId,measureId) && strcmp(x.spatialDomain,'volume'),entries),1,'first');
                if isempty(entryHit)
                    error('NMResultsViewerImagingTools:AtlasContextUnavailable', ...
                        'No voxel imaging catalogue entry matches feature context %s and measure %s.',contextId,measureId);
                end
                entry = entries(entryHit);
                if ~entry.enabled, error('NMResultsViewerImagingTools:AtlasContextDisabled','%s',entry.disabledReason); end
                [atlasCatalogue,preparedAtlas,atlasContentHash,atlasHit] = ...
                    NMResultsViewerImagingTools.resolveAtlasResource( ...
                        entry,selectedAtlasId,targetReference,doProfile,req.volumeAtlasPath, ...
                        req.volumeAtlasDelimiter,req.volumeAtlasNameColumn,req.volumeAtlasDescriptorFile);
                payload.atlasCatalogue = rmfield(atlasCatalogue,{'descriptorOptions','descriptorCandidates'});
                resourceId = NMImagingContentIdentity.hashText(strjoin({ ...
                    'atlas_resource','PORT1-R1O-B',targetReference.gridId, ...
                    preparedAtlas.atlasId,atlasContentHash},'|'));
                asset = NMImagingAssetCache.writeAtlas(tmpDir,resourceId,preparedAtlas,doProfile,atlasContentHash);
                payload.selectedAtlas = struct('available',true,'atlasId',preparedAtlas.atlasId, ...
                    'label',preparedAtlas.label,'url',asset.url,'dataType','uint32', ...
                    'contentHash',asset.contentHash,'roiLabels',preparedAtlas.roiLabels, ...
                    'descriptorInfo',preparedAtlas.descriptorInfo,'labelMessage',preparedAtlas.labelMessage,'labelProvenance',preparedAtlas.labelProvenance, ...
                    'alignmentAudit',preparedAtlas.alignmentAudit);
                payload.ok = true;
                payload.message = sprintf('Prepared atlas %s on display grid %s.',preparedAtlas.label,payload.targetGridId);
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof] imaging atlas resource SUCCESS: %.3fs (cacheHit=%d atlas=%s grid=%s)\n', ...
                    toc(tTotal),double(atlasHit),preparedAtlas.atlasId,payload.targetGridId);
            % nm2-allow: public imaging atlas-resource boundary converts failures into the documented diagnostic payload
            catch ME
                payload.ok = false;
                payload.message = NMUIErrorTools.messageWithStack(ME,'Loading the selected ROI atlas failed.',2);
                payload.diagnostics = NMImagingContractTools.diagnostic( ...
                    'error','imaging_atlas_resource_failure','NMResultsViewerImagingTools.getImagingAtlasResource', ...
                    payload.message,'',ME);
            end
        end

        function payload = getImaging3DAssets(NM, spec, tmpDir)
            % getImaging3DAssets  Prepare volume support or the deferred surface mesh.
            %
            % assetScope='volume' returns only the deterministic anatomy mask
            % needed by volume ray casting. assetScope='surface' additionally
            % extracts and transports the world-mm anatomy mesh. Both scopes
            % share the same mask contract and stable structural cache key.
            % nm2-allow: public imaging 3-D asset API intentionally supports omitted request state
            if nargin < 2 || isempty(spec), spec = struct(); end
            % nm2-allow: public imaging 3-D asset API intentionally supports omitted temporary asset root
            payload = struct( ...
                'schema','NMImaging3DAssetPayload', ...
                'schemaVersion',2, ...
                'contractVersion','C18g5-R3B', ...
                'ok',false, ...
                'message','', ...
                'assetScope','surface', ...
                'contentId','', ...
                'workspaceContentId','', ...
                'gridId','', ...
                'meshQuality','balanced', ...
                'surfaceDepthMm',0, ...
                'anatomyMesh',struct( ...
                    'available',false, ...
                    'coordinateSpace','world_mm', ...
                    'verticesUrl','', ...
                    'normalsUrl','', ...
                    'indicesUrl','', ...
                    'vertexCount',0, ...
                    'faceCount',0, ...
                    'indexCount',0, ...
                    'indexBase',0, ...
                    'boundsWorldMm',struct( ...
                        'min',[NaN NaN NaN], ...
                        'max',[NaN NaN NaN], ...
                        'center',[NaN NaN NaN], ...
                        'radius',NaN), ...
                    'provenance',struct()), ...
                'anatomyMask',struct( ...
                    'available',false, ...
                    'contentId','', ...
                    'url','', ...
                    'dataType','uint8', ...
                    'dimensions',[0 0 0], ...
                    'foregroundVoxelCount',0, ...
                    'provenance',struct()), ...
                'diagnostics',NMImagingContractTools.diagnosticTemplate([]));
            doProfile = NMResultsViewerTools.profileEnabled(spec);
            tAssetsTotal = tic;
            try
                req = NMResultsViewerImagingTools.imagingRequest(spec);
                assetScope = req.assetScope;
                if ~ismember(assetScope,{'volume','surface'})
                    error('NMResultsViewerImagingTools:Invalid3DAssetScope', ...
                        'Unsupported 3-D asset scope "%s".',assetScope);
                end
                quality = req.meshQuality;
                if ~ismember(quality,{'draft','balanced','high'})
                    error('NMResultsViewerImagingTools:InvalidMeshQuality', ...
                        'Unsupported 3-D mesh quality "%s".',quality);
                end
                surfaceDepthMm = req.surfaceDepthMm;
                if ~isfinite(surfaceDepthMm) || surfaceDepthMm < 0 || surfaceDepthMm > 12
                    error('NMResultsViewerImagingTools:InvalidSurfaceDepth', ...
                        'Surface depth must be finite and within [0, 12] mm.');
                end

                residentWorkspaceContentId = req.residentWorkspaceContentId;
                residentScaffoldKey = req.residentDisplayScaffoldKey;
                residentGridId = req.residentDisplayGridId;
                residentStructuralHash = req.residentStructuralContentHash;
                residentSupportHash = req.residentSupportContentHash;
                if isempty(residentWorkspaceContentId) || isempty(residentScaffoldKey) || ...
                        isempty(residentGridId) || isempty(residentStructuralHash) || ...
                        isempty(residentSupportHash)
                    error('NMResultsViewerImagingTools:MissingResident3DMaterialization', ...
                        'The 3-D asset request is missing the resident imaging-workspace materialization identity.');
                end
                tAssetPhase = tic;
                [scaffold,scaffoldHit] = NMImagingRuntimeCache.get( ...
                    'display_scaffold',residentScaffoldKey);
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]     imaging 3-D assets resident scaffold lookup:     %.3fs (hit=%d key=%s)\n', ...
                    toc(tAssetPhase),double(scaffoldHit),residentScaffoldKey);
                if ~scaffoldHit
                    error('NMResultsViewerImagingTools:Resident3DMaterializationUnavailable', ...
                        'The resident imaging display scaffold is no longer available.');
                end
                if ~strcmp(residentGridId,scaffold.spatialReference.gridId) || ...
                        ~strcmp(residentStructuralHash,scaffold.structuralContentHash) || ...
                        ~strcmp(residentSupportHash,scaffold.supportContentHash)
                    error('NMResultsViewerImagingTools:Resident3DMaterializationMismatch', ...
                        'The resident imaging display scaffold does not match the mounted workspace identity.');
                end
                structuralHash = scaffold.structuralContentHash;
                structuralData = scaffold.structuralVolume.data;
                spatialReference = scaffold.spatialReference;
                maskKey = NMImagingContentIdentity.hashText(strjoin( ...
                    {'NMResultsViewerAnatomyMask','v2',structuralHash, ...
                     sprintf('voxel_spacing_mm=%.12g,%.12g,%.12g',double(spatialReference.voxelSizeMm)), ...
                     sprintf('surface_depth_mm=%.6g',surfaceDepthMm)},'|'));
                tAssetPhase = tic;
                [maskAsset,maskHit] = NMImagingRuntimeCache.get('mask3d',maskKey);
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]     imaging 3-D assets mask cache lookup:          %.3fs (hit=%d key=%s)\n', ...
                    toc(tAssetPhase),double(maskHit),maskKey);
                if ~maskHit
                    tAssetPhase = tic;
                    [foregroundMask,maskProvenance] = NMImagingMeshService.prepareAnatomyMask( ...
                        structuralData,spatialReference,struct('surfaceDepthMm',surfaceDepthMm));
                    NMResultsViewerImagingTools.profileLog(doProfile, ...
                        '[nm-prof]     imaging 3-D assets anatomy mask prepare:       %.3fs (voxels=%d depth=%.3gmm)\n', ...
                        toc(tAssetPhase),double(numel(foregroundMask)),double(surfaceDepthMm));
                    maskAsset = struct('foregroundMask',logical(foregroundMask), ...
                        'provenance',maskProvenance);
                    NMImagingRuntimeCache.put('mask3d',maskKey,maskAsset);
                end
                foregroundMask = logical(maskAsset.foregroundMask);
                maskProvenance = maskAsset.provenance;

                mesh = struct();
                meshKey = '';
                meshHit = false;
                if strcmp(assetScope,'surface')
                    meshKey = NMImagingContentIdentity.hashText(strjoin( ...
                        {'NMResultsViewerAnatomyMesh','v2',maskKey, ...
                         spatialReference.gridId,quality},'|'));
                    tAssetPhase = tic;
                    [meshAsset,meshHit] = NMImagingRuntimeCache.get('mesh3d',meshKey);
                    NMResultsViewerImagingTools.profileLog(doProfile, ...
                        '[nm-prof]     imaging 3-D assets mesh cache lookup:          %.3fs (hit=%d key=%s)\n', ...
                        toc(tAssetPhase),double(meshHit),meshKey);
                    if ~meshHit
                        tAssetPhase = tic;
                        mesh = NMImagingMeshService.prepareAnatomyMesh( ...
                            foregroundMask,spatialReference,struct('quality',quality),maskProvenance);
                        NMResultsViewerImagingTools.profileLog(doProfile, ...
                            '[nm-prof]     imaging 3-D assets anatomy mesh prepare:       %.3fs (vertices=%d faces=%d quality=%s)\n', ...
                            toc(tAssetPhase),double(mesh.vertexCount),double(mesh.faceCount),quality);
                        meshAsset = struct('mesh',mesh);
                        NMImagingRuntimeCache.put('mesh3d',meshKey,meshAsset);
                    else
                        mesh = meshAsset.mesh;
                    end
                end

                verticesUrl = '';
                normalsUrl = '';
                indicesUrl = '';
                tAssetPhase = tic;
                if strcmp(assetScope,'surface')
                    assets = NMImagingMeshAssetCache.write( ...
                        tmpDir,meshKey,mesh,foregroundMask);
                else
                    assets = NMImagingMeshAssetCache.writeMask( ...
                        tmpDir,maskKey,foregroundMask);
                end
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]     imaging 3-D assets package/write:              %.3fs (scope=%s)\n', ...
                    toc(tAssetPhase),assetScope);
                foregroundMaskUrl = assets.foregroundUrl;
                if strcmp(assetScope,'surface')
                    verticesUrl = assets.verticesUrl;
                    normalsUrl = assets.normalsUrl;
                    indicesUrl = assets.indicesUrl;
                end


                tAssetPhase = tic;
                payload.ok = true;
                payload.assetScope = assetScope;
                if strcmp(assetScope,'surface')
                    payload.contentId = meshKey;
                else
                    payload.contentId = maskKey;
                end
                payload.workspaceContentId = residentWorkspaceContentId;
                payload.gridId = residentGridId;
                payload.meshQuality = quality;
                payload.surfaceDepthMm = surfaceDepthMm;
                if strcmp(assetScope,'surface')
                    payload.message = sprintf( ...
                        ['Prepared deferred %s world-mm anatomy mesh (%d vertices, ' ...
                         '%d faces; meshCacheHit=%d; maskCacheHit=%d).'], ...
                        quality,mesh.vertexCount,mesh.faceCount,double(meshHit),double(maskHit));
                    payload.anatomyMesh = struct( ...
                        'available',true, ...
                        'coordinateSpace','world_mm', ...
                        'verticesUrl',verticesUrl, ...
                        'normalsUrl',normalsUrl, ...
                        'indicesUrl',indicesUrl, ...
                        'vertexCount',mesh.vertexCount, ...
                        'faceCount',mesh.faceCount, ...
                        'indexCount',numel(mesh.indices), ...
                        'indexBase',0, ...
                        'boundsWorldMm',mesh.boundsWorldMm, ...
                        'provenance',mesh.provenance);
                else
                    payload.message = sprintf( ...
                        'Prepared volume-raycast anatomy support only (maskCacheHit=%d; meshDeferred=1).', ...
                        double(maskHit));
                end
                payload.anatomyMask = struct( ...
                    'available',true, ...
                    'contentId',maskKey, ...
                    'url',foregroundMaskUrl, ...
                    'dataType','uint8', ...
                    'dimensions',double(size(foregroundMask)), ...
                    'foregroundVoxelCount',nnz(foregroundMask), ...
                    'provenance',struct( ...
                        'maskPolicy',maskProvenance.maskPolicy, ...
                        'surfaceDepthMm',surfaceDepthMm, ...
                        'sameMaskAsRenderedAnatomySurface',true, ...
                        'surfaceDeferred',strcmp(assetScope,'volume'), ...
                        'maskAudit',maskProvenance.maskAudit, ...
                        'surfaceDepthAudit',maskProvenance.surfaceDepthAudit));

                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]     imaging 3-D assets payload packaging:           %.3fs\n', toc(tAssetPhase));
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging 3-D assets detailed TOTAL:              %.3fs (scope=%s maskHit=%d meshHit=%d)\n', ...
                    toc(tAssetsTotal),assetScope,double(maskHit),double(meshHit));
            % nm2-allow: public imaging 3-D asset boundary converts failures into the documented diagnostic payload
            catch ME
                NMResultsViewerImagingTools.profileLog(doProfile, ...
                    '[nm-prof]   imaging 3-D assets detailed TOTAL:              %.3fs (failed=1)\n', ...
                    toc(tAssetsTotal));
                payload.ok = false;
                payload.message = sprintf('%s: %s',ME.identifier,ME.message);
                payload.diagnostics = NMImagingContractTools.diagnostic( ...
                    'error','imaging_3d_asset_failure', ...
                    'NMResultsViewerImagingTools.getImaging3DAssets', ...
                    payload.message,'',ME);
            end
        end

        function req = imagingRequest(spec)
            % One canonical viewer specification for both scientific selection
            % and imaging/surface materialization. The general Results Viewer
            % producer owns analysis, target, classifier, source, and feature
            % selectors. This ingress completes only imaging-specific fields.
            [~,req] = NMResultsViewerTools.viewerPlotOptions(spec);
            text = { ...
                'displayGridPolicy','structural_reference'; ...
                'imagingModalityId',''; 'selectedTemplateId',''; ...
                'selectedAtlasId',''; 'volumeAtlasPath',''; 'volumeAtlasDelimiter','auto'; ...
                'volumeAtlasNameColumn',''; 'volumeAtlasDescriptorFile',''; 'atlasTargetGridId',''; ...
                'assetScope','surface'; 'meshQuality','balanced'; ...
                'residentStructuralKey',''; 'residentFeatureSpaceKey',''; ...
                'residentDisplayScaffoldKey',''; 'residentFeatureMappingId',''; ...
                'residentDisplayGridId',''; 'residentStructuralContentHash',''; ...
                'residentSupportContentHash',''; 'residentNativeGridId',''; ...
                'residentNativeMappingId',''; 'residentNativeSupportContentHash',''; ...
                'residentWorkspaceContentId',''; 'residentSurfaceGeometryIdentity',''; ...
                'residentSurfaceTopologyIdentity',''; 'residentSurfaceVertexOrderIdentity',''; ...
                'surfaceAtlasPath',''};
            numeric = { ...
                'surfaceDepthMm',0; 'residentSurfaceVertexCount',NaN; ...
                'surfaceVertexCount',NaN; 'varind',0};
            for k = 1:size(text,1)
                name = text{k,1};
                req.(name) = text{k,2};
                if isfield(spec,name) && ~isempty(spec.(name))
                    raw = spec.(name);
                    if ischar(raw)
                        req.(name) = raw;
                    elseif isstring(raw) && isscalar(raw)
                        req.(name) = char(raw);
                    end
                end
            end
            for k = 1:size(numeric,1)
                name = numeric{k,1};
                req.(name) = numeric{k,2};
                if isfield(spec,name) && ~isempty(spec.(name))
                    raw = spec.(name);
                    candidate = NaN;
                    if isnumeric(raw) || islogical(raw)
                        candidate = double(raw(1));
                    elseif ischar(raw) || (isstring(raw) && isscalar(raw))
                        candidate = str2double(raw);
                    end
                    if isfinite(candidate), req.(name) = candidate; end
                end
            end
            req.assetScope = lower(strtrim(req.assetScope));
            req.meshQuality = lower(strtrim(req.meshQuality));
            req.measureIds = {};
            if isfield(spec,'measureIds') && ~isempty(spec.measureIds)
                req.measureIds = spec.measureIds;
            end
            if ~strcmpi(req.resultType,'mli')
                req.resultType = 'model_feature_inspection';
                if ~isempty(req.featureContextId)
                    req.featureInspectionCatalogueScope = 'selected';
                end
            else
                % Imaging consumers use only the selected subject's relevance vector. The MLI subject catalogue
                % (Model Performance projection over all subjects) is requested by the MLI panel alone.
                req.mliIncludeSubjectCatalogue = false;
            end
        end
    end

    methods (Static, Access = private)
        function [entries,diagnostics] = catalogueEntriesFromInspection(NM,inspection,sourceId,selectedGridPolicy)
            % catalogueEntriesFromInspection  Normalize already-resolved metadata once.
            % Current NM2 imaging resources come from the persisted DataIO spatial contract;
            % canonical ROI identity comes from its validated ROI provenance. No directory discovery occurs.
            entries = NMImagingContractTools.catalogueEntryTemplate([]);
            diagnostics = NMImagingContractTools.diagnosticTemplate([]);
            if isempty(inspection.spatialMaps), return; end
            structuralFile = NMImagingTemplateService.structuralReferenceFile(NM);
            structuralExists = NMDataIOImageFileTools.existsForSPM(structuralFile);
            spatialMaps = inspection.spatialMaps;
            entryTemplate = NMImagingContractTools.catalogueEntryTemplate();
            entries = repmat(entryTemplate,1,numel(spatialMaps));
            for ii = 1:numel(spatialMaps)
                sp = spatialMaps(ii);
                contextId = sp.contextId;
                ctx = NMResultsViewerImagingTools.requireContext(inspection,contextId);
                measure = NMResultsViewerImagingTools.requireMeasure(inspection,contextId,sp.measureId);
                entries(ii) = NMResultsViewerImagingTools.entryFromDescriptor( ...
                    NM,inspection,ctx,measure,sp,sourceId,structuralFile,structuralExists,selectedGridPolicy);
            end
        end

        function [catalogue,preparedAtlas,contentHash,cacheHit] = resolveAtlasResource(entry, selectedAtlasId, targetReference, profileEnabled, volumeAtlasPath, delimiter, nameColumn, descriptorFile)
            % resolveAtlasResource  Materialize one display atlas without rediscovering canonical ROI identity.
            % Authority and flow: canonical ROI uses exactly its persisted provenance atlas and bypasses the
            % generic atlas catalogue path. The voxel path consumes persisted DataIO atlas resources or one
            % explicitly selected viewer-local atlas; both delegate adjacent ROI descriptor discovery to
            % NMDataIOAtlasDescriptorTools via NMImagingAtlasService.catalogue before cached materialization.
            canonicalROI = strcmpi(entry.featureKind,'roi') && strcmpi(entry.spatialDomain,'volume');
            preparedAtlas = struct(); contentHash = ''; cacheHit = false;
            if canonicalROI
                if ~isempty(volumeAtlasPath)
                    error('NMResultsViewerImagingTools:ImmutableROIAtlas','DataIO-defined ROI atlases cannot be substituted in the Results Viewer.');
                end
                fileName = regexprep(entry.atlasFile,',\d+$','');
                if ~NMDataIOImageFileTools.existsForSPM(fileName)
                    error('NMResultsViewerImagingTools:CanonicalROIAtlasUnavailable', ...
                        'ROI atlas resource is unavailable: %s. Relink the modality resources in DataIO.',fileName);
                end
                catalogue = NMImagingAtlasService.catalogue(fileName,'');
                catalogue(1).atlasId = sprintf('atlas_%s',NMImagingContractTools.stableId(fileName,'canonical_roi_provenance'));
                catalogue(1).provenance = 'canonical_roi_provenance';
                atlasEntry = catalogue(1);
            else
                if ~isempty(volumeAtlasPath)
                    catalogue = NMImagingAtlasService.catalogue(volumeAtlasPath,'',{});
                    catalogue(1).provenance = 'viewer_local_atlas';
                    selectedAtlasId = catalogue(1).atlasId;
                else
                    catalogue = NMImagingAtlasService.catalogue(entry.atlasFile,entry.atlasDescriptorFile,{});
                end
                if isempty(selectedAtlasId) || strcmpi(selectedAtlasId,'none')
                    return;
                end
                selectedIndex = find(strcmp({catalogue.atlasId},selectedAtlasId) & [catalogue.enabled],1,'first');
                if isempty(selectedIndex)
                    error('NMResultsViewerImagingTools:SelectedAtlasUnavailable', ...
                        'Selected atlas "%s" is not available for the current feature context.',selectedAtlasId);
                end
                atlasEntry = catalogue(selectedIndex);
            end
            if ~isempty(descriptorFile)
                if ~any(strcmp(atlasEntry.descriptorCandidates,descriptorFile))
                    error('NMResultsViewerImagingTools:InvalidAtlasDescriptor', ...
                        'The selected ROI description file is not associated with the current atlas.');
                end
                atlasEntry.descriptorFile = descriptorFile;
            end
            atlasEntry.descriptorOptions = struct('delimiter',delimiter,'nameColumn',nameColumn);
            atlasKey = NMImagingContentIdentity.hashText(strjoin({ ...
                'C18b2c',atlasEntry.atlasId,atlasEntry.provenance,NMImagingContentIdentity.fileFingerprint(atlasEntry.file), ...
                targetReference.gridId},'|'));
            [atlasPackage,cacheHit] = NMImagingRuntimeCache.get('atlas',atlasKey);
            if ~cacheHit
                preparedAtlas = NMImagingAtlasService.prepare(atlasEntry,targetReference,profileEnabled);
                atlasPackage = struct('atlas',preparedAtlas, ...
                    'contentHash',NMImagingContentIdentity.hashArray(uint32(preparedAtlas.data),'uint32'));
                NMImagingRuntimeCache.put('atlas',atlasKey,atlasPackage);
            else
                preparedAtlas = atlasPackage.atlas;
                [preparedAtlas.roiLabels,preparedAtlas.labelMessage,preparedAtlas.labelProvenance, ...
                    preparedAtlas.descriptorInfo] = NMImagingAtlasService.resolveLabels(atlasEntry,preparedAtlas.roiIds);
            end
            contentHash = atlasPackage.contentHash;
        end

        function capabilities = volumeCapabilities(canonicalROI)
            % volumeCapabilities  Project scientific provenance onto the existing volumetric control surface.
            %
            % Canonical ROI maps retain ordinary presentation, montage, ROI Mapper and anatomy-surface-depth
            % controls, but prohibit atlas substitution, feature-grid substitution, interpolation/smoothing,
            % TFLSE/projection-support tuning and ROI re-tabulation. This is a bounded metadata operation and
            % is safe on interactive paths; it reads no files and materializes no feature-scale arrays.
            canonicalROI = logical(canonicalROI);
            capabilities = struct('sourceDomain','volume','canonicalROI',canonicalROI, ...
                'displayGridSelection',~canonicalROI,'featureInterpolation',~canonicalROI, ...
                'atlasFileSelection',~canonicalROI, ...
                'roiTable',~canonicalROI,'roiMapper',true, ...
                'montage2D',true,'montage3D',true,'surfaceProjectionControls',~canonicalROI, ...
                'volumeFeatureControls',true,'volumeBoundarySmoothing',~canonicalROI, ...
                'featureSmoothing',~canonicalROI,'anatomySurfaceDepth',true);
        end

        function [mapping,nativePackage,overlayData,indexedOverlays,valuesByMeasure] = ...
                prepareCanonicalROICompact(NM,req,inspection,requestedIds,featurePackage,featureKey,profileEnabled)
            % prepareCanonicalROICompact  Shared compact canonical-ROI feature materialization for open and switch.
            mapping = featurePackage.canonicalROIVolumetricMapping;
            if ~strcmp(mapping.authorityIdentity,featureKey)
                error('NMResultsViewerImagingTools:CanonicalROIMappingAuthorityMismatch', ...
                    'The cached canonical ROI mapping does not belong to the selected feature space.');
            end
            mappingId = NMImagingContentIdentity.hashText(strjoin({ ...
                'canonical_roi_mapping_v1',mapping.materializationIdentity},'|'));
            supportHash = NMImagingContentIdentity.hashText(strjoin({ ...
                'canonical_roi_support_v1',mapping.materializationIdentity},'|'));
            supportData = logical(mapping.lookupIndex > 1);
            nativePackage = NMImagingNativeFeatureSource.initializePrepared( ...
                featurePackage.volume,mappingId,supportData,mapping.supportVoxelCount,supportHash, ...
                'NMDataIOROIProvenanceTools.prepareVolumetricMapping');
            overlayTemplate = struct('measureId','','label','','sourceField','','valuePolarity','signed', ...
                'valueRange',[NaN NaN],'displayDefaults',struct(),'sourceVectorHash','', ...
                'mappingId','','displayContentHash','','data',[]);
            indexedTemplate = struct('measureId','','label','','sourceField','','valuePolarity','signed', ...
                'valueRange',[NaN NaN],'sourceVectorHash','','contentHash','','values',[]);
            overlayData = repmat(overlayTemplate,1,numel(requestedIds));
            indexedOverlays = repmat(indexedTemplate,1,numel(requestedIds));
            valuesByMeasure = cell(1,numel(requestedIds));
            for ii=1:numel(requestedIds)
                tOverlay = tic;
                vectorSpec = req;
                vectorSpec.measureId = requestedIds{ii};
                vector = NMResultsViewerImagingVectorAdapter.resolve(NM,vectorSpec,requestedIds{ii},inspection);
                if ~vector.ok
                    error('NMResultsViewerImagingTools:FeatureVectorUnavailable','%s',vector.message);
                end
                values = double(vector.values(:)');
                sourceVectorHash = NMImagingContentIdentity.hashArray(double(vector.values),'double');
                contentHash = NMImagingContentIdentity.hashText(strjoin({ ...
                    'canonical_roi_indexed_values_v1',mapping.materializationIdentity,sourceVectorHash},'|'));
                displayDefaults = NMImagingColorMapping.defaults(vector.values,vector.measure);
                overlayData(ii).measureId = vector.measure.measureId;
                overlayData(ii).label = vector.measure.label;
                overlayData(ii).sourceField = vector.measure.sourceField;
                overlayData(ii).valuePolarity = vector.measure.valuePolarity;
                overlayData(ii).valueRange = displayDefaults.valueRange;
                overlayData(ii).displayDefaults = displayDefaults;
                overlayData(ii).sourceVectorHash = sourceVectorHash;
                overlayData(ii).mappingId = mappingId;
                overlayData(ii).displayContentHash = contentHash;
                indexedOverlays(ii) = struct('measureId',vector.measure.measureId,'label',vector.measure.label, ...
                    'sourceField',vector.measure.sourceField,'valuePolarity',vector.measure.valuePolarity, ...
                    'valueRange',displayDefaults.valueRange,'sourceVectorHash',sourceVectorHash, ...
                    'contentHash',contentHash,'values',values);
                valuesByMeasure{ii} = values;
                NMResultsViewerImagingTools.profileLog(profileEnabled, ...
                    '[nm-prof]       canonical ROI compact values:      %.3fs (rois=%d denseVoxels=%d)\n', ...
                    toc(tOverlay),double(numel(values)),double(numel(mapping.lookupIndex)));
            end
        end

        function [package,displayDefaults] = appendPreparedNativeOverlay(package,featureMap,values,measure,sourceVectorHash)
            % appendPreparedNativeOverlay  Package an already-validated native feature map without rescanning voxel content.
            displayDefaults = NMImagingColorMapping.defaults(values,measure);
            if isempty(fieldnames(package))
                supportIdentity = NMImagingContentIdentity.hashText(strjoin({ ...
                    'native_support_derivation_v1',featureMap.mappingId},'|'));
                package = NMImagingNativeFeatureSource.initializePrepared( ...
                    featureMap.overlayVolume,featureMap.mappingId,featureMap.supportVolume.data, ...
                    featureMap.supportVoxelCountAfterBadcoords,supportIdentity, ...
                    'NMImagingFeatureMapAdapter.reconstruct');
            end
            overlayIdentity = NMImagingContentIdentity.hashText(strjoin({ ...
                'native_overlay_derivation_v1',featureMap.mappingId,sourceVectorHash},'|'));
            package = NMImagingNativeFeatureSource.addPreparedOverlay( ...
                package,single(featureMap.overlayVolume.data),measure,sourceVectorHash, ...
                overlayIdentity,displayDefaults.valueRange,'NMImagingFeatureMapAdapter.reconstruct');
        end

        function [scaffold,key,cacheHit] = resolveNativeDisplayScaffold( ...
                structuralOriginal,featureVolume,policy,structuralKey,featureKey,mappingId,nativeSupportHash,profileEnabled)
            % resolveNativeDisplayScaffold  Build only the display anatomy/grid for native feature rendering.
            key = NMImagingContentIdentity.hashText(strjoin({ ...
                'C18d4.7a-native-display',policy,structuralKey,featureKey,mappingId},'|'));
            [scaffold,cacheHit] = NMImagingRuntimeCache.get('display_scaffold',key);
            if cacheHit, return; end
            tStage = tic;
            switch policy
                case 'structural_reference'
                    displayStructural = structuralOriginal;
                    displayReference = structuralOriginal.spatialReference;
                case 'feature_reference'
                    displayReference = featureVolume.spatialReference;
                    [displayStructural,~] = NMImagingResampling.resample( ...
                        structuralOriginal,displayReference,'linear',NaN,'structural_display');
                otherwise
                    error('NMResultsViewerImagingTools:UnsupportedDisplayGridPolicy', ...
                        'Unsupported display-grid policy "%s".',policy);
            end
            scaffold = struct( ...
                'structuralVolume',displayStructural, ...
                'spatialReference',displayReference, ...
                'structuralContentHash',NMImagingContentIdentity.hashText(strjoin({ ...
                    'native_structural_display_v1',structuralKey,policy,displayReference.gridId},'|')), ...
                'supportContentHash',nativeSupportHash, ...
                'structuralWindow',NMResultsViewerImagingTools.robustWindow(displayStructural));
            NMImagingRuntimeCache.put('display_scaffold',key,scaffold);
            NMResultsViewerImagingTools.profileLog(profileEnabled, ...
                '[nm-prof]   native interactive display scaffold: %.3fs (policy=%s grid=%s)\n', ...
                toc(tStage),policy,displayReference.gridId);
        end

        function [scaffold,key] = resolveRetainedNativeScaffold( ...
                residentScaffold,nativeSupportHash,structuralKey,featureKey,mappingId,profileEnabled)
            % resolveRetainedNativeScaffold  Retain mounted anatomy/grid and replace only native feature identity.
            key=NMImagingContentIdentity.hashText(strjoin({ ...
                'RV-L3-retained-native-scaffold-v1',structuralKey,featureKey,mappingId, ...
                residentScaffold.spatialReference.gridId},'|'));
            [scaffold,cacheHit]=NMImagingRuntimeCache.get('display_scaffold',key);
            if cacheHit, return; end
            tStage=tic;
            scaffold=residentScaffold;
            scaffold.supportContentHash=nativeSupportHash;
            NMImagingRuntimeCache.put('display_scaffold',key,scaffold);
            NMResultsViewerImagingTools.profileLog(profileEnabled, ...
                '[nm-prof]   retained native display scaffold: %.3fs (grid=%s)\n', ...
                toc(tStage),scaffold.spatialReference.gridId);
        end

        function key = structuralCacheKey(fileName)
            % structuralCacheKey  Identify one immutable structural input file.
            key = NMImagingContentIdentity.hashText(strjoin({ ...
                'structural','C18b2a',NMImagingContentIdentity.fileFingerprint(fileName)},'|'));
        end

        function key = featureSpaceCacheKey(NM,varind,requestedFile)
            % featureSpaceCacheKey  Identify one selected modality's mask grid and selection contract.
            descriptor = NMResultsViewerImagingDescriptorAdapter.resolve(NM,varind,struct());
            if ~descriptor.ok
                error('NMResultsViewerImagingTools:FeatureDescriptorUnavailable','%s',descriptor.message);
            end
            requestedFile = regexprep(requestedFile,',\d+$','');
            sourceIdentity = NMResultsViewerImagingDescriptorAdapter.featureSpaceIdentity( ...
                NM,varind,requestedFile,descriptor);
            selection = descriptor.maskSelection;
            selectionIdentity = sprintf('%s|%.17g|%d', ...
                selection.operator,double(selection.threshold), ...
                double(selection.roundBeforeComparison));
            badIdentity = 'none';
            if ~isempty(descriptor.badcoords)
                badIdentity = NMImagingContentIdentity.hashArray(double(descriptor.badcoords(:)),'double');
            end
            key = NMImagingContentIdentity.hashText(strjoin({ ...
                'feature_space','C18b2a-R4',sprintf('varind=%d',round(double(varind))), ...
                sourceIdentity,selectionIdentity,['bad=' badIdentity]},'|'));
        end

        function profileLog(enabled, varargin)
            % profileLog  Emit one imaging profiling record when enabled.
            if ~enabled, return; end
            try
                fprintf(varargin{:});
            % nm2-allow: profiling diagnostic boundary reports logging failure without altering scientific materialization
            catch ME
                warning('NMResultsViewerImagingTools:ProfileLogFailed', ...
                    'Imaging profiling log failed (%s): %s',ME.identifier,ME.message);
            end
        end

        function entry = entryFromDescriptor(NM,inspection,ctx,measure,sp,sourceId,structuralFile,structuralExists,selectedGridPolicy)
            % entryFromDescriptor  Build one imaging catalogue entry from established feature context state.
            % Authority and flow: ROI atlas identity comes only from the already-validated context projection;
            % non-ROI imaging consumes the descriptor normalized once by the adapter. No arbitrary descriptor traversal occurs.
            % Materialization and performance: metadata-only; reads no atlas/feature arrays and scans no directories.
            entry = NMImagingContractTools.catalogueEntryTemplate();
            entry.featureKind = ctx.featureKind;
            entry.spatialDomain = NMResultsViewerImagingTools.spatialDomain(entry.featureKind);
            if strcmp(entry.featureKind,'roi')
                entry.spatialDomain = ctx.roiSpatialDomain;
            end
            entry.nFeatures = max(0,round(ctx.nFeatures));
            descriptor = struct();
            if ~strcmp(entry.featureKind,'roi')
                descriptor = NMResultsViewerImagingDescriptorAdapter.resolve( ...
                    NM,ctx.varind,struct());
            end
            entry.featureSpaceFile = '';
            entry.featureSpaceFileExists = false;
            entry.featureSpaceEmbeddedAvailable = false;
            entry.featureSpaceSourceKind = 'unavailable';
            entry.featureSpaceProvenance = 'none';
            if ~strcmp(entry.featureKind,'roi')
                entry.featureSpaceFile = sp.maskFile;
                if isempty(entry.featureSpaceFile) && descriptor.ok
                    entry.featureSpaceFile = descriptor.featureSpaceFile;
                end
                entry.featureSpaceFileExists = NMDataIOImageFileTools.existsForSPM(entry.featureSpaceFile);
                entry.featureSpaceEmbeddedAvailable = descriptor.ok && descriptor.embeddedFeatureSpaceAvailable;
                if entry.featureSpaceFileExists
                    entry.featureSpaceSourceKind = 'file';
                    if descriptor.ok && strcmp(entry.featureSpaceFile,descriptor.featureSpaceFile) && ...
                            ~isempty(descriptor.featureSpaceFileProvenance)
                        entry.featureSpaceProvenance = descriptor.featureSpaceFileProvenance;
                    else
                        entry.featureSpaceProvenance = 'spatial_descriptor_mask_file';
                    end
                elseif entry.featureSpaceEmbeddedAvailable
                    entry.featureSpaceSourceKind = 'embedded_datadescriptor';
                    entry.featureSpaceProvenance = descriptor.embeddedFeatureSpaceProvenance;
                end
            end
            entry.structuralReferenceFile = structuralFile;
            entry.structuralReferenceFileExists = structuralExists;
            entry.structuralReferenceProvenance = 'legacy_nm_defs_atlas_path';
            entry.selectedDisplayGridPolicy = selectedGridPolicy;
            entry.measureLabel = measure.label;
            entry.measureSourceField = measure.sourceField;
            entry.valuePolarity = measure.valuePolarity;
            entry.thresholdMode = measure.thresholdMode;
            entry.thresholdLow = measure.thresholdLow;
            entry.thresholdHigh = measure.thresholdHigh;
            entry.thresholdValue = measure.thresholdValue;
            entry.thresholdLabel = measure.thresholdLabel;
            if NMResultsViewerImagingTools.hasRegisteredThreshold(entry)
                entry.thresholdDefaultPolicy = 'registered_metric';
                entry.thresholdProvenance = 'registered_metric';
            else
                entry.thresholdDefaultPolicy = 'percentile_10_90';
                entry.thresholdProvenance = 'percentile_10_90';
            end

            entry.atlasFile = '';
            entry.atlasDescriptorFile = '';
            entry.atlasProvenance = 'none';
            if strcmp(entry.featureKind,'roi')
                if ~ctx.roiSidecarAvailable
                    error('NMResultsViewerImagingTools:CanonicalROIProvenanceUnavailable', ...
                        'ROI imaging catalogue entry requires validated canonical DataIO ROI provenance.');
                end
                if strcmp(entry.spatialDomain,'volume')
                    entry.atlasFile = ctx.roiAtlasFile;
                    if isempty(entry.atlasFile)
                        error('NMResultsViewerImagingTools:CanonicalROIAtlasIdentity', ...
                            'Canonical volumetric ROI context must identify exactly one atlas file.');
                    end
                    entry.atlasProvenance = 'canonical_roi_provenance';
                    entry.featureSpaceFile = entry.atlasFile;
                    entry.featureSpaceFileExists = NMDataIOImageFileTools.existsForSPM(entry.featureSpaceFile);
                    entry.featureSpaceEmbeddedAvailable = false;
                    entry.featureSpaceSourceKind = 'canonical_roi_atlas';
                    entry.featureSpaceProvenance = 'canonical_roi_provenance';
                end
            else
                entry.atlasFile = descriptor.atlasFile;
                entry.atlasDescriptorFile = descriptor.atlasDescriptorFile;
                if ~isempty(entry.atlasFile)
                    entry.atlasProvenance = descriptor.spatialContractProvenance;
                end
            end
            entry.atlasFileExists = NMDataIOImageFileTools.existsForSPM(entry.atlasFile);
            entry.atlasDescriptorFileExists = NMDataIOImageFileTools.existsForSPM(entry.atlasDescriptorFile);

            resolvedSelection = inspection.resolvedSelection;
            identity = NMImagingContractTools.identityTemplate();
            identity.analysisIndex = double(resolvedSelection.analysisIndex);
            identity.resultSourceId = sourceId;
            identity.targetIndex = double(resolvedSelection.targetIndex);
            identity.resultTargetIndex = double(resolvedSelection.resultTargetIndex);
            identity.classifierIndex = double(resolvedSelection.classifierIndex);
            identity.binaryDecompositionId = sprintf('classifier_%d',round(identity.classifierIndex));
            identity.featureContextId = ctx.contextId;
            identity.varind = ctx.varind;
            identity.imagingModalityId = sprintf('%s:varind_%d',identity.featureContextId,round(identity.varind));
            identity.backprojectionComponentId = resolvedSelection.backprojectionComponentId;
            identity.componentIndex = double(resolvedSelection.componentIndex);
            identity.componentPosition = double(resolvedSelection.componentPosition);
            identity.measureId = sp.measureId;
            identity.displayGridPolicy = selectedGridPolicy;
            identity.spatialDomain = entry.spatialDomain;
            identity.contentRevision = NMImagingContractTools.stableId( ...
                identity.analysisIndex,identity.resultSourceId,identity.targetIndex,identity.resultTargetIndex, ...
                identity.classifierIndex,identity.binaryDecompositionId,identity.featureContextId,identity.varind, ...
                identity.backprojectionComponentId,identity.componentIndex,identity.componentPosition,identity.measureId,identity.displayGridPolicy, ...
                entry.featureSpaceFile,entry.featureSpaceSourceKind,entry.featureSpaceProvenance, ...
                entry.structuralReferenceFile,entry.atlasFile,entry.atlasDescriptorFile,'C18b2a');
            identity.payloadId = sprintf('nmimg_%s',identity.contentRevision);
            entry.identity = identity;
            componentToken = identity.backprojectionComponentId;
            if isempty(componentToken), componentToken = 'component_invariant'; end
            entry.imagingEntryId = sprintf('%s:%s:%s',identity.imagingModalityId,componentToken,identity.measureId);
            entry.label = sprintf('%s — %s',ctx.modalityLabel,entry.measureLabel);
            entry.selectionLabel = sprintf('%s | %s',ctx.selectionLabel,entry.measureLabel);

            switch entry.spatialDomain
                case 'volume'
                    featureSpaceAvailable = entry.featureSpaceFileExists || entry.featureSpaceEmbeddedAvailable;
                    entry.orthogonal2DAvailable = entry.nFeatures > 0 && featureSpaceAvailable && structuralExists;
                    entry.enabled = entry.orthogonal2DAvailable;
                    if entry.nFeatures < 1
                        entry.disabledReason = 'The voxel feature source declares no features.';
                    elseif ~featureSpaceAvailable
                        if isempty(entry.featureSpaceFile)
                            entry.disabledReason = ['The voxel feature source declares neither a readable ' ...
                                'space-defining image nor a persisted Vm/Vmvol feature-space payload.'];
                        else
                            entry.disabledReason = sprintf(['The space-defining image is unavailable and no ' ...
                                'persisted Vm/Vmvol payload can replace it: %s'],entry.featureSpaceFile);
                        end
                    elseif isempty(structuralFile)
                        entry.disabledReason = 'NM.defs.atlas_path does not define the legacy structural reference image.';
                    elseif ~structuralExists
                        entry.disabledReason = sprintf('The legacy structural reference image is unavailable: %s',structuralFile);
                    else
                        entry.disabledReason = '';
                    end
                case 'surface'
                    availability = NMResultsViewerSurfaceTools.catalogueAvailability( ...
                        NM,ctx.varind,entry.nFeatures);
                    entry.orthogonal2DAvailable = false;
                    entry.surfaceViewerAvailable = availability.enabled;
                    entry.enabled = availability.enabled;
                    entry.disabledReason = availability.disabledReason;
                case 'roi'
                    entry.enabled = false;
                    entry.disabledReason = 'Canonical ROI provenance did not resolve to volume or surface space.';
                case 'connectivity'
                    entry.enabled = false;
                    entry.disabledReason = 'Connectivity spatial rendering remains handled by the feature-relation graph components, not the volumetric imaging viewer.';
                otherwise
                    entry.enabled = false;
                    entry.disabledReason = 'This feature source has no volume imaging contract.';
            end
        end

        function tf = hasRegisteredThreshold(entry)
            mode = entry.thresholdMode;
            tf = ~strcmp(mode,'none') && (isfinite(entry.thresholdValue) || ...
                isfinite(entry.thresholdLow) || isfinite(entry.thresholdHigh));
        end

        function domain = spatialDomain(featureKind)
            switch featureKind
                case 'voxel'
                    domain = 'volume';
                case 'surface_vertex'
                    domain = 'surface';
                case 'roi'
                    domain = 'roi';
                case 'connectivity_edge'
                    domain = 'connectivity';
                otherwise
                    domain = 'none';
            end
        end

        function ctx = requireContext(inspection,contextId)
            if isempty(inspection.contexts)
                error('NMResultsViewerImagingTools:MissingFeatureContexts', ...
                    'The canonical feature-vector payload contains no physical contexts.');
            end
            hits = find(strcmp({inspection.contexts.contextId},contextId));
            if numel(hits) ~= 1
                error('NMResultsViewerImagingTools:InvalidSpatialContextReference', ...
                    'Spatial context %s resolves to %d canonical physical contexts.', ...
                    contextId,numel(hits));
            end
            ctx = inspection.contexts(hits);
        end

        function measure = requireMeasure(inspection,contextId,measureId)
            if isempty(inspection.measures)
                error('NMResultsViewerImagingTools:MissingFeatureMeasures', ...
                    'The canonical feature-vector payload contains no measures.');
            end
            hits = find(strcmp({inspection.measures.contextId},contextId) & ...
                strcmp({inspection.measures.measureId},measureId));
            if numel(hits) ~= 1
                error('NMResultsViewerImagingTools:InvalidSpatialMeasureReference', ...
                    'Spatial measure %s for context %s resolves to %d canonical measures.', ...
                    measureId,contextId,numel(hits));
            end
            measure = inspection.measures(hits);
        end

        function idx = selectEntry(entries,requestedId)
            idx = 0;
            if isempty(entries), return; end
            requestedId = strtrim(requestedId);
            if ~isempty(requestedId)
                hit = find(strcmp({entries.imagingEntryId},requestedId),1,'first');
                if isempty(hit)
                    hit = find(strcmp(arrayfun(@(x)x.identity.imagingModalityId,entries,'UniformOutput',false),requestedId),1,'first');
                end
                if ~isempty(hit), idx = hit; return; end
            end
            hit = find([entries.enabled],1,'first');
            if isempty(hit), hit = 1; end
            idx = hit;
        end


        function window = robustWindow(volume)
            data = volume.data(:);
            if volume.finiteValueCount == numel(data)
                if numel(data) > 1000000
                    take = unique(round(linspace(1,numel(data),1000000)));
                    values = double(data(take));
                else
                    values = double(data);
                end
            else
                values = double(data(isfinite(data)));
                if numel(values) > 1000000
                    take = unique(round(linspace(1,numel(values),1000000)));
                    values = values(take);
                end
            end
            if isempty(values), window=[0 1]; return; end
            lo=prctile(values,1); hi=prctile(values,99);
            if ~isfinite(lo)||~isfinite(hi)||hi<=lo, lo=min(values); hi=max(values); end
            if hi<=lo, hi=lo+max(eps,abs(lo)*1e-6); end
            window=[double(lo) double(hi)];
        end

    end
end

classdef NMResultsViewerConnectivityAdapter
% NMResultsViewerConnectivityAdapter
% -------------------------------------------------------------------------
% Narrow representation adapter for precomputed connectivity-edge results.
%
% The adapter is downstream of two authoritative contracts:
%   1. NMResultsViewerTools.getModelFeatureInspectionMeasureVector resolves
%      the selected VIS measure/component through the shared Results Viewer
%      pathway.
%   2. NM.datadescriptor{varind}.connectivity defines the retained node and
%      edge space established by DataIO.
%
% It does not inspect raw VIS fields, reopen ROI sidecars, infer node count,
% or repeat DataIO correspondence/localisation checks. Only explicit
% persisted-contract guards required for representation indexing are applied.
%
% Contract version: NM-RESULTS-CONNECTIVITY-C2-V1
% Documentation: docs/NMResultsViewerConnectivityAdapterStageC2.md
% -------------------------------------------------------------------------

    methods (Static)
        function out = anatomyAssets(NM, spec, tmpDir)
            % anatomyAssets  Materialize the selected shared structural template
            % through the existing imaging mesh/cache pathway.
            resolved = NMResultsViewerConnectivityAdapter.resolve(NM,spec,'',[]);
            out = struct('ok',false,'message','','contentId','','anatomyMesh',struct());
            if ~resolved.ok, out.message = resolved.message; return; end
            view = resolved.views.glassBrain;
            if ~view.enabled, out.message = view.disabledReason; return; end
            structuralFile = NMImagingTemplateService.structuralReferenceFile(NM);
            templateCatalogue = NMImagingTemplateService.catalogue( ...
                structuralFile,fileparts(structuralFile),{});
            requestedTemplateId = NMResultsViewerConnectivityAdapter.requestText(spec,'selectedTemplateId','');
            [selectedTemplate,selectedTemplateIndex] = NMImagingTemplateService.select( ...
                templateCatalogue,requestedTemplateId);
            if selectedTemplateIndex == 0 || ~selectedTemplate.enabled
                out.message = 'No enabled structural template is available from the shared NM template catalogue.';
                return;
            end
            % nm2-allow: selected structural template is an external imaging resource requiring SPM loaders
            if exist('spm_vol','file') ~= 2 || exist('spm_read_vols','file') ~= 2
                out.message = 'SPM volume services are required to load the selected structural template.';
                return;
            end
            structuralFile = selectedTemplate.file;
            V = spm_vol(structuralFile);
            if numel(V) ~= 1
                out.message = 'The selected structural template must be one three-dimensional volume.';
                return;
            end
            structural = spm_read_vols(V);
            support = isfinite(structural) & structural ~= 0;
            if nnz(support) < 8
                out.message = 'The selected structural template contains no nondegenerate anatomical envelope.';
                return;
            end
            reference = NMImagingSpatialReference.fromVolume(V);
            contentId = NMImagingContentIdentity.hashText(strjoin( ...
                {'G6B-R1','shared_structural_template_envelope', ...
                 NMImagingContentIdentity.fileFingerprint(structuralFile),reference.gridId},'|'));
            [cached,hit] = NMImagingRuntimeCache.get('mesh3d',contentId);
            if hit
                mesh = cached.mesh;
            else
                [foregroundMask,maskProvenance] = NMImagingMeshService.prepareAnatomyMask( ...
                    structural,reference,struct('surfaceDepthMm',0));
                mesh = NMImagingMeshService.prepareAnatomyMesh( ...
                    foregroundMask,reference,struct('quality','balanced'),maskProvenance);
                cached = struct('mesh',mesh,'foregroundMask',foregroundMask);
                NMImagingRuntimeCache.put('mesh3d',contentId,cached);
            end
            foregroundMask = cached.foregroundMask;
            package = NMImagingMeshAssetCache.write(tmpDir,contentId,mesh,foregroundMask);
            out.ok = true;
            out.message = sprintf('Prepared shared structural template %s (%d vertices, %d faces; cacheHit=%d).', ...
                selectedTemplate.label, ...
                mesh.vertexCount,mesh.faceCount,double(hit));
            out.contentId = contentId;
            out.coordinateSpace = 'world_mm';
            out.anatomyMesh = struct('available',true,'verticesUrl',package.verticesUrl, ...
                'normalsUrl',package.normalsUrl,'indicesUrl',package.indicesUrl, ...
                'vertexCount',mesh.vertexCount,'faceCount',mesh.faceCount, ...
                'boundsWorldMm',mesh.boundsWorldMm,'templateId',selectedTemplate.templateId, ...
                'templateLabel',selectedTemplate.label,'structuralFile',structuralFile);
        end

        function out = resolve(NM, spec, measureId, inspection)
            % resolve  Resolve the shared feature vector and adapt it to the
            % authoritative persisted connectivity descriptor.
            base = NMResultsViewerTools.getModelFeatureInspectionMeasureVector( ...
                NM, spec, measureId, inspection);
            if ~base.ok
                out = NMResultsViewerConnectivityAdapter.template();
                out.message = base.message;
                out.analysisIndex = base.analysisIndex;
                out.targetIndex = base.targetIndex;
                out.resultTargetIndex = base.resultTargetIndex;
                out.classifierIndex = base.classifierIndex;
                out.context = base.context;
                out.measure = base.measure;
                out.spatialMap = base.spatialMap;
                out.component = base.component;
                return;
            end

            varind = base.context.varind;
            if varind < 1
                error('NMResultsViewerConnectivityAdapter:InvalidModalityIndex', ...
                    'Canonical connectivity context has invalid modality index %g.',varind);
            end
            if varind > numel(NM.datadescriptor)
                out = NMResultsViewerConnectivityAdapter.template();
                out.message = sprintf(['The selected connectivity context refers to modality %g, ' ...
                    'but no corresponding DataIO descriptor is available.'], varind);
                out = NMResultsViewerConnectivityAdapter.copyResolvedMetadata(out,base);
                return;
            end
            out = NMResultsViewerConnectivityAdapter.build(base,NM.datadescriptor{varind}.connectivity);
            structuralFile = NMImagingTemplateService.structuralReferenceFile(NM);
            out.templateCatalogue = NMImagingTemplateService.catalogue( ...
                structuralFile,fileparts(structuralFile),{});
            requestedTemplateId = NMResultsViewerConnectivityAdapter.requestText(spec,'selectedTemplateId','');
            [selectedTemplate,selectedTemplateIndex] = NMImagingTemplateService.select( ...
                out.templateCatalogue,requestedTemplateId);
            if selectedTemplateIndex > 0
                out.selectedTemplate = selectedTemplate;
            end
        end

        function out = build(resolved, connectivity)
            if NMResultsViewerScientificCapability.isQuery(resolved)
                p=[NMResultsViewerScientificCapability.provide('connectivity_payload','scientific_artefact','connectivity','connectivity_payload'), ...
                    NMResultsViewerScientificCapability.provide('connectivity_matrix','visualization','',''), ...
                    NMResultsViewerScientificCapability.provide('connectivity_network','visualization','',''), ...
                    NMResultsViewerScientificCapability.provide('connectivity_glass_brain','visualization','','')];
                out=NMResultsViewerScientificCapability.contract('connectivity_payload',{{'connectivity_feature_map'}},p); return;
            end
            % build  Adapt an already-resolved Results Viewer vector and one
            % authoritative DataIO connectivity descriptor.
            out = NMResultsViewerConnectivityAdapter.template();
            out = NMResultsViewerConnectivityAdapter.copyResolvedMetadata(out,resolved);
            if ~resolved.ok
                out.message = resolved.message;
                return;
            end
            featureKind = resolved.context.featureKind;
            if ~strcmp(featureKind,'connectivity_edge')
                out.message = sprintf(['Connectivity representation requires a connectivity_edge ' ...
                    'feature context; the selected context is "%s".'], featureKind);
                return;
            end

            [core, message] = NMResultsViewerConnectivityAdapter.normaliseDescriptor(connectivity);
            if ~core.ok
                out.message = message;
                return;
            end

            values = double(resolved.values(:));
            if numel(values) ~= core.nEdges
                out.message = sprintf(['Persisted connectivity provenance contains %g edge(s), but the ' ...
                    'shared Results Viewer resolver returned %g feature value(s). This is an internal ' ...
                    'provenance-integrity error; the viewer will not infer or remap the edge space.'], ...
                    core.nEdges,numel(values));
                return;
            end

            nodeRows = repmat(NMResultsViewerConnectivityAdapter.nodeRowTemplate(),1,core.nNodes);
            for ii = 1:core.nNodes
                nodeRows(ii).nodePosition = double(ii);
                nodeRows(ii).nodeId = core.nodeIdText{ii};
                nodeRows(ii).label = core.nodeLabels{ii};
                nodeRows(ii).x = core.nodeCoordinates(ii,1);
                nodeRows(ii).y = core.nodeCoordinates(ii,2);
                nodeRows(ii).z = core.nodeCoordinates(ii,3);
                nodeRows(ii).coordinateSource = core.nodeCoordinateSource{ii};
                nodeRows(ii).coordinateSpace = core.nodeCoordinateSpace;
                nodeRows(ii).coordinateUnits = core.nodeCoordinateUnits;
            end

            displayDefaults = NMImagingColorMapping.defaults(values,out.measure);

            featurePositions = (1:core.nEdges)';
            edgeIds = arrayfun(@(position)sprintf('connectivity_edge_%d',position), ...
                featurePositions,'UniformOutput',false);
            selectionMap = struct( ...
                'identity','feature_position_equals_persisted_edge_position', ...
                'featurePositions',featurePositions, ...
                'edgePositions',featurePositions, ...
                'sourceNodePositions',core.edgeIndex(:,1), ...
                'targetNodePositions',core.edgeIndex(:,2));

            matrixOptions = struct('matrixType',core.matrixType);
            matrixValues = NMDataIOConnectivityTools.edgeVectorToMatrix( ...
                values,core.edgeIndex,core.nNodes,matrixOptions);
            edgePositionMatrix = NMDataIOConnectivityTools.edgeVectorToMatrix( ...
                featurePositions,core.edgeIndex,core.nNodes,matrixOptions);
            presentMask = isfinite(edgePositionMatrix) & edgePositionMatrix > 0;
            missingMask = presentMask & isnan(matrixValues);
            finiteMask = presentMask & isfinite(matrixValues);
            zeroMask = finiteMask & matrixValues == 0;
            matrixRepresentation = struct( ...
                'viewerMode','connectivity_matrix', ...
                'available',true, ...
                'nRows',core.nNodes, ...
                'nColumns',core.nNodes, ...
                'values',matrixValues, ...
                'edgePositions',edgePositionMatrix, ...
                'presentMask',presentMask, ...
                'missingMask',missingMask, ...
                'zeroMask',zeroMask, ...
                'diagonalMask',logical(eye(core.nNodes)), ...
                'nodePositions',(1:core.nNodes)', ...
                'nodeIDs',{reshape(core.nodeIdText,[],1)}, ...
                'nodeLabels',{reshape(core.nodeLabels,[],1)}, ...
                'axisTitleX','Target ROI', ...
                'axisTitleY','Source ROI', ...
                'symmetric',~strcmp(core.matrixType,'directed'), ...
                'sourceOrder','dataio_sidecar_order', ...
                'nPresentCells',nnz(presentMask), ...
                'nMissingCells',nnz(missingMask), ...
                'nZeroCells',nnz(zeroMask));

            matrixView = NMResultsViewerConnectivityAdapter.viewTemplate( ...
                'connectivity_matrix','ROI-by-ROI matrix',true,'');
            matrixView.requiresNodeCoordinates = false;
            matrixView.materialized = true;
            networkView = NMResultsViewerConnectivityAdapter.viewTemplate( ...
                'connectivity_network_2d','2-D anatomical network',true,'');
            networkView.requiresNodeCoordinates = false;
            networkView.materialized = true;
            glassEnabled = core.hasCompleteNodeCoordinates;
            glassReason = '';
            if ~glassEnabled
                glassReason = ['The persisted connectivity descriptor does not contain finite ' ...
                    'coordinates for every retained node.'];
            end
            glassView = NMResultsViewerConnectivityAdapter.viewTemplate( ...
                'connectivity_glass_brain','3-D glass brain',glassEnabled,glassReason);
            glassView.requiresNodeCoordinates = true;

            out.ok = true;
            out.message = sprintf(['Connectivity representation adapter resolved %g retained node(s) ' ...
                'and %g persisted edge feature(s) for measure %s.'], ...
                core.nNodes,core.nEdges,out.measure.measureId);
            out.representationId = sprintf('%s:%s',out.context.contextId,out.measure.measureId);
            out.nNodes = core.nNodes;
            out.nEdges = core.nEdges;
            out.matrixType = core.matrixType;
            out.triangle = core.triangle;
            out.includeDiagonal = core.includeDiagonal;
            out.vectorizationOrder = core.vectorizationOrder;
            out.nodeCoordinateSpace = core.nodeCoordinateSpace;
            out.nodeCoordinateUnits = core.nodeCoordinateUnits;
            out.hasCompleteNodeCoordinates = core.hasCompleteNodeCoordinates;
            out.nodeIDs = core.nodeIDs;
            out.nodeLabels = core.nodeLabels;
            out.nodeCoordinates = core.nodeCoordinates;
            out.nodeCoordinateSource = core.nodeCoordinateSource;
            out.nodeRows = nodeRows;
            out.groupingColumns = core.groupingColumns;
            out.edgeIndex = core.edgeIndex;
            out.edgeIds = reshape(edgeIds,[],1);
            out.edgeNames = core.edgeNames;
            out.values = values;
            out.valueMissingMask = isnan(values);
            out.displayDefaults = displayDefaults;
            out.featurePositions = featurePositions;
            out.selectionMap = selectionMap;
            out.matrix = matrixRepresentation;
            out.views = struct('matrix',matrixView,'network2D',networkView,'glassBrain',glassView);
            out.provenance = struct( ...
                'sourceFamily',core.sourceFamily, ...
                'sourceFormat',core.sourceFormat, ...
                'atlasFile',core.atlasFile, ...
                'atlasLabelFile',core.atlasLabelFile, ...
                'atlasLocalizationUsed',core.atlasLocalizationUsed, ...
                'originalNNodes',core.originalNNodes, ...
                'retainedNodeMask',core.retainedNodeMask, ...
                'retainedOriginalEdgeMask',core.retainedOriginalEdgeMask);
        end

        function summary = descriptorSummary(NM, varind)
            % descriptorSummary  Return compact representation availability
            % directly from the persisted DataIO connectivity descriptor.
            summary = NMResultsViewerConnectivityAdapter.summaryTemplate();
            varind = double(varind);
            if ~isscalar(varind) || ~isfinite(varind) || varind ~= round(varind)
                error('NMResultsViewerConnectivityAdapter:InvalidModalityIndex', ...
                    'Connectivity descriptor summary requires one finite integer modality index.');
            end
            summary.varind = varind;
            if varind < 1
                summary.message = sprintf('No DataIO descriptor is available for modality %g.',varind);
                return;
            end
            if varind > numel(NM.datadescriptor)
                summary.message = sprintf('No DataIO descriptor is available for modality %g.',varind);
                return;
            end
            [core,message] = NMResultsViewerConnectivityAdapter.normaliseDescriptor( ...
                NM.datadescriptor{varind}.connectivity);
            summary.message = message;
            if ~core.ok, return; end
            summary.ok = true;
            summary.message = sprintf('Persisted connectivity descriptor contains %g node(s) and %g edge(s).',core.nNodes,core.nEdges);
            summary.nNodes = core.nNodes;
            summary.nEdges = core.nEdges;
            summary.edgeNames = core.edgeNames;
            summary.matrixType = core.matrixType;
            summary.triangle = core.triangle;
            summary.includeDiagonal = core.includeDiagonal;
            summary.vectorizationOrder = core.vectorizationOrder;
            summary.hasCompleteNodeCoordinates = core.hasCompleteNodeCoordinates;
            summary.nodeCoordinateSpace = core.nodeCoordinateSpace;
            summary.nodeCoordinateUnits = core.nodeCoordinateUnits;
            summary.atlasFile = core.atlasFile;
            summary.atlasLabelFile = core.atlasLabelFile;
            summary.atlasLocalizationUsed = core.atlasLocalizationUsed;
        end
    end

    methods (Static, Access = private)
        function out = template()
            out = struct( ...
                'schema','NMResultsViewerConnectivityRepresentation', ...
                'schemaVersion',1, ...
                'contractVersion','NM-RESULTS-CONNECTIVITY-C2-V1', ...
                'ok',false, ...
                'message','', ...
                'scientificContractVersion','', ...
                'scientificAnnotation',struct(), ...
                'resolvedSelection',struct(), ...
                'representationId','', ...
                'analysisIndex',0, ...
                'targetIndex',0, ...
                'resultTargetIndex',NaN, ...
                'classifierIndex',0, ...
                'context',struct(), ...
                'measure',struct(), ...
                'spatialMap',struct(), ...
                'component',struct(), ...
                'nNodes',0, ...
                'nEdges',0, ...
                'matrixType','', ...
                'triangle','', ...
                'includeDiagonal',false, ...
                'vectorizationOrder','', ...
                'nodeCoordinateSpace','', ...
                'nodeCoordinateUnits','', ...
                'hasCompleteNodeCoordinates',false, ...
                'nodeIDs',[], ...
                'nodeLabels',{{}}, ...
                'nodeCoordinates',zeros(0,3), ...
                'nodeCoordinateSource',{{}}, ...
                'nodeRows',repmat(NMResultsViewerConnectivityAdapter.nodeRowTemplate(),1,0), ...
                'groupingColumns',repmat(NMResultsViewerConnectivityAdapter.groupingColumnTemplate(),1,0), ...
                'edgeIndex',zeros(0,2), ...
                'edgeIds',{{}}, ...
                'edgeNames',{{}}, ...
                'values',[], ...
                'valueMissingMask',false(0,1), ...
                'displayDefaults',struct(), ...
                'featurePositions',[], ...
                'selectionMap',struct(), ...
                'matrix',NMResultsViewerConnectivityAdapter.matrixTemplate(), ...
                'views',struct(), ...
                'provenance',struct());
        end

        function summary = summaryTemplate()
            summary = struct( ...
                'ok',false,'message','','varind',0, ...
                'nNodes',0,'nEdges',0,'edgeNames',{{}},'matrixType','','triangle','', ...
                'includeDiagonal',false,'vectorizationOrder','', ...
                'hasCompleteNodeCoordinates',false, ...
                'nodeCoordinateSpace','','nodeCoordinateUnits','', ...
                'atlasFile','','atlasLabelFile','','atlasLocalizationUsed',false);
        end


        function matrix = matrixTemplate()
            matrix = struct( ...
                'viewerMode','connectivity_matrix', ...
                'available',false, ...
                'nRows',0, ...
                'nColumns',0, ...
                'values',zeros(0,0), ...
                'edgePositions',zeros(0,0), ...
                'presentMask',false(0,0), ...
                'missingMask',false(0,0), ...
                'zeroMask',false(0,0), ...
                'diagonalMask',false(0,0), ...
                'nodePositions',[], ...
                'nodeIDs',{{}}, ...
                'nodeLabels',{{}}, ...
                'axisTitleX','Target ROI', ...
                'axisTitleY','Source ROI', ...
                'symmetric',false, ...
                'sourceOrder','dataio_sidecar_order', ...
                'nPresentCells',0, ...
                'nMissingCells',0, ...
                'nZeroCells',0);
        end

        function row = nodeRowTemplate()
            row = struct('nodePosition',0,'nodeId','','label','', ...
                'x',NaN,'y',NaN,'z',NaN,'coordinateSource','', ...
                'coordinateSpace','','coordinateUnits','');
        end

        function column = groupingColumnTemplate()
            column = struct('columnId','','label','','values',{{}},'nGroups',0);
        end

        function view = viewTemplate(viewerMode,label,enabled,disabledReason)
            view = struct('viewerMode',viewerMode, ...
                'label',label, ...
                'enabled',enabled, ...
                'disabledReason',disabledReason, ...
                'requiresNodeCoordinates',false, ...
                'materialized',false);
        end

        function out = copyResolvedMetadata(out,resolved)
            out.scientificContractVersion = resolved.scientificContractVersion;
            out.scientificAnnotation = resolved.scientificAnnotation;
            out.resolvedSelection = resolved.resolvedSelection;
            out.analysisIndex = resolved.analysisIndex;
            out.targetIndex = resolved.targetIndex;
            out.resultTargetIndex = resolved.resultTargetIndex;
            out.classifierIndex = resolved.classifierIndex;
            out.context = resolved.context;
            out.measure = resolved.measure;
            out.spatialMap = resolved.spatialMap;
            out.component = resolved.component;
        end

        function [core,message] = normaliseDescriptor(conn)
            core = struct('ok',false,'nNodes',0,'nEdges',0, ...
                'nodeIDs',[],'nodeIdText',{{}},'nodeLabels',{{}}, ...
                'nodeCoordinates',zeros(0,3),'nodeCoordinateSource',{{}}, ...
                'groupingColumns',repmat(NMResultsViewerConnectivityAdapter.groupingColumnTemplate(),1,0), ...
                'nodeCoordinateSpace','','nodeCoordinateUnits','', ...
                'hasCompleteNodeCoordinates',false,'edgeIndex',zeros(0,2), ...
                'edgeNames',{{}},'matrixType','','triangle','', ...
                'includeDiagonal',false,'vectorizationOrder','', ...
                'sourceFamily','','sourceFormat','','atlasFile','', ...
                'atlasLabelFile','','atlasLocalizationUsed',false, ...
                'originalNNodes',0,'retainedNodeMask',[], ...
                'retainedOriginalEdgeMask',[]);
            message = '';

            nNodes = double(conn.nNodes);
            nEdges = double(conn.nEdges);
            if nNodes < 1 || nEdges < 1 || nNodes ~= round(nNodes) || nEdges ~= round(nEdges)
                message = 'The persisted connectivity descriptor has invalid nNodes/nEdges values.';
                return;
            end
            edgeIndex = double(conn.edgeIndex);
            if size(edgeIndex,1) ~= nEdges
                message = sprintf(['Persisted edgeIndex must have %g row(s); received size %s.'], ...
                    nEdges,mat2str(size(edgeIndex)));
                return;
            end
            if size(edgeIndex,2) ~= 2
                message = sprintf('Persisted edgeIndex must have two columns; received size %s.', ...
                    mat2str(size(edgeIndex)));
                return;
            end
            if any(~isfinite(edgeIndex(:))) || any(edgeIndex(:) < 1) || ...
                    any(edgeIndex(:) > nNodes) || any(abs(edgeIndex(:)-round(edgeIndex(:))) > 1e-10)
                message = 'Persisted edgeIndex contains invalid retained node-position indices.';
                return;
            end
            edgeIndex = round(edgeIndex);

            nodeIDs = double(conn.nodeIDs(:));
            if numel(nodeIDs) ~= nNodes
                message = sprintf('Persisted nodeIDs contain %g item(s), but nNodes is %g.',numel(nodeIDs),nNodes);
                return;
            end
            nodeIdText = arrayfun(@(value)sprintf('%.15g',value),nodeIDs,'UniformOutput',false);
            nodeLabels = reshape(conn.nodeLabels,[],1);
            if numel(nodeLabels) ~= nNodes
                message = sprintf('Persisted nodeLabels contain %g item(s), but nNodes is %g.',numel(nodeLabels),nNodes);
                return;
            end
            edgeNames = reshape(conn.edgeNames,[],1);
            if numel(edgeNames) ~= nEdges
                message = sprintf('Persisted edgeNames contain %g item(s), but nEdges is %g.',numel(edgeNames),nEdges);
                return;
            end
            coordinates = double(conn.nodeCoordinates);
            if ~isequal(size(coordinates),[nNodes 3])
                message = sprintf(['Persisted nodeCoordinates must be %g-by-3; received size %s.'], ...
                    nNodes,mat2str(size(coordinates)));
                return;
            end
            coordinateSource = reshape(conn.nodeCoordinateSource,[],1);
            if numel(coordinateSource) ~= nNodes
                message = sprintf(['Persisted nodeCoordinateSource contains %g item(s), ' ...
                    'but nNodes is %g.'],numel(coordinateSource),nNodes);
                return;
            end

            core.ok = true;
            core.nNodes = nNodes;
            core.nEdges = nEdges;
            core.nodeIDs = reshape(nodeIDs,1,[]);
            core.nodeIdText = reshape(nodeIdText,[],1);
            core.nodeLabels = nodeLabels;
            core.nodeCoordinates = coordinates;
            core.nodeCoordinateSource = coordinateSource;
            core.groupingColumns = NMResultsViewerConnectivityAdapter.groupingColumns(conn.nodeTable,nNodes);
            core.nodeCoordinateSpace = conn.nodeCoordinateSpace;
            core.nodeCoordinateUnits = conn.nodeCoordinateUnits;
            core.hasCompleteNodeCoordinates = all(all(isfinite(core.nodeCoordinates),2));
            core.edgeIndex = edgeIndex;
            core.edgeNames = edgeNames;
            core.matrixType = conn.matrixType;
            core.triangle = conn.triangle;
            core.includeDiagonal = logical(conn.includeDiagonal);
            core.vectorizationOrder = conn.vectorizationOrder;
            core.sourceFamily = conn.sourceFamily;
            core.sourceFormat = conn.sourceFormat;
            core.atlasFile = conn.atlasFile;
            core.atlasLabelFile = conn.atlasLabelFile;
            core.atlasLocalizationUsed = logical(conn.atlasLocalizationUsed);
            core.originalNNodes = double(conn.originalNNodes);
            core.retainedNodeMask = logical(conn.retainedNodeMask);
            core.retainedOriginalEdgeMask = logical(conn.retainedOriginalEdgeMask);
            message = 'Persisted connectivity descriptor is representation-ready.';
        end

        function value = requestText(s,name,defaultValue)
            value = defaultValue;
            % nm2-allow: public connectivity representation request boundary owns optional template selectors
            if isfield(s,name) && ~isempty(s.(name))
                raw = s.(name);
                % nm2-allow: public connectivity representation request boundary accepts MATLAB scalar string transport
                if isstring(raw)
                    if ~isscalar(raw)
                        error('NMResultsViewerConnectivityAdapter:InvalidRequestText', ...
                            'Connectivity request field %s must be scalar text.',name);
                    end
                    value = char(raw);
                % nm2-allow: public connectivity representation request boundary accepts MATLAB character-row transport
                elseif ischar(raw) && size(raw,1) == 1
                    value = raw;
                else
                    error('NMResultsViewerConnectivityAdapter:InvalidRequestText', ...
                        'Connectivity request field %s must be scalar text.',name);
                end
            end
        end

        function columns = groupingColumns(nodeTable,nNodes)
            % groupingColumns  Project categorical sidecar metadata without creating a second node table.
            %
            % Scientific contract:
            %   Row order is the retained DataIO node order. Unique identifier/label
            %   columns and continuous coordinate columns are excluded because they do
            %   not define meaningful categorical groups. Blank values remain explicit.
            %
            % Side effects: none.
            columns = repmat(NMResultsViewerConnectivityAdapter.groupingColumnTemplate(),1,0);
            if height(nodeTable) ~= nNodes
                error('NMResultsViewerConnectivityAdapter:InvalidNodeTable', ...
                    'Persisted connectivity nodeTable must contain one row per retained node.');
            end
            names = nodeTable.Properties.VariableNames;
            for ii = 1:numel(names)
                token = lower(regexprep(names{ii},'[^a-zA-Z0-9]',''));
                excluded = {'id','nodeid','nodeidentifier','label','nodelabel', ...
                    'name','nodename','roi','roiid','roilabel','index','nodeindex', ...
                    'position','nodeposition','x','y','z','mnix','mniy','mniz'};
                if ismember(token,excluded) || contains(token,'coordinate')
                    continue;
                end
                % nm2-allow: DataIO connectivity nodeTable deliberately preserves heterogeneous metadata column types
                values = cellstr(string(nodeTable.(names{ii})(:)));
                if numel(values) ~= nNodes
                    error('NMResultsViewerConnectivityAdapter:InvalidNodeMetadataAxis', ...
                        'Persisted node metadata column %s does not match the retained node axis.',names{ii});
                end
                values = cellfun(@strtrim,values,'UniformOutput',false);
                nonempty = values(~cellfun(@isempty,values));
                groups = unique(nonempty,'stable');
                if numel(groups) < 2
                    continue;
                end
                if numel(groups) >= nNodes
                    continue;
                end
                if numel(groups) > 64
                    continue;
                end
                column = NMResultsViewerConnectivityAdapter.groupingColumnTemplate();
                column.columnId = names{ii};
                column.label = regexprep(names{ii},'[_-]+',' ');
                column.values = reshape(values,[],1);
                column.nGroups = numel(groups) + double(numel(nonempty) < nNodes);
                columns(end+1) = column; %#ok<AGROW>
            end
        end
    end
end

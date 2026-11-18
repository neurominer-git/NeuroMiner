classdef NMDataIOConnectivityTools
% NMDataIOConnectivityTools
% -------------------------------------------------------------------------
% Backend-only normalization helpers for connectivity-matrix DataIO.
%
% Connectivity import scope:
%   - resolve the ROI sidecar as authoritative node identity/order provenance;
%   - use sidecar MNI coordinates directly and a labelled atlas only as a
%     localization fallback for unresolved nodes;
%   - vectorize 3-D arrays, vectorized edge matrices/tables, and
%     file-per-subject square MAT/CSV matrices into subjects-by-edges form;
%   - derive stable edge feature names from atlas/node labels;
%   - hand the resolved feature payload to generic DataIO for Case-ID matching,
%     labels, covariates, globals, label normalization and transfer counts.
%
% This class does not mutate NM and does not commit modalities. Later API/UI
% patches should hand connOut.Y / connOut.featnames / connOut.caseIDs to the
% existing matrix import pathway and persist connOut.provenance.
% -------------------------------------------------------------------------

    methods (Static)
        function out = inspectTableSchema(tableValue)
            % inspectTableSchema  Report row-name and variable roles for a MATLAB connectivity table.
            out = struct('ok',false,'rowNamesPresent',false,'nRows',0,'nVariables',0, ...
                'variableNames',{{}},'numericVariableNames',{{}},'message','Connectivity table not inspected.');
            try
                T = tableValue;
                if ischar(T) || (isstring(T) && isscalar(T))
                    T = NMDataIOConnectivityTools.resolveNamedValue(T);
                end
                if ~istable(T)
                    out.message = 'Selected connectivity input does not resolve to a MATLAB table.';
                    return;
                end
                out.nRows = double(height(T));
                out.nVariables = double(width(T));
                out.variableNames = T.Properties.VariableNames;
                out.rowNamesPresent = ~isempty(T.Properties.RowNames);
                numeric = false(1,width(T));
                for i = 1:width(T)
                    v = T.(T.Properties.VariableNames{i});
                    numeric(i) = isnumeric(v) || islogical(v);
                end
                out.numericVariableNames = T.Properties.VariableNames(numeric);
                out.ok = true;
                if out.rowNamesPresent
                    out.message = sprintf('Connectivity table has %g rows and %g variables. Case IDs will be read from table row names; no separate Case-ID variable is needed.', out.nRows, out.nVariables);
                else
                    out.message = sprintf('Connectivity table has %g rows and %g variables but no row names. Select the Case-ID variable from the table; text and cell-array variables are supported.', out.nRows, out.nVariables);
                end
            catch ME
                out.ok = false;
                out.message = sprintf('Connectivity table inspection failed: %s', ME.message);
            end
        end

        function out = inspectNodeLocalization(spec)
            % inspectNodeLocalization  Inspect connectivity sidecar coordinates and optional atlas fallback.
            if nargin < 1 || isempty(spec), spec = struct(); end
            spec = NMDataIOConnectivityTools.normalizeSpec(spec);
            opts = struct('delimiter',spec.atlasLabelDelimiter,'hasHeader',spec.atlasLabelHasHeader, ...
                'idColumn',spec.atlasLabelIDColumn,'nameColumn',spec.atlasLabelNameColumn, ...
                'xColumn',spec.atlasLabelXColumn,'yColumn',spec.atlasLabelYColumn,'zColumn',spec.atlasLabelZColumn, ...
                'coordinateSpace',spec.nodeCoordinateSpace,'coordinateUnits',spec.nodeCoordinateUnits);
            out = NMDataIOAtlasDescriptorTools.inspectNodeDescriptor(spec.atlasLabelFile, opts);
            out.atlasMatchSummary = struct('status','not_required','nSidecarIDs',double(NMDataIOConnectivityTools.fieldOr(out,'nRows',0)), ...
                'nMatched',0,'missingSidecarIDs',[],'atlasOnlyIDs',[]);
            out.localizationSummary = struct('status','none','nNodes',double(NMDataIOConnectivityTools.fieldOr(out,'nRows',0)), ...
                'nLocalized',double(NMDataIOConnectivityTools.fieldOr(NMDataIOConnectivityTools.fieldOr(out,'coordinateSummary',struct()),'nValid',0)), ...
                'nDropped',0,'atlasRequired',false);
            if ~NMDataIOConnectivityTools.fieldOr(out,'ok',false), return; end
            coordSummary = NMDataIOConnectivityTools.fieldOr(out,'coordinateSummary',struct());
            if strcmp(NMDataIOConnectivityTools.fieldOr(coordSummary,'status','none'),'full')
                out.localizationSummary.status = 'full';
                out.localizationSummary.nLocalized = out.nRows;
                out.localizationSummary.atlasRequired = false;
                return;
            end
            out.localizationSummary.atlasRequired = true;
            if isempty(spec.atlasFile), return; end
            atlas = NMDataIOAtlasDescriptorTools.atlasNodeCoordinates(spec.atlasFile, out.nodeIDs);
            out.atlasLocalization = atlas;
            matched = logical(NMDataIOConnectivityTools.fieldOr(atlas,'matchedMask',false(1,out.nRows)));
            atlasIDs = double(NMDataIOConnectivityTools.fieldOr(atlas,'atlasIDs',[]));
            if ~NMDataIOConnectivityTools.fieldOr(atlas,'ok',false) && isempty(atlasIDs)
                out.atlasMatchSummary = struct('status','unreadable','nSidecarIDs',double(out.nRows), ...
                    'nMatched',0,'missingSidecarIDs',out.nodeIDs,'atlasOnlyIDs',[]);
                out.localizationSummary.status = 'none';
                out.message = sprintf('%s %s', out.message, NMDataIOConnectivityTools.fieldOr(atlas,'message','Labelled atlas could not be inspected.'));
                out.ok = false;
                return;
            end
            out.atlasMatchSummary = NMDataIOConnectivityTools.atlasMatchSummary(out.nodeIDs, atlasIDs, matched);
            if ~any(matched)
                out.localizationSummary.status = 'none';
                out.message = sprintf('%s The labelled atlas and ROI description file do not contain any matching ROI IDs.', out.message);
                out.ok = false;
                return;
            end
            sidecarValid = all(isfinite(out.nodeCoordinates),2);
            atlasCoords = NMDataIOConnectivityTools.fieldOr(atlas,'coordinates',nan(out.nRows,3));
            atlasValid = matched(:) & all(isfinite(atlasCoords),2);
            localized = sidecarValid | atlasValid;
            out.localizationSummary.nLocalized = double(nnz(localized));
            out.localizationSummary.nDropped = double(nnz(~localized));
            if all(localized), out.localizationSummary.status = 'full'; else, out.localizationSummary.status = 'partial'; end
        end

        function [connOut, messages] = resolveConnectivityPayload(spec, progressTask)
            % resolveConnectivityPayload  Resolve a connectivity spec into vectorized subject-by-edge data and provenance.
            %
            % Consumes spec and an optional progress task; returns connOut, messages.
            % It preserves the connectivity edge-space contract so training, OOCV, QC, and results viewers use the same feature order.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            messages = NMDataIOMessageTools.emptyMessages();
            connOut = NMDataIOConnectivityTools.emptyOutput();
            if nargin < 1 || isempty(spec), spec = struct(); end
            if nargin < 2 || isempty(progressTask), progressTask = NMProgressTools.emptyTaskForLocalUse(); end
            if ~isstruct(spec)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.spec', 'Connectivity spec must be a struct.', 1, 'red*')];
                return;
            end
            spec = NMDataIOConnectivityTools.normalizeSpec(spec);
            baseStart = progressTask.phaseStart;
            baseEnd = progressTask.phaseEnd;
            baseSpan = max(0, baseEnd - baseStart);
            progressTask = NMProgressTools.setIndeterminate(progressTask, 'Reading the connectivity source data.', 'connectivity_resolve_source');

            [data, sourceFormat, caseIDs, fileInfo, readMessages] = NMDataIOConnectivityTools.resolveRawPayload(spec);
            messages = [messages; readMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if isempty(data)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.payload', 'No connectivity data were found.', 1, 'red*')];
                return;
            end

            progressTask = NMProgressTools.phase(progressTask, 'connectivity_resolve_edges', baseStart + 0.18*baseSpan, baseStart + 0.34*baseSpan, 'Matching connectivity edge columns to ROI pairs.');
            [edgeIndex, nNodes, edgeMessages] = NMDataIOConnectivityTools.edgeIndexFromSpecAndPayload(spec, data, sourceFormat, fileInfo);
            messages = [messages; edgeMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            progressTask = NMProgressTools.phase(progressTask, 'connectivity_resolve_nodes', baseStart + 0.34*baseSpan, baseStart + 0.52*baseSpan, 'Validating ROI identities and node locations.');
            if strcmp(sourceFormat,'table') && NMDataIOConnectivityTools.fieldOr(fileInfo,'allowNoAtlas',false)
                [atlasProv, atlasMessages] = NMDataIOConnectivityTools.tableFallbackAtlasProvenance(nNodes, spec);
            else
                [atlasProv, atlasMessages] = NMDataIOConnectivityTools.resolveAtlasNodeProvenance(spec, nNodes);
            end
            messages = [messages; atlasMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            progressTask = NMProgressTools.phase(progressTask, 'connectivity_vectorize', baseStart + 0.52*baseSpan, baseStart + 0.72*baseSpan, 'Preparing the case-by-edge connectivity matrix.');
            [Y, vectorMessages] = NMDataIOConnectivityTools.vectorizePayload(data, sourceFormat, edgeIndex, spec);
            messages = [messages; vectorMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            progressTask = NMProgressTools.phase(progressTask, 'connectivity_localization_filter', baseStart + 0.72*baseSpan, baseStart + 0.82*baseSpan, 'Applying validated ROI localization to the edge space.');
            [Y, edgeIndex, atlasProv, localizationMessages] = NMDataIOConnectivityTools.applyLocalizedNodeFilter(Y, edgeIndex, atlasProv);
            messages = [messages; localizationMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            if size(Y,1) < 1 || size(Y,2) < 1
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.vectorize', 'Connectivity vectorization produced an empty subjects-by-edges matrix.', 1, 'red*')];
                return;
            end
            if numel(caseIDs) ~= size(Y,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.caseIDs', sprintf('The number of connectivity Case IDs (%g) differs from the number of cases in the connectivity data (%g).', numel(caseIDs), size(Y,1)), 1, 'red*')];
                return;
            end
            allNanRows = all(isnan(Y),2);
            allNanCols = all(isnan(Y),1);
            if all(allNanRows)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.missingness', 'All connectivity subjects are all-NaN after vectorization.', 1, 'red*')];
                return;
            end
            if all(allNanCols)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.missingness', 'All connectivity edge features are all-NaN after vectorization.', 1, 'red*')];
                return;
            end
            if any(allNanRows)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.missingness', sprintf('%g connectivity subject(s) are all-NaN after vectorization.', nnz(allNanRows)), 2, 'SystemCommands')];
            end
            if any(allNanCols)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.missingness', sprintf('%g connectivity edge feature(s) are all-NaN after vectorization.', nnz(allNanCols)), 2, 'SystemCommands')];
            end

            progressTask = NMProgressTools.phase(progressTask, 'connectivity_feature_names', baseStart + 0.82*baseSpan, baseStart + 0.94*baseSpan, 'Finalising connectivity feature names and source checks.');
            edgeNames = NMDataIOConnectivityTools.edgeNames(edgeIndex, atlasProv.nodeLabels, atlasProv.nodeIDs, spec);
            [edgeNames, nameMessages] = NMDataIOConnectivityTools.validateUniqueEdgeNames(edgeNames);
            messages = [messages; nameMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            progressTask = NMProgressTools.phase(progressTask, 'connectivity_resolve_finalize', baseStart + 0.94*baseSpan, baseStart + 0.99*baseSpan, 'Finalising the resolved connectivity source.');
            connOut.Y = double(Y);
            connOut.caseIDs = caseIDs(:);
            connOut.featnames = edgeNames(:)';
            connOut.provenance = NMDataIOConnectivityTools.buildProvenance(spec, sourceFormat, data, caseIDs, edgeIndex, edgeNames, atlasProv, fileInfo);
            if strcmpi(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(spec,'modeflag','classification')),'classification') && ...
                    strcmp(NMDataIOConnectivityTools.normalizedLabelMode(NMDataIOConnectivityTools.fieldOr(spec,'labelMode','metadata')),'legacy_groups')
                [legacyLabels, legacyNames, legacyMessages] = NMDataIOConnectivityTools.legacyGroupLabels(spec, numel(caseIDs));
                messages = [messages; legacyMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                connOut.label = legacyLabels;
                connOut.desc_groups = legacyNames(:)';
            end
            connOut.diagnostics = messages;
            connOut.ok = ~NMDataIOMessageTools.hasFatal(messages);
        end

        function [connOut, messages] = resolveWeightingMaps(connOut, spec)
            % resolveWeightingMaps  Resolve optional training-time connectivity weighting maps.
            %
            % The output Yw is nMaps-by-nEdges and is guaranteed to use the
            % same edge order as connOut.Y / connOut.featnames.  This method is
            % intended for training imports only; OOCV data inherit the trained
            % feature/weighting definition and should not provide independent
            % weighting maps.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 2 || isempty(spec), spec = struct(); end
            spec = NMDataIOConnectivityTools.normalizeSpec(spec);
            if ~isstruct(connOut) || ~isfield(connOut,'Y') || isempty(connOut.Y) || ...
                    ~isfield(connOut,'provenance') || ~isstruct(connOut.provenance)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting', ...
                    'Connectivity weighting maps require connectivity data with a valid node/edge definition.', 1, 'red*')];
                return;
            end
            if ~NMDataIOConnectivityTools.hasWeightingSpec(spec)
                connOut.provenance.hasWeightingMaps = false;
                connOut.diagnostics = [NMDataIOConnectivityTools.fieldOr(connOut,'diagnostics',NMDataIOMessageTools.emptyMessages()); messages];
                connOut.ok = ~NMDataIOMessageTools.hasFatal(connOut.diagnostics);
                return;
            end
            [Yw, names, wprov, wMessages] = NMDataIOConnectivityTools.resolveWeightingPayload(connOut, spec);
            messages = [messages; wMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                connOut.diagnostics = [NMDataIOConnectivityTools.fieldOr(connOut,'diagnostics',NMDataIOMessageTools.emptyMessages()); messages];
                connOut.ok = false;
                return;
            end
            connOut.Yw = Yw;
            connOut.weightingNames = names;
            connOut.provenance.hasWeightingMaps = true;
            connOut.provenance.weighting = wprov;
            connOut.provenance.weightingNames = names;
            if ~isfield(connOut,'importReport') || ~isstruct(connOut.importReport), connOut.importReport = struct(); end
            connOut.importReport.hasWeightingMaps = true;
            connOut.importReport.nWeightingMaps = size(Yw,1);
            connOut.importReport.weightingNames = names;
            connOut.diagnostics = [NMDataIOConnectivityTools.fieldOr(connOut,'diagnostics',NMDataIOMessageTools.emptyMessages()); messages];
            connOut.ok = ~NMDataIOMessageTools.hasFatal(connOut.diagnostics);
        end

        function [connOut, messages] = applySubspaceSelection(connOut, spec)
            % applySubspaceSelection  Reduce a resolved connectivity payload by node/ROI rules.
            %
            % The selector operates on node provenance and produces an edge mask.
            % It reduces Y, featnames, provenance.edgeIndex/edgeNames, and Yw when
            % present.  It does not alter case order or labels/covariates.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 2 || isempty(spec), spec = struct(); end
            if ~isstruct(connOut) || ~isfield(connOut,'Y') || isempty(connOut.Y) || ...
                    ~isfield(connOut,'provenance') || ~isstruct(connOut.provenance)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                    'Connectivity subspace selection requires connectivity data with a valid node/edge definition.', 1, 'red*')];
                return;
            end
            sel = NMDataIOConnectivityTools.normalizedSubspaceSelection(spec);
            if ~sel.enabled
                connOut.provenance.subspaceSelection = struct('enabled',false);
                return;
            end

            prov = connOut.provenance;
            edgeIndex = double(prov.edgeIndex);
            edgeNames = prov.edgeNames;
            nodeIDs = prov.nodeIDs;
            nodeLabels = prov.nodeLabels;
            if isempty(edgeIndex) || size(edgeIndex,2) ~= 2 || isempty(nodeIDs) || isempty(nodeLabels)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                    'Connectivity subspace selection requires node IDs, node names, and an edge definition.', 1, 'red*')];
                return;
            end
            if size(connOut.Y,2) ~= size(edgeIndex,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                    sprintf('Connectivity feature count (%g) does not match edgeIndex row count (%g) before subspace selection.', size(connOut.Y,2), size(edgeIndex,1)), 1, 'red*')];
                return;
            end
            if numel(edgeNames) ~= size(edgeIndex,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                    sprintf('Connectivity edge-name count (%g) does not match edgeIndex row count (%g) before subspace selection.', numel(edgeNames), size(edgeIndex,1)), 1, 'red*')];
                return;
            end
            if any(edgeIndex(:) < 1) || any(edgeIndex(:) > numel(nodeIDs)) || any(abs(edgeIndex(:)-round(edgeIndex(:))) > 1e-10)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                    'Connectivity edgeIndex contains invalid node-position indices before subspace selection.', 1, 'red*')];
                return;
            end

            report = struct('enabled',true,'mode',sel.mode,'metadataEdgeMode',sel.metadataEdgeMode, ...
                'metadataColumn',sel.metadataColumn,'metadataValues',{sel.metadataValues}, ...
                'nOriginalEdges',size(edgeIndex,1),'nSelectedEdges',0, ...
                'selectedNodeIDs',[],'selectedNodeLabels',{{}}, ...
                'selectedNodeIDsA',[],'selectedNodeLabelsA',{{}}, ...
                'selectedNodeIDsB',[],'selectedNodeLabelsB',{{}}, ...
                'edgeMask',[]);

            switch sel.mode
                case {'seed','seed_nodes','involving'}
                    [nodesA, nodeMessages] = NMDataIOConnectivityTools.resolveConnectivityNodeSet(sel.seedNodes, prov, 'seed node');
                    messages = [messages; nodeMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                    edgeMask = ismember(edgeIndex(:,1), nodesA) | ismember(edgeIndex(:,2), nodesA);
                    report.selectedNodeIDs = nodeIDs(nodesA);
                    report.selectedNodeLabels = nodeLabels(nodesA);
                case {'between','a_x_b','node_set_ab','nodesetab'}
                    [nodesA, nodeMessagesA] = NMDataIOConnectivityTools.resolveConnectivityNodeSet(sel.nodeSetA, prov, 'node-set A');
                    [nodesB, nodeMessagesB] = NMDataIOConnectivityTools.resolveConnectivityNodeSet(sel.nodeSetB, prov, 'node-set B');
                    messages = [messages; nodeMessagesA; nodeMessagesB];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                    edgeMask = (ismember(edgeIndex(:,1), nodesA) & ismember(edgeIndex(:,2), nodesB)) | ...
                               (ismember(edgeIndex(:,1), nodesB) & ismember(edgeIndex(:,2), nodesA));
                    report.selectedNodeIDsA = nodeIDs(nodesA);
                    report.selectedNodeLabelsA = nodeLabels(nodesA);
                    report.selectedNodeIDsB = nodeIDs(nodesB);
                    report.selectedNodeLabelsB = nodeLabels(nodesB);
                case {'within','within_set','within_node_set'}
                    [nodesA, nodeMessages] = NMDataIOConnectivityTools.resolveConnectivityNodeSet(sel.nodeSetA, prov, 'within-set node');
                    messages = [messages; nodeMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                    edgeMask = ismember(edgeIndex(:,1), nodesA) & ismember(edgeIndex(:,2), nodesA);
                    report.selectedNodeIDs = nodeIDs(nodesA);
                    report.selectedNodeLabels = nodeLabels(nodesA);
                case {'metadata','metadata_nodes'}
                    [nodesA, metaMessages, metaReport] = NMDataIOConnectivityTools.resolveMetadataNodeSet(sel, prov);
                    messages = [messages; metaMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                    if strcmp(sel.metadataEdgeMode,'within')
                        edgeMask = ismember(edgeIndex(:,1), nodesA) & ismember(edgeIndex(:,2), nodesA);
                    else
                        edgeMask = ismember(edgeIndex(:,1), nodesA) | ismember(edgeIndex(:,2), nodesA);
                    end
                    report.selectedNodeIDs = nodeIDs(nodesA);
                    report.selectedNodeLabels = nodeLabels(nodesA);
                    report.metadata = metaReport;
                otherwise
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                        sprintf('Unsupported connectivity subspace mode: %s.', sel.mode), 1, 'red*')];
                    return;
            end

            edgeMask = logical(edgeMask(:)');
            if numel(edgeMask) ~= size(edgeIndex,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                    'Connectivity subspace selector produced an invalid edge-mask length.', 1, 'red*')];
                return;
            end
            if ~any(edgeMask)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                    sprintf('Connectivity subspace selector mode ''%s'' selected zero edges. Adjust the node/metadata selection.', sel.mode), 1, 'red*')];
                return;
            end
            if isfield(connOut,'Yw') && ~isempty(connOut.Yw) && size(connOut.Yw,2) ~= numel(edgeMask)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace', ...
                    sprintf('Connectivity weighting maps have %g edge column(s), but the full edge space has %g before subspace reduction.', size(connOut.Yw,2), numel(edgeMask)), 1, 'red*')];
                return;
            end

            report.nSelectedEdges = nnz(edgeMask);
            report.edgeMask = edgeMask;
            prov.subspaceOriginalEdgeIndex = edgeIndex;
            prov.subspaceOriginalEdgeNames = edgeNames(:)';
            prov.edgeIndex = edgeIndex(edgeMask,:);
            prov.edgeNames = edgeNames(edgeMask);
            prov.edgeNames = prov.edgeNames(:)';
            prov.nEdges = nnz(edgeMask);
            connOut.Y = connOut.Y(:, edgeMask);
            connOut.featnames = prov.edgeNames;

            if isfield(connOut,'Yw') && ~isempty(connOut.Yw)
                connOut.Yw = connOut.Yw(:, edgeMask);
                report.weightingMapsReduced = true;
            else
                report.weightingMapsReduced = false;
            end
            prov.subspaceSelection = report;

            connOut.provenance = prov;
            if ~isfield(connOut,'importReport') || ~isstruct(connOut.importReport), connOut.importReport = struct(); end
            connOut.importReport.connectivitySubspace = report;
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.subspace', ...
                sprintf('Connectivity subspace selection kept %g/%g edge feature(s) using mode ''%s''.', report.nSelectedEdges, report.nOriginalEdges, sel.mode), 0, 'green*')];
            connOut.diagnostics = [NMDataIOConnectivityTools.fieldOr(connOut,'diagnostics',NMDataIOMessageTools.emptyMessages()); messages];
            connOut.ok = ~NMDataIOMessageTools.hasFatal(connOut.diagnostics);
        end

        function [connOut, messages, report] = alignToTrainingConnectivity(connOut, trainProv, spec)
            % alignToTrainingConnectivity  Reorder OOCV connectivity edges to the trained edge space.
            %
            % The training connectivity provenance is authoritative. Matching is
            % performed by atlas/node IDs and edgeIndex, not by display feature
            % names. For undirected matrices, A--B and B--A are treated as the
            % same edge. Missing training edges are blocking; extra OOCV edges
            % are ignored after a warning.
            messages = NMDataIOMessageTools.emptyMessages();
            report = struct('ok',false,'nTrainingEdges',0,'nOOCVEdges',0, ...
                'nMatchedEdges',0,'nExtraEdges',0,'missingTrainingEdgeKeys',{{}}, ...
                'extraOOCVEdgeKeys',{{}},'edgeReorderIndex',[], ...
                'edgeOrderChanged',false,'nodeOrderChanged',false, ...
                'matrixType','','includeDiagonal',[],'matchBy','nodeIDs_edgeIndex');
            if nargin < 3 || isempty(spec), spec = struct(); end
            if ~isstruct(connOut) || ~isfield(connOut,'Y') || isempty(connOut.Y) || ...
                    ~isfield(connOut,'provenance') || ~isstruct(connOut.provenance)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'OOCV connectivity matching requires connectivity data with a valid node/edge definition.', 1, 'red*')];
                return;
            end
            if ~isstruct(trainProv)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'The training connectivity node/edge definition is missing or invalid.', 1, 'red*')];
                return;
            end

            trainNodeIDs = NMDataIOConnectivityTools.numericVector(NMDataIOConnectivityTools.fieldOr(trainProv,'nodeIDs',[]));
            oocvNodeIDs = NMDataIOConnectivityTools.numericVector(NMDataIOConnectivityTools.fieldOr(connOut.provenance,'nodeIDs',[]));
            trainEdgeIndex = double(NMDataIOConnectivityTools.fieldOr(trainProv,'edgeIndex',[]));
            oocvEdgeIndex = double(NMDataIOConnectivityTools.fieldOr(connOut.provenance,'edgeIndex',[]));
            if isempty(trainNodeIDs) || isempty(oocvNodeIDs) || isempty(trainEdgeIndex) || isempty(oocvEdgeIndex)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'Training and OOCV connectivity data must both contain node IDs and edge definitions.', 1, 'red*')];
                return;
            end
            if size(trainEdgeIndex,2) ~= 2 || size(oocvEdgeIndex,2) ~= 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'Training and OOCV connectivity edgeIndex fields must be nEdges-by-2 matrices.', 1, 'red*')];
                return;
            end
            if numel(unique(trainNodeIDs)) ~= numel(trainNodeIDs) || numel(unique(oocvNodeIDs)) ~= numel(oocvNodeIDs)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'Training and OOCV connectivity node IDs must be unique before edge-space mapping.', 1, 'red*')];
                return;
            end
            if numel(trainNodeIDs) ~= numel(oocvNodeIDs)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    sprintf('OOCV connectivity has %g node ID(s), but the trained connectivity modality has %g.', numel(oocvNodeIDs), numel(trainNodeIDs)), 1, 'red*')];
                return;
            end
            [nodeMatched, nodeLoc] = ismember(trainNodeIDs(:), oocvNodeIDs(:));
            if ~all(nodeMatched)
                missingIDs = trainNodeIDs(~nodeMatched);
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    sprintf('The OOCV ROI description file is missing %g node ID(s) used during training: %s.', nnz(~nodeMatched), NMDataIOConnectivityTools.shortNumericList(missingIDs, 12)), 1, 'red*')];
                return;
            end
            report.nodeOrderChanged = any(nodeLoc(:) ~= (1:numel(trainNodeIDs))');

            trainMatrixType = lower(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(trainProv,'matrixType','undirected')));
            oocvMatrixType = lower(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(connOut.provenance,'matrixType',trainMatrixType)));
            trainDiag = logical(NMDataIOConnectivityTools.fieldOr(trainProv,'includeDiagonal',false));
            oocvDiag = logical(NMDataIOConnectivityTools.fieldOr(connOut.provenance,'includeDiagonal',false));
            report.matrixType = trainMatrixType;
            report.includeDiagonal = trainDiag;
            if ~strcmp(trainMatrixType, oocvMatrixType)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    sprintf('OOCV connectivity matrixType (%s) differs from trained connectivity matrixType (%s).', oocvMatrixType, trainMatrixType), 1, 'red*')];
                return;
            end
            if trainDiag ~= oocvDiag
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    sprintf('OOCV includeDiagonal=%g differs from trained includeDiagonal=%g.', double(oocvDiag), double(trainDiag)), 1, 'red*')];
                return;
            end
            if size(trainEdgeIndex,1) < 1 || size(oocvEdgeIndex,1) < 1 || size(connOut.Y,2) ~= size(oocvEdgeIndex,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    sprintf('OOCV connectivity feature count (%g) does not match OOCV edgeIndex row count (%g).', size(connOut.Y,2), size(oocvEdgeIndex,1)), 1, 'red*')];
                return;
            end
            if any(trainEdgeIndex(:) < 1) || any(trainEdgeIndex(:) > numel(trainNodeIDs)) || ...
                    any(oocvEdgeIndex(:) < 1) || any(oocvEdgeIndex(:) > numel(oocvNodeIDs))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'Training or OOCV edgeIndex contains node-position indices outside the corresponding node-ID vector.', 1, 'red*')];
                return;
            end

            trainKeys = NMDataIOConnectivityTools.edgeKeysFromIDs(trainNodeIDs, trainEdgeIndex, trainMatrixType);
            oocvKeys = NMDataIOConnectivityTools.edgeKeysFromIDs(oocvNodeIDs, oocvEdgeIndex, oocvMatrixType);
            if numel(unique(trainKeys)) ~= numel(trainKeys)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'Training connectivity edge keys are not unique; cannot perform safe OOCV edge-space mapping.', 1, 'red*')];
                return;
            end
            if numel(unique(oocvKeys)) ~= numel(oocvKeys)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'OOCV connectivity edge keys are not unique; cannot perform safe OOCV edge-space mapping.', 1, 'red*')];
                return;
            end
            [matched, loc] = ismember(trainKeys(:), oocvKeys(:));
            report.nTrainingEdges = numel(trainKeys);
            report.nOOCVEdges = numel(oocvKeys);
            report.nMatchedEdges = nnz(matched);
            if ~all(matched)
                report.missingTrainingEdgeKeys = trainKeys(~matched)';
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    sprintf('OOCV connectivity is missing %g required training edge(s). Examples: %s.', nnz(~matched), NMDataIOConnectivityTools.shortCellList(report.missingTrainingEdgeKeys, 8)), 1, 'red*')];
                return;
            end
            extraMask = ~ismember(oocvKeys(:), trainKeys(:));
            report.nExtraEdges = nnz(extraMask);
            report.extraOOCVEdgeKeys = oocvKeys(extraMask)';
            if report.nExtraEdges > 0
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.oocv.edgeSpace', ...
                    sprintf('OOCV connectivity contains %g extra edge(s) not used by the trained model. Extra edges were ignored. Examples: %s.', report.nExtraEdges, NMDataIOConnectivityTools.shortCellList(report.extraOOCVEdgeKeys, 8)), 2, 'SystemCommands')];
            end
            report.edgeReorderIndex = loc(:)';
            report.edgeOrderChanged = any(loc(:) ~= (1:numel(loc))');

            connOut.provenance.oocvOriginalEdgeIndex = connOut.provenance.edgeIndex;
            connOut.provenance.oocvOriginalEdgeNames = NMDataIOConnectivityTools.fieldOr(connOut.provenance,'edgeNames',{});
            connOut.provenance.oocvOriginalNodeIDs = connOut.provenance.nodeIDs;
            connOut.provenance.oocvOriginalNodeLabels = NMDataIOConnectivityTools.fieldOr(connOut.provenance,'nodeLabels',{});
            connOut.Y = connOut.Y(:, loc);
            if isfield(trainProv,'edgeNames') && ~isempty(trainProv.edgeNames)
                connOut.featnames = NMDataIOConnectivityTools.asCellstr(trainProv.edgeNames);
            else
                connOut.featnames = connOut.featnames(loc);
            end
            connOut.featnames = connOut.featnames(:)';
            connOut.provenance.edgeIndex = trainEdgeIndex;
            connOut.provenance.edgeNames = connOut.featnames;
            connOut.provenance.nodeIDs = trainNodeIDs(:)';
            if isfield(trainProv,'nodeLabels') && ~isempty(trainProv.nodeLabels)
                connOut.provenance.nodeLabels = NMDataIOConnectivityTools.asCellstr(trainProv.nodeLabels);
                connOut.provenance.nodeLabels = connOut.provenance.nodeLabels(:)';
            end
            connOut.provenance.nNodes = numel(trainNodeIDs);
            connOut.provenance.nEdges = size(trainEdgeIndex,1);
            connOut.provenance.trainingModality = NMDataIOConnectivityTools.fieldOr(spec,'varind',[]);
            connOut.provenance.trainingEdgeSpaceMatched = true;
            connOut.provenance.trainingEdgeSpace = struct('nNodes',NMDataIOConnectivityTools.fieldOr(trainProv,'nNodes',[]), ...
                'nEdges',NMDataIOConnectivityTools.fieldOr(trainProv,'nEdges',[]), ...
                'nodeIDs',{NMDataIOConnectivityTools.fieldOr(trainProv,'nodeIDs',[])}, ...
                'edgeIndex',NMDataIOConnectivityTools.fieldOr(trainProv,'edgeIndex',[]));
            connOut.provenance.edgeReorderIndexToTraining = report.edgeReorderIndex;
            connOut.provenance.extraOOCVEdgeKeysIgnored = report.extraOOCVEdgeKeys;
            connOut.provenance.nodeOrderChangedRelativeToTraining = report.nodeOrderChanged;
            connOut.provenance.edgeOrderChangedRelativeToTraining = report.edgeOrderChanged;

            if all(isnan(connOut.Y(:)))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.oocv.edgeSpace', ...
                    'OOCV connectivity matrix is 100% NaN after training edge-space mapping.', 1, 'red*')];
                return;
            end
            allNanRows = all(isnan(connOut.Y),2);
            allNanCols = all(isnan(connOut.Y),1);
            if any(allNanRows)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.oocv.edgeSpace', ...
                    sprintf('%g OOCV connectivity case(s) are all-NaN after training edge-space mapping.', nnz(allNanRows)), 2, 'SystemCommands')];
            end
            if any(allNanCols)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.oocv.edgeSpace', ...
                    sprintf('%g trained connectivity edge feature(s) are all-NaN in the OOCV data.', nnz(allNanCols)), 2, 'SystemCommands')];
            end
            report.ok = true;
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.oocv.edgeSpace', ...
                sprintf('OOCV connectivity edge space matched %g/%g trained edge(s)%s.', report.nMatchedEdges, report.nTrainingEdges, NMDataIOConnectivityTools.edgeSpaceChangeText(report)), 0, 'green*')];
            connOut.provenance.oocvCompatibility = report;
            connOut.importReport.oocvCompatibility = report;
            connOut.diagnostics = [NMDataIOConnectivityTools.fieldOr(connOut,'diagnostics',NMDataIOMessageTools.emptyMessages()); messages];
            connOut.ok = ~NMDataIOMessageTools.hasFatal(connOut.diagnostics);
        end

    end

    methods (Static)
        function out = inspectMatMatrixVariables(filePath)
            % inspectMatMatrixVariables  List numeric square matrix variables in a MAT file.
            % This is intentionally connectivity-scoped: these are the only
            % MAT variables that can be used as file-per-subject connectivity
            % matrices or square connectivity weighting maps.
            out = struct();
            out.ok = false;
            out.filePath = NMDataIOConnectivityTools.asChar(filePath);
            out.variables = {};
            out.variableDetails = struct('name',{},'size',{},'class',{});
            out.nVariables = 0;
            out.message = '';
            out.messages = NMDataIOMessageTools.emptyMessages();
            if isempty(out.filePath) || exist(out.filePath,'file') ~= 2
                out.messages = [out.messages; NMDataIOMessageTools.make('danger', true, 'connectivity.matVariables', sprintf('MAT file does not exist: %s.', out.filePath), 1, 'red*')];
                out.message = out.messages(1).text;
                return;
            end
            [~,~,ext] = fileparts(out.filePath);
            if ~strcmpi(ext, '.mat')
                out.messages = [out.messages; NMDataIOMessageTools.make('danger', true, 'connectivity.matVariables', sprintf('Connectivity MAT-variable inspection requires a .mat file, got ''%s''.', ext), 1, 'red*')];
                out.message = out.messages(1).text;
                return;
            end
            try
                W = whos('-file', out.filePath);
            catch ME
                out.messages = NMDataIOMessageTools.fromException(ME, 'connectivity.matVariables');
                out.message = out.messages(1).text;
                return;
            end
            vars = {};
            details = struct('name',{},'size',{},'class',{});
            for k = 1:numel(W)
                if numel(W(k).size) == 2 && W(k).size(1) == W(k).size(2) && ...
                        any(strcmp(W(k).class, {'double','single','logical','uint8','uint16','uint32','uint64','int8','int16','int32','int64'}))
                    vars{end+1,1} = W(k).name; %#ok<AGROW>
                    details(end+1).name = W(k).name; %#ok<AGROW>
                    details(end).size = W(k).size;
                    details(end).class = W(k).class;
                end
            end
            out.variables = vars;
            out.variableDetails = details;
            out.nVariables = numel(vars);
            if out.nVariables == 0
                out.messages = [out.messages; NMDataIOMessageTools.make('danger', true, 'connectivity.matVariables', sprintf('MAT file %s contains no numeric square matrix variables.', out.filePath), 1, 'red*')];
                out.message = out.messages(1).text;
                return;
            end
            out.ok = true;
            out.messages = [out.messages; NMDataIOMessageTools.make('ok', false, 'connectivity.matVariables', sprintf('Found %g numeric square MAT variable(s): %s.', out.nVariables, strjoin(vars(:)', ', ')), 0, 'green*')];
            out.message = out.messages(1).text;
        end


        function M = edgeVectorToMatrix(edgeVec, edgeIndex, nNodes, opts)
            % edgeVectorToMatrix  Reconstruct a square connectivity matrix from a vectorized edge row.
            %
            % Consumes edgeVec, edgeIndex, nNodes, opts; returns M.
            % It preserves the connectivity edge-space contract so training, OOCV, QC, and results viewers use the same feature order.
            % Throws on invalid preconditions instead of returning an ambiguous partial result.
            %
            % opts.matrixType: configures optional matrix type behavior for this call.
            if nargin < 4 || isempty(opts), opts = struct(); end
            edgeIndex = double(edgeIndex);
            if isempty(edgeIndex)
                M = nan(max(0, round(double(nNodes))));
                return;
            end
            if size(edgeIndex,2) ~= 2 && size(edgeIndex,1) == 2
                edgeIndex = edgeIndex';
            end
            if size(edgeIndex,2) ~= 2
                error('NMDataIOConnectivityTools:badEdgeIndex', 'Connectivity edgeIndex must be nEdges-by-2 or 2-by-nEdges.');
            end
            if nargin < 3 || isempty(nNodes) || ~isfinite(double(nNodes)) || double(nNodes) < 1
                nNodes = max(edgeIndex(:));
            end
            nNodes = max(0, round(double(nNodes)));
            M = nan(nNodes, nNodes);
            v = double(edgeVec(:));
            n = min(numel(v), size(edgeIndex,1));
            directed = strcmpi(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(opts, 'matrixType', 'undirected')), 'directed');
            for i = 1:n
                a = round(edgeIndex(i,1));
                b = round(edgeIndex(i,2));
                if a < 1 || b < 1 || a > nNodes || b > nNodes, continue; end
                M(a,b) = v(i);
                if ~directed && a ~= b
                    M(b,a) = v(i);
                end
            end
        end

        function stats = edgeMatrixStats(Y, edgeIndex, nNodes, opts)
            % edgeMatrixStats  Compute edge-space descriptive statistics for connectivity QC and viewer summaries.
            %
            % Consumes Y, edgeIndex, nNodes, opts; returns stats.
            % It preserves the connectivity edge-space contract so training, OOCV, QC, and results viewers use the same feature order.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 4 || isempty(opts), opts = struct(); end
            Y = double(Y);
            if isempty(Y), Y = nan(0, size(edgeIndex,1)); end
            nSubjects = size(Y,1);
            meanVec = nan(1, size(Y,2));
            sdVec = nan(1, size(Y,2));
            validN = zeros(1, size(Y,2));
            missingRate = nan(1, size(Y,2));
            for j = 1:size(Y,2)
                x = Y(:,j);
                finite = isfinite(x);
                validN(j) = nnz(finite);
                missingRate(j) = 1 - validN(j) ./ max(1, nSubjects);
                if any(finite)
                    meanVec(j) = mean(x(finite));
                    if nnz(finite) > 1
                        sdVec(j) = std(x(finite), 0);
                    else
                        sdVec(j) = NaN;
                    end
                end
            end
            stats = struct();
            stats.schemaVersion = 1;
            stats.nSubjects = double(nSubjects);
            stats.nNodes = double(nNodes);
            stats.nEdges = double(size(edgeIndex,1));
            stats.edgeMean = double(meanVec(:)');
            stats.edgeSD = double(sdVec(:)');
            stats.edgeMissingRate = double(missingRate(:)');
            stats.edgeValidN = double(validN(:)');
            stats.meanMatrix = NMDataIOConnectivityTools.edgeVectorToMatrix(meanVec, edgeIndex, nNodes, opts);
            stats.sdMatrix = NMDataIOConnectivityTools.edgeVectorToMatrix(sdVec, edgeIndex, nNodes, opts);
            stats.missingRateMatrix = NMDataIOConnectivityTools.edgeVectorToMatrix(missingRate, edgeIndex, nNodes, opts);
            stats.validNMatrix = NMDataIOConnectivityTools.edgeVectorToMatrix(validN, edgeIndex, nNodes, opts);
            stats.edgeSpaceQC = NMDataIOConnectivityTools.edgeSpaceQC(Y, edgeIndex, nNodes, opts);
        end

        function qc = edgeSpaceQC(Y, edgeIndex, nNodes, opts)
            % edgeSpaceQC  Compute subject and edge QC metrics for vectorized connectivity matrices.
            %
            % Consumes Y, edgeIndex, nNodes, opts; returns qc.
            % It preserves the connectivity edge-space contract so training, OOCV, QC, and results viewers use the same feature order.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            %
            % opts.matrixType: configures optional matrix type behavior for this call.
            if nargin < 4 || isempty(opts), opts = struct(); end
            Y = double(Y); edgeIndex = double(edgeIndex);
            qc = struct('schemaVersion',1,'nSubjects',double(size(Y,1)), 'diagonalAvailable',false, ...
                'diagonalNonzeroCount',[], 'diagonalMaxAbs',[], 'symmetryAvailable',false, ...
                'symmetryMeanAbsDeviation',[], 'symmetryMaxAbsDeviation',[], 'note','');
            if isempty(Y) || isempty(edgeIndex) || size(edgeIndex,2) ~= 2
                qc.note = 'Connectivity edge-space QC requires a subjects-by-edges matrix and nEdges-by-2 edgeIndex.';
                return;
            end
            diagMask = edgeIndex(:,1) == edgeIndex(:,2);
            if any(diagMask)
                D = Y(:,diagMask);
                qc.diagonalAvailable = true;
                qc.diagonalNonzeroCount = sum(isfinite(D) & abs(D) > 0, 2)';
                qc.diagonalMaxAbs = nan(1,size(D,1));
                for i = 1:size(D,1)
                    v = abs(D(i,isfinite(D(i,:))));
                    if ~isempty(v), qc.diagonalMaxAbs(i) = max(v); end
                end
            else
                qc.note = 'Diagonal QC is unavailable because diagonal edges were not imported.';
            end
            directed = strcmpi(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(opts, 'matrixType', 'undirected')), 'directed');
            pairMap = containers.Map('KeyType','char','ValueType','double');
            for e = 1:size(edgeIndex,1)
                pairMap(sprintf('%g:%g', edgeIndex(e,1), edgeIndex(e,2))) = e;
            end
            pairA = []; pairB = [];
            if directed
                for e = 1:size(edgeIndex,1)
                    a = edgeIndex(e,1); b = edgeIndex(e,2);
                    if a == b, continue; end
                    revKey = sprintf('%g:%g', b, a);
                    if isKey(pairMap, revKey)
                        r = pairMap(revKey);
                        if e < r
                            pairA(end+1) = e; %#ok<AGROW>
                            pairB(end+1) = r; %#ok<AGROW>
                        end
                    end
                end
            end
            if ~isempty(pairA)
                delta = abs(Y(:,pairA) - Y(:,pairB));
                qc.symmetryAvailable = true;
                qc.symmetryMeanAbsDeviation = nan(1,size(Y,1));
                qc.symmetryMaxAbsDeviation = nan(1,size(Y,1));
                for i = 1:size(Y,1)
                    v = delta(i,isfinite(delta(i,:)));
                    if ~isempty(v)
                        qc.symmetryMeanAbsDeviation(i) = mean(v);
                        qc.symmetryMaxAbsDeviation(i) = max(v);
                    end
                end
            elseif directed
                qc.note = strtrim([qc.note ' Symmetry QC is unavailable because reciprocal directed edge pairs were not imported.']);
            else
                qc.note = strtrim([qc.note ' Symmetry QC is not applicable to undirected vectorized connectivity because one triangle was imported.']);
            end
        end

        function qc = rawConnectivityMatrixQC(connOut, opts) %#ok<INUSD>
            % rawConnectivityMatrixQC  Report availability of raw square-matrix QC.
            % The current resolved contract keeps subjects-by-edge matrices.  Symmetry
            % and diagonal checks are available during square matrix import and are
            % represented in diagnostics/provenance; vectorized/table inputs cannot
            % be retroactively checked without fabricating source matrices.
            qc = struct('available',false,'reason','Raw square connectivity matrices are not kept after import. Review the import diagnostics for symmetry and diagonal checks performed on the source data.');
            try
                prov = NMDataIOConnectivityTools.fieldOr(connOut, 'provenance', struct());
                sourceFormat = lower(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(prov, 'sourceFormat', '')));
                qc.sourceFormat = sourceFormat;
                qc.matrixType = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(prov, 'matrixType', ''));
                qc.includeDiagonal = NMDataIOConnectivityTools.fieldOr(prov, 'includeDiagonal', false);
                if any(strcmp(sourceFormat, {'file_per_subject','array3d'}))
                    qc.available = false;
                    qc.reason = 'Symmetry and diagonal QC were performed before the connectivity matrices were converted to edge features. The QC viewer uses the imported edge-feature matrix.';
                end
            catch
                % leave conservative unavailable payload
            end
        end



    end

    methods (Static, Access = private)

        function sel = normalizedSubspaceSelection(spec)
            sel = struct('enabled',false,'mode','all','seedNodes',[], 'nodeSetA',[], 'nodeSetB',[], ...
                'metadataColumn','', 'metadataValues',{{}}, 'metadataEdgeMode','involving');
            if nargin < 1 || isempty(spec) || ~isstruct(spec), return; end
            raw = [];
            candidates = {'connectivitySubspace','subspace','edgeSubspace','nodeSelection'};
            for i = 1:numel(candidates)
                if isfield(spec,candidates{i}) && ~isempty(spec.(candidates{i}))
                    raw = spec.(candidates{i});
                    break;
                end
            end
            if isempty(raw), return; end
            if islogical(raw) || isnumeric(raw)
                sel.enabled = logical(raw(1));
                return;
            end
            if ischar(raw) || (isstring(raw) && isscalar(raw))
                rawMode = lower(strtrim(char(string(raw))));
                sel.enabled = ~(isempty(rawMode) || any(strcmp(rawMode, {'all','none','off','false','0'})));
                if sel.enabled, sel.mode = rawMode; end
                return;
            end
            if ~isstruct(raw), return; end
            enabled = NMDataIOConnectivityTools.pick(raw, {'enabled','enable','use','active'}, []);
            mode = lower(strrep(strrep(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(raw, {'mode','selectionMode','edgeMode'}, 'all')), '-', '_'), ' ', '_'));
            if isempty(mode), mode = 'all'; end
            if isempty(enabled)
                enabled = ~any(strcmp(mode, {'all','none','off','false','0'}));
            end
            sel.enabled = NMDataIOConnectivityTools.toLogical(enabled);
            if ~sel.enabled, return; end
            sel.mode = mode;
            sel.seedNodes = NMDataIOConnectivityTools.pick(raw, {'seedNodes','seeds','nodes','nodeSelection','selectedNodes'}, []);
            sel.nodeSetA = NMDataIOConnectivityTools.pick(raw, {'nodeSetA','nodesA','setA','sourceNodes','fromNodes','withinNodes'}, []);
            sel.nodeSetB = NMDataIOConnectivityTools.pick(raw, {'nodeSetB','nodesB','setB','targetNodes','toNodes'}, []);
            if isempty(sel.nodeSetA) && any(strcmp(sel.mode, {'within','within_set','within_node_set'}))
                sel.nodeSetA = NMDataIOConnectivityTools.pick(raw, {'nodes','selectedNodes','nodeSelection'}, []);
            end
            sel.metadataColumn = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(raw, {'metadataColumn','nodeMetadataColumn','column','field'}, ''));
            metaValues = NMDataIOConnectivityTools.pick(raw, {'metadataValues','values','value','metadataValue','nodeMetadataValues'}, {});
            sel.metadataValues = NMDataIOConnectivityTools.tokenCell(metaValues);
            metaRule = lower(strrep(strrep(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(raw, {'metadataEdgeMode','metadataRule','edgeRule'}, 'involving')), '-', '_'), ' ', '_'));
            if any(strcmp(metaRule, {'within','within_set'})), sel.metadataEdgeMode = 'within'; else, sel.metadataEdgeMode = 'involving'; end
        end

        function [nodePos, messages] = resolveConnectivityNodeSet(raw, prov, label)
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 3 || isempty(label), label = 'node'; end
            nodePos = [];
            nodeIDs = prov.nodeIDs;
            nodeLabels = prov.nodeLabels;
            nNodes = numel(nodeIDs);
            if isempty(raw)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.nodes', ...
                    sprintf('Connectivity subspace selection requires at least one %s.', label), 1, 'red*')];
                return;
            end
            if iscell(raw) && numel(raw) == 1, raw = raw{1}; end
            if isstring(raw) && isscalar(raw), raw = char(raw); end
            if ischar(raw)
                expr = strtrim(raw);
                if isempty(expr) || strcmp(expr,'?')
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.nodes', ...
                        sprintf('Connectivity subspace selection requires at least one %s.', label), 1, 'red*')];
                    return;
                end
                if isvarname(expr) && evalin('base', sprintf('exist(''%s'',''var'')', expr))
                    raw = evalin('base', expr);
                else
                    [idx, idxMessages] = NMDataIOConnectivityTools.resolveNumericIndexVector(expr);
                    if isempty(idxMessages) && ~isempty(idx)
                        raw = idx;
                    else
                        toks = NMDataIOConnectivityTools.tokenCell(expr);
                        if isempty(toks), messages = [messages; idxMessages]; return; end
                        raw = toks;
                    end
                end
            end
            if islogical(raw)
                vec = raw(:)';
                if numel(vec) ~= nNodes
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.nodes', ...
                        sprintf('Logical %s selector has %g element(s), but the connectivity atlas has %g node(s).', label, numel(vec), nNodes), 1, 'red*')];
                    return;
                end
                nodePos = find(vec);
            elseif isnumeric(raw)
                vals = double(raw(:)');
                vals = vals(isfinite(vals));
                vals = round(vals(abs(vals-round(vals)) < 1e-10));
                missing = [];
                pos = [];
                for i = 1:numel(vals)
                    idLoc = find(nodeIDs == vals(i), 1, 'first');
                    if ~isempty(idLoc)
                        pos(end+1) = idLoc; %#ok<AGROW>
                    elseif vals(i) >= 1 && vals(i) <= nNodes
                        pos(end+1) = vals(i); %#ok<AGROW>
                    else
                        missing(end+1) = vals(i); %#ok<AGROW>
                    end
                end
                nodePos = unique(pos, 'stable');
                if ~isempty(missing)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.nodes', ...
                        sprintf('Unknown numeric %s ID/position(s): %s.', label, NMDataIOConnectivityTools.shortNumericList(missing, 12)), 1, 'red*')];
                    return;
                end
            else
                toks = NMDataIOConnectivityTools.tokenCell(raw);
                normLabels = NMDataIOConnectivityTools.normalizedNameList(nodeLabels);
                missing = {};
                pos = [];
                for i = 1:numel(toks)
                    tk = strtrim(NMDataIOConnectivityTools.asChar(toks{i}));
                    if isempty(tk), continue; end
                    numVal = str2double(tk);
                    if isfinite(numVal) && abs(numVal-round(numVal)) < 1e-10
                        [p, pMessages] = NMDataIOConnectivityTools.resolveConnectivityNodeSet(numVal, prov, label);
                        if NMDataIOMessageTools.hasFatal(pMessages)
                            missing{end+1} = tk; %#ok<AGROW>
                        else
                            pos = [pos p]; %#ok<AGROW>
                        end
                    else
                        loc = find(strcmp(nodeLabels, tk), 1, 'first');
                        if isempty(loc), loc = find(strcmp(normLabels, NMDataIOConnectivityTools.normalizeNameToken(tk)), 1, 'first'); end
                        if isempty(loc)
                            missing{end+1} = tk; %#ok<AGROW>
                        else
                            pos(end+1) = loc; %#ok<AGROW>
                        end
                    end
                end
                nodePos = unique(pos, 'stable');
                if ~isempty(missing)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.nodes', ...
                        sprintf('Unknown %s name(s): %s.', label, strjoin(missing, ', ')), 1, 'red*')];
                    return;
                end
            end
            if isempty(nodePos)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.nodes', ...
                    sprintf('Connectivity subspace %s selector resolved to zero node(s).', label), 1, 'red*')];
            end
        end

        function [nodePos, messages, report] = resolveMetadataNodeSet(sel, prov)
            messages = NMDataIOMessageTools.emptyMessages();
            report = struct('column','','values',{sel.metadataValues},'nMatchedNodes',0);
            nodePos = [];
            nodeTable = prov.nodeTable;
            if isempty(nodeTable) || ~istable(nodeTable) || height(nodeTable) < 1
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.metadata', ...
                    'Metadata-based connectivity subspace selection requires ROI metadata from the ROI description file.', 1, 'red*')];
                return;
            end
            column = strtrim(sel.metadataColumn);
            if isempty(column)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.metadata', ...
                    'Metadata-based connectivity subspace selection requires a metadata column from the ROI description file.', 1, 'red*')];
                return;
            end
            varNames = nodeTable.Properties.VariableNames;
            colIdx = find(strcmp(varNames, column), 1, 'first');
            if isempty(colIdx)
                normVars = NMDataIOConnectivityTools.normalizedNameList(varNames);
                colIdx = find(strcmp(normVars, NMDataIOConnectivityTools.normalizeNameToken(column)), 1, 'first');
            end
            if isempty(colIdx)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.metadata', ...
                    sprintf('Node metadata column ''%s'' was not found in the ROI description file. Available columns: %s.', column, strjoin(varNames, ', ')), 1, 'red*')];
                return;
            end
            values = NMDataIOConnectivityTools.tokenCell(sel.metadataValues);
            if isempty(values)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.metadata', ...
                    'Metadata-based connectivity subspace selection requires at least one metadata value.', 1, 'red*')];
                return;
            end
            col = nodeTable.(varNames{colIdx});
            colText = NMDataIOConnectivityTools.tableColumnText(col);
            normCol = NMDataIOConnectivityTools.normalizedNameList(colText);
            normValues = NMDataIOConnectivityTools.normalizedNameList(values);
            mask = ismember(normCol, normValues);
            nodePos = find(mask(:)');
            report.column = varNames{colIdx};
            report.values = values;
            report.nMatchedNodes = numel(nodePos);
            if isempty(nodePos)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.subspace.metadata', ...
                    sprintf('Node metadata selection %s in {%s} matched zero node(s).', varNames{colIdx}, strjoin(values, ', ')), 1, 'red*')];
            end
        end

        function out = tokenCell(raw)
            out = {};
            if isempty(raw), return; end
            if iscell(raw)
                for i = 1:numel(raw)
                    out = [out NMDataIOConnectivityTools.tokenCell(raw{i})]; %#ok<AGROW>
                end
                out = out(~cellfun(@isempty,out));
                return;
            end
            if isstring(raw)
                raw = cellstr(raw(:));
                out = NMDataIOConnectivityTools.tokenCell(raw);
                return;
            end
            if isnumeric(raw) || islogical(raw)
                vals = raw(:)';
                out = arrayfun(@(x)sprintf('%.15g', double(x)), vals, 'UniformOutput', false);
                return;
            end
            if ischar(raw)
                parts = regexp(char(raw), '[,;\n\r\|]+', 'split');
                parts = cellfun(@strtrim, parts, 'UniformOutput', false);
                out = parts(~cellfun(@isempty, parts));
            end
        end

        function out = tableColumnText(col)
            if iscellstr(col)
                out = col(:)';
            elseif iscell(col)
                out = cell(size(col(:)'));
                for i = 1:numel(col), out{i} = NMDataIOConnectivityTools.asChar(col{i}); end
            elseif isstring(col) || iscategorical(col)
                out = cellstr(string(col(:)))';
            elseif isnumeric(col) || islogical(col)
                out = arrayfun(@(x)sprintf('%.15g', double(x)), col(:)', 'UniformOutput', false);
            else
                out = cellstr(string(col(:)))';
            end
        end

        function out = emptyOutput()
            out = struct('ok',false,'Y',[],'caseIDs',{{}},'featnames',{{}},'provenance',struct(), ...
                'diagnostics',NMDataIOMessageTools.emptyMessages(),'importReport',struct());
        end

        function spec = normalizeSpec(spec)
            spec.sourceFormat = lower(strrep(strrep(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'sourceFormat','connectivitySourceFormat','inputFormat'}, 'auto')), '-', '_'), ' ', '_'));
            if isempty(spec.sourceFormat), spec.sourceFormat = 'auto'; end
            spec.matrixType = lower(strrep(strrep(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'matrixType','connectivityType'}, 'undirected')), '-', '_'), ' ', '_'));
            if isempty(spec.matrixType), spec.matrixType = 'undirected'; end
            if ismember(spec.matrixType, {'symmetric','undirected_symmetric'}), spec.matrixType = 'undirected'; end
            if ismember(spec.matrixType, {'asymmetric','directed_asymmetric'}), spec.matrixType = 'directed'; end
            spec.triangle = lower(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'triangle','vectorizationTriangle'}, 'upper')));
            if isempty(spec.triangle), spec.triangle = 'upper'; end
            spec.includeDiagonal = NMDataIOConnectivityTools.toLogical(NMDataIOConnectivityTools.pick(spec, {'includeDiagonal','keepDiagonal'}, false));
            spec.subjectDim = double(NMDataIOConnectivityTools.pick(spec, {'subjectDim','subjectDimension'}, 1));
            if ~isfinite(spec.subjectDim) || isempty(spec.subjectDim), spec.subjectDim = 1; end
            spec.subjectDim = round(spec.subjectDim(1));
            spec.symmetryTolerance = double(NMDataIOConnectivityTools.pick(spec, {'symmetryTolerance','symmetricTolerance'}, 1e-8));
            if ~isfinite(spec.symmetryTolerance) || spec.symmetryTolerance < 0, spec.symmetryTolerance = 1e-8; end
            spec.atlasFile = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'atlasFile','atlas','nodeAtlasFile'}, ''));
            spec.atlasLabelFile = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'atlasLabelFile','atlasDescriptorFile','atlasSidecarFile','roiLabelFile','nodeSidecarFile'}, ''));
            spec.atlasLabelDelimiter = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'atlasLabelDelimiter','atlasDescriptorDelimiter','roiLabelDelimiter','nodeSidecarDelimiter'}, 'auto'));
            spec.atlasLabelHasHeader = NMDataIOConnectivityTools.pick(spec, {'atlasLabelHasHeader','atlasDescriptorHasHeader','roiLabelHasHeader','nodeSidecarHasHeader'}, 'auto');
            spec.atlasLabelIDColumn = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'atlasLabelIDColumn','atlasDescriptorIDColumn','roiIDColumn','nodeIDColumn'}, ''));
            spec.atlasLabelNameColumn = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'atlasLabelNameColumn','atlasDescriptorNameColumn','roiNameColumn','nodeNameColumn'}, ''));
            spec.atlasLabelXColumn = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'atlasLabelXColumn','atlasDescriptorXColumn','roiXColumn','nodeXColumn','xColumn'}, ''));
            spec.atlasLabelYColumn = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'atlasLabelYColumn','atlasDescriptorYColumn','roiYColumn','nodeYColumn','yColumn'}, ''));
            spec.atlasLabelZColumn = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'atlasLabelZColumn','atlasDescriptorZColumn','roiZColumn','nodeZColumn','zColumn'}, ''));
            spec.nodeCoordinateSpace = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'nodeCoordinateSpace','coordinateSpace'}, 'MNI'));
            spec.nodeCoordinateUnits = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'nodeCoordinateUnits','coordinateUnits'}, 'mm'));
            spec.weightingNodeOrder = lower(strrep(strrep(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'weightingNodeOrder','weightingOrder','nodeWeightingOrder'}, 'training')), '-', '_'), ' ', '_'));
            if isempty(spec.weightingNodeOrder), spec.weightingNodeOrder = 'training'; end
            spec.weightingEdgeMode = lower(strrep(strrep(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'weightingEdgeMode','edgeWeightingMode'}, 'auto')), '-', '_'), ' ', '_'));
            if isempty(spec.weightingEdgeMode), spec.weightingEdgeMode = 'auto'; end
            spec.weightingOrientation = lower(strrep(strrep(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'weightingOrientation','weightingVectorOrientation'}, 'maps_by_edges')), '-', '_'), ' ', '_'));
            if isempty(spec.weightingOrientation), spec.weightingOrientation = 'maps_by_edges'; end
            spec.weightingDim = double(NMDataIOConnectivityTools.pick(spec, {'weightingDim','weightingMapDim'}, NaN));
            if isempty(spec.weightingDim), spec.weightingDim = NaN; end
        end

        function [data, sourceFormat, caseIDs, fileInfo, messages] = resolveRawPayload(spec)
            messages = NMDataIOMessageTools.emptyMessages();
            data = [];
            caseIDs = {};
            fileInfo = struct('files',{{}},'matVariable','');
            sourceFormat = spec.sourceFormat;
            if strcmp(sourceFormat,'auto')
                if ~isempty(NMDataIOConnectivityTools.pick(spec, {'files','matrixFiles','connectivityFiles'}, {})) || ~isempty(NMDataIOConnectivityTools.pick(spec, {'classFileLists','classFiles'}, {}))
                    sourceFormat = 'file_per_subject';
                elseif istable(NMDataIOConnectivityTools.pick(spec, {'table','t_Y'}, []))
                    sourceFormat = 'table';
                elseif ~isempty(NMDataIOConnectivityTools.pick(spec, {'edgeMatrix','vectorizedData'}, []))
                    sourceFormat = 'vectorized';
                elseif ~isempty(NMDataIOConnectivityTools.pick(spec, {'data','Y','connectivityArray','matrixArray'}, []))
                    raw = NMDataIOConnectivityTools.pick(spec, {'data','Y','connectivityArray','matrixArray'}, []);
                    if isnumeric(raw) && ndims(raw) == 3
                        sourceFormat = 'array3d';
                    elseif isnumeric(raw) && ismatrix(raw)
                        sourceFormat = 'vectorized';
                    end
                end
            end
            switch sourceFormat
                case {'array3d','array_3d','3d'}
                    sourceFormat = 'array3d';
                    data = NMDataIOConnectivityTools.pick(spec, {'data','Y','connectivityArray','matrixArray'}, []);
                    data = NMDataIOConnectivityTools.resolveNamedValue(data);
                    if ~(isnumeric(data) || islogical(data)) || ndims(data) ~= 3
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.array3d', '3-D connectivity input must be a numeric/logical subjects-by-nodes-by-nodes array or a workspace variable name resolving to one.', 1, 'red*')];
                        return;
                    end
                    nSub = size(data, spec.subjectDim);
                    caseIDs = NMDataIOConnectivityTools.resolveSubjectCaseIDs(spec, nSub, {});
                case {'vectorized','edge_matrix','edges'}
                    sourceFormat = 'vectorized';
                    data = NMDataIOConnectivityTools.pick(spec, {'edgeMatrix','vectorizedData','data','Y'}, []);
                    data = NMDataIOConnectivityTools.resolveNamedValue(data);
                    if istable(data)
                        tableSpec = spec;
                        tableSpec.table = data;
                        tableSpec.sourceFormat = 'table';
                        [data, caseIDs, fileInfo, messages] = NMDataIOConnectivityTools.resolveTablePayload(tableSpec);
                        sourceFormat = 'table';
                        return;
                    end
                    if ~(isnumeric(data) || islogical(data)) || ~ismatrix(data)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.vectorized', 'Vectorized connectivity input must be a numeric/logical subjects-by-edges matrix or a workspace variable name resolving to one.', 1, 'red*')];
                        return;
                    end
                    caseIDs = NMDataIOConnectivityTools.resolveSubjectCaseIDs(spec, size(data,1), {});
                case {'table','edge_table'}
                    sourceFormat = 'table';
                    [data, caseIDs, fileInfo, messages] = NMDataIOConnectivityTools.resolveTablePayload(spec);
                case {'file_per_subject','files','file'}
                    sourceFormat = 'file_per_subject';
                    [data, caseIDs, fileInfo, messages] = NMDataIOConnectivityTools.readFilePerSubjectPayload(spec);
                otherwise
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.sourceFormat', sprintf('Unsupported connectivity source format ''%s''.', sourceFormat), 1, 'red*')];
            end
        end

        function [data, caseIDs, fileInfo, messages] = resolveTablePayload(spec)
            messages = NMDataIOMessageTools.emptyMessages();
            fileInfo = struct('source','table','edgeColumns',{{}},'edgeColumnIndices',[],'edgeIndex',[], ...
                'nNodes',[],'ignoredColumns',{{}},'selectionMode','','allowNoAtlas',false,'caseIDSource','', ...
                'caseIDColumn','','rowNamesUsed',false);
            T = NMDataIOConnectivityTools.pick(spec, {'table','t_Y'}, []);
            tableFile = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(spec,'tableFile',''));
            if isempty(T) && ~isempty(tableFile)
                caseColumn = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'caseColumn','caseIDColumn','tableCaseIDColumn','case_edit'}, ''));
                try
                    T = NMDataIOTableReadTools.probeWideNumericFile(tableFile, caseColumn);
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, 'NMDataIOConnectivityTools.resolveTablePayload')];
                    data = [];
                    caseIDs = {};
                    return;
                end
            elseif ischar(T) || (isstring(T) && isscalar(T))
                T = NMDataIOConnectivityTools.resolveNamedValue(T);
            end
            if ~(istable(T) || NMDataIOConnectivityTools.isWideNumericTableProbe(T))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table', 'Connectivity table input must resolve to a MATLAB table or a supported file-backed numeric table.', 1, 'red*')];
                data = [];
                caseIDs = {};
                return;
            end

            if NMDataIOConnectivityTools.isWideNumericTableProbe(T)
                caseIDs = T.caseIDs(:);
                caseInfo = struct('source','column','columnName',T.caseColumn,'columnIndex',T.caseColumnIndex);
                [caseIDs, caseMessages] = NMDataIOConnectivityTools.validateResolvedTableCaseIDs(caseIDs, T.nRows, caseInfo);
            else
                [caseIDs, caseInfo, caseMessages] = NMDataIOConnectivityTools.resolveTableCaseIDs(T, spec);
            end
            messages = [messages; caseMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                data = [];
                caseIDs = {};
                return;
            end
            fileInfo.caseIDSource = caseInfo.source;
            fileInfo.caseIDColumn = caseInfo.columnName;
            fileInfo.rowNamesUsed = strcmp(caseInfo.source,'row_names');

            hasNodeDescriptor = ~isempty(spec.atlasLabelFile);
            rawEdgeColumns = NMDataIOConnectivityTools.pick(spec, {'edgeColumns','edgeColumnIndices','featureColumns','features','feature_edit'}, []);
            hasExplicitEdgeColumns = ~isempty(rawEdgeColumns);
            if ischar(rawEdgeColumns) || (isstring(rawEdgeColumns) && isscalar(rawEdgeColumns))
                hasExplicitEdgeColumns = ~isempty(strtrim(char(string(rawEdgeColumns)))) && ~strcmp(strtrim(char(string(rawEdgeColumns))),'?');
            end
            if hasExplicitEdgeColumns
                [edgeColumns, edgeIndex, nNodes, ignoredColumns, columnMessages] = NMDataIOConnectivityTools.tableEdgeColumnsFromNumericSpec(T, caseInfo, spec);
                fileInfo.selectionMode = 'numeric_edge_columns';
                fileInfo.allowNoAtlas = ~hasNodeDescriptor;
            elseif hasNodeDescriptor
                [edgeColumns, edgeIndex, nNodes, ignoredColumns, columnMessages] = NMDataIOConnectivityTools.tableEdgeColumnsFromAtlasNames(T, caseInfo, spec);
                if isempty(edgeColumns) && ~NMDataIOMessageTools.hasFatal(columnMessages)
                    [edgeColumns, edgeIndex, nNodes, ignoredColumns, exactMessages] = NMDataIOConnectivityTools.tableEdgeColumnsFromExactNumericTable(T, caseInfo, spec);
                    columnMessages = [columnMessages; exactMessages];
                    if ~isempty(edgeColumns), fileInfo.selectionMode = 'all_numeric_exact_edge_count'; end
                else
                    fileInfo.selectionMode = 'sidecar_roi_names';
                end
            else
                [edgeColumns, edgeIndex, nNodes, ignoredColumns, columnMessages] = NMDataIOConnectivityTools.tableEdgeColumnsFromNumericSpec(T, caseInfo, spec);
                fileInfo.selectionMode = 'numeric_edge_columns';
                fileInfo.allowNoAtlas = true;
            end
            messages = [messages; columnMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                data = [];
                caseIDs = {};
                return;
            end
            if isempty(edgeColumns)
                if hasNodeDescriptor
                    msg = 'No connectivity table columns could be matched to ROI pairs in the ROI description file or to the complete expected edge set. Select the numeric edge columns explicitly.';
                else
                    msg = 'Connectivity table input without an ROI description file requires explicit numeric edge-column selections.';
                end
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', msg, 1, 'red*')];
                data = [];
                caseIDs = {};
                return;
            end

            if NMDataIOConnectivityTools.isWideNumericTableProbe(T)
                try
                    data = NMDataIOTableReadTools.readWideNumericColumns(T, edgeColumns);
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, 'NMDataIOConnectivityTools.resolveTablePayload')];
                    data = [];
                    return;
                end
            else
                try
                    data = table2array(T(:, edgeColumns));
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, 'NMDataIOConnectivityTools.resolveTablePayload')];
                    data = [];
                    return;
                end
            end
            if ~isnumeric(data) && ~islogical(data)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table', 'Connectivity table edge columns must be numeric/logical after edge-column selection.', 1, 'red*')];
                data = [];
                return;
            end
            fileInfo.edgeColumns = edgeColumns(:)';
            [tableNames, ~] = NMDataIOConnectivityTools.tableColumnSchema(T);
            fileInfo.edgeColumnIndices = find(ismember(tableNames, edgeColumns));
            fileInfo.edgeIndex = edgeIndex;
            fileInfo.nNodes = nNodes;
            fileInfo.ignoredColumns = ignoredColumns(:)';
            if ~isempty(ignoredColumns)
                messages = [messages; NMDataIOMessageTools.make('info', false, 'connectivity.table.ignoredColumns', sprintf('Connectivity table ignored %g non-edge column(s): %s.', numel(ignoredColumns), NMDataIOConnectivityTools.previewList(ignoredColumns, 8)), 0, 'blue')];
            end
        end

        function [caseIDs, info, messages] = resolveTableCaseIDs(T, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            caseIDs = {};
            info = struct('source','','columnName','','columnIndex',[]);
            rowNames = T.Properties.RowNames;
            if ~isempty(rowNames)
                caseIDs = NMDataIOConnectivityTools.asCellstr(rowNames);
                info.source = 'row_names';
            else
                caseColumn = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'caseColumn','caseIDColumn','tableCaseIDColumn','case_edit'}, ''));
                if isempty(caseColumn) || ~ismember(caseColumn, T.Properties.VariableNames)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.caseIDs', 'The connectivity table has no row names. Select the table variable containing case IDs; its column position is unrestricted.', 1, 'red*')];
                    return;
                end
                caseIDs = NMDataIOConnectivityTools.asCellstr(T.(caseColumn));
                info.source = 'column';
                info.columnName = caseColumn;
                info.columnIndex = find(strcmp(T.Properties.VariableNames, caseColumn),1);
            end
            caseIDs = caseIDs(:);
            [caseIDs, validationMessages] = NMDataIOConnectivityTools.validateResolvedTableCaseIDs(caseIDs, height(T), info);
            messages = [messages; validationMessages];
        end

        function [edgeColumns, edgeIndex, nNodes, ignoredColumns, messages] = tableEdgeColumnsFromAtlasNames(T, caseInfo, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            edgeColumns = {};
            edgeIndex = [];
            nNodes = [];
            ignoredColumns = {};
            opts = struct('delimiter',spec.atlasLabelDelimiter,'hasHeader',spec.atlasLabelHasHeader, ...
                'idColumn',spec.atlasLabelIDColumn,'nameColumn',spec.atlasLabelNameColumn, ...
                'xColumn',spec.atlasLabelXColumn,'yColumn',spec.atlasLabelYColumn,'zColumn',spec.atlasLabelZColumn);
            desc = NMDataIOAtlasDescriptorTools.resolveNodeDescriptorTable(spec.atlasLabelFile, opts);
            if ~NMDataIOConnectivityTools.fieldOr(desc,'ok',false)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.nodeDescriptor', NMDataIOConnectivityTools.fieldOr(desc,'message','The ROI description file could not be read.'), 1, 'red*')];
                return;
            end
            nodeNames = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.fieldOr(desc,'orderedNames',{}));
            nNodes = numel(nodeNames);
            normNames = NMDataIOConnectivityTools.normalizedNameList(nodeNames);
            if isempty(nodeNames) || numel(unique(normNames)) ~= numel(nodeNames)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.nodeDescriptor', 'ROI names in the ROI description file are missing or duplicated. NM2 therefore cannot match connectivity table columns safely by ROI name.', 1, 'red*')];
                return;
            end

            % Build normalized node aliases from the ROI-name authority. If the
            % sidecar also contains an Atlas column, accept Atlas+ROI_Name as an
            % alternative header token (e.g. Suit_Left_VI) without changing the
            % canonical node name stored in the connectivity provenance.
            nodeAliases = cell(nNodes,1);
            for i = 1:nNodes, nodeAliases{i} = {normNames{i}}; end
            nodeTable = NMDataIOConnectivityTools.fieldOr(desc,'orderedTable',table());
            if istable(nodeTable) && height(nodeTable) == nNodes
                atlasColumn = find(strcmpi(nodeTable.Properties.VariableNames,'Atlas'),1);
                if ~isempty(atlasColumn)
                    atlasValues = NMDataIOConnectivityTools.tableColumnText(nodeTable.(nodeTable.Properties.VariableNames{atlasColumn}));
                    for i = 1:nNodes
                        atlasToken = NMDataIOConnectivityTools.normalizeNameToken(atlasValues{i});
                        if ~isempty(atlasToken)
                            prefixed = [atlasToken normNames{i}];
                            if ~strcmp(prefixed,normNames{i}), nodeAliases{i}{end+1} = prefixed; end %#ok<AGROW>
                        end
                    end
                end
            end

            % Match complete header tokens against sidecar-defined ROI pairs.
            % This avoids delimiter parsing: ROI names themselves may contain
            % hyphens (e.g. pre-SMA), while table headers may use a single '-'.
            candidateIndex = NMDataIOConnectivityTools.defaultEdgeIndex(nNodes, spec);
            edgeMap = containers.Map('KeyType','char','ValueType','any');
            for e = 1:size(candidateIndex,1)
                ia = candidateIndex(e,1); ib = candidateIndex(e,2);
                for aa = 1:numel(nodeAliases{ia})
                    for bb = 1:numel(nodeAliases{ib})
                        keys = {[nodeAliases{ia}{aa} nodeAliases{ib}{bb}]};
                        if strcmp(spec.matrixType,'undirected') && ia ~= ib
                            keys{end+1} = [nodeAliases{ib}{bb} nodeAliases{ia}{aa}]; %#ok<AGROW>
                        end
                        for kk = 1:numel(keys)
                            key = keys{kk};
                            if isempty(key), continue; end
                            if isKey(edgeMap,key)
                                prior = edgeMap(key);
                                if ~isequal(prior,[ia ib]), edgeMap(key) = [0 0]; end
                            else
                                edgeMap(key) = [ia ib];
                            end
                        end
                    end
                end
            end

            [names, numericMask] = NMDataIOConnectivityTools.tableColumnSchema(T);
            unmatchedEdgeColumns = {};
            for c = 1:numel(names)
                nm = names{c};
                if strcmp(caseInfo.source,'column') && strcmp(nm, caseInfo.columnName)
                    ignoredColumns{end+1,1} = nm; %#ok<AGROW>
                    continue;
                end
                isNumeric = numericMask(c);
                header = regexprep(nm, '^(edge|conn|connectivity)[_\-]+', '', 'ignorecase');
                key = NMDataIOConnectivityTools.normalizeNameToken(header);
                mapped = [];
                if ~isempty(key) && isKey(edgeMap,key), mapped = edgeMap(key); end
                if any(mapped == 0), mapped = []; end
                if ~isempty(mapped)
                    if ~isNumeric
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', sprintf('ROI-pair column ''%s'' is not numeric/logical.', nm), 1, 'red*')];
                        return;
                    end
                    edgeColumns{end+1,1} = nm; %#ok<AGROW>
                    edgeIndex(end+1,:) = mapped; %#ok<AGROW>
                else
                    ignoredColumns{end+1,1} = nm; %#ok<AGROW>
                    edgeLikeName = contains(nm,'--') || contains(nm,'__') || contains(lower(nm),'_to_') || ...
                        contains(lower(nm),'-to-') || contains(lower(nm),' to ') || contains(nm,'->') || contains(nm,'<->') || contains(nm,'-');
                    if isNumeric && edgeLikeName
                        unmatchedEdgeColumns{end+1,1} = nm; %#ok<AGROW>
                    end
                end
            end
            if ~isempty(unmatchedEdgeColumns)
                missingNameText = '';
                generatedRows = NMDataIOConnectivityTools.fieldOr(desc,'generatedNameRows',[]);
                nodeIDs = double(NMDataIOConnectivityTools.fieldOr(desc,'nodeIDs',[]));
                if ~isempty(generatedRows) && ~isempty(nodeIDs)
                    generatedRows = generatedRows(generatedRows >= 1 & generatedRows <= numel(nodeIDs));
                    missingIDs = nodeIDs(generatedRows);
                    missingIDText = strjoin(arrayfun(@(x)sprintf('%g',x), missingIDs(:)', 'UniformOutput', false), ', ');
                    missingNameText = sprintf(' The ROI description file has %g row(s) without ROI names (ROI IDs: %s).', numel(generatedRows), missingIDText);
                end
                msg = sprintf(['The ROI description file cannot map %g connectivity edge column(s), e.g. %s. ' ...
                    'Every connectivity edge present in the table must identify two ROIs in the ROI description file. ' ...
                    'The ROI description file may contain additional ROIs or edges that are not present in this table.%s'], ...
                    numel(unmatchedEdgeColumns), NMDataIOConnectivityTools.previewList(unmatchedEdgeColumns, 6), missingNameText);
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', msg, 1, 'red*')];
                return;
            end
            if isempty(edgeColumns)
                messages = [messages; NMDataIOMessageTools.make('info', false, 'connectivity.table.edgeColumns', 'No table edge headers matched ROI pairs in the ROI description file. NM2 will use positional matching only if the numeric columns exactly represent the complete expected edge set.', 0, 'blue')];
                return;
            end
            if size(unique(edgeIndex,'rows'),1) ~= size(edgeIndex,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', 'Table contains duplicated ROI-pair edge columns after ROI-name mapping.', 1, 'red*')];
                return;
            end
            [~, canonicalPosition] = ismember(edgeIndex, candidateIndex, 'rows');
            [~, canonicalOrder] = sort(canonicalPosition);
            edgeColumns = edgeColumns(canonicalOrder);
            edgeIndex = edgeIndex(canonicalOrder,:);
            nExpected = size(candidateIndex,1);
            if numel(edgeColumns) < nExpected
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.table.edgeColumns', ...
                    sprintf('Matched %g connectivity edge column(s) to the ROI description file. The ROI description defines %g possible edge(s); additional ROIs or edges that are absent from this table are allowed.', numel(edgeColumns), nExpected), 0, 'green*')];
            end
        end

        function [edgeColumns, edgeIndex, nNodes, ignoredColumns, messages] = tableEdgeColumnsFromExactNumericTable(T, caseInfo, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            edgeColumns = {};
            edgeIndex = [];
            ignoredColumns = {};
            opts = struct('delimiter',spec.atlasLabelDelimiter,'hasHeader',spec.atlasLabelHasHeader, ...
                'idColumn',spec.atlasLabelIDColumn,'nameColumn',spec.atlasLabelNameColumn, ...
                'xColumn',spec.atlasLabelXColumn,'yColumn',spec.atlasLabelYColumn,'zColumn',spec.atlasLabelZColumn);
            desc = NMDataIOAtlasDescriptorTools.resolveNodeDescriptorTable(spec.atlasLabelFile, opts);
            if ~NMDataIOConnectivityTools.fieldOr(desc,'ok',false)
                nNodes = [];
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.nodeDescriptor', NMDataIOConnectivityTools.fieldOr(desc,'message','The ROI description file could not be read.'), 1, 'red*')];
                return;
            end
            nNodes = double(NMDataIOConnectivityTools.fieldOr(desc,'nRows',0));
            [allNames, allNumericMask] = NMDataIOConnectivityTools.tableColumnSchema(T);
            keep = true(size(allNames));
            if strcmp(caseInfo.source,'column')
                keep(strcmp(allNames,caseInfo.columnName)) = false;
            end
            candidates = allNames(keep);
            numericMask = allNumericMask(keep);
            if ~all(numericMask)
                ignoredColumns = candidates(~numericMask);
                return;
            end
            expectedIndex = NMDataIOConnectivityTools.defaultEdgeIndex(nNodes, spec);
            if numel(candidates) ~= size(expectedIndex,1)
                return;
            end
            edgeColumns = candidates;
            edgeIndex = expectedIndex;
            ignoredColumns = {};
            if strcmp(caseInfo.source,'column'), ignoredColumns = {caseInfo.columnName}; end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.table.edgeColumns', sprintf('All %g numeric table columns match the complete edge set for %g nodes.', numel(edgeColumns), nNodes), 0, 'green*')];
        end

        function [edgeColumns, edgeIndex, nNodes, ignoredColumns, messages] = tableEdgeColumnsFromNumericSpec(T, caseInfo, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            edgeColumns = {};
            edgeIndex = [];
            nNodes = [];
            ignoredColumns = {};
            raw = NMDataIOConnectivityTools.pick(spec, {'edgeColumns','edgeColumnIndices','featureColumns','features','feature_edit'}, []);
            [idx, idxMessages] = NMDataIOConnectivityTools.resolveNumericIndexVector(raw);
            messages = [messages; idxMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if isempty(idx)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', 'Select the numeric connectivity edge columns unless all numeric columns exactly match the complete edge set defined by the ROI description file.', 1, 'red*')];
                return;
            end
            idx = unique(idx(:)', 'stable');
            [names, tableNumericMask] = NMDataIOConnectivityTools.tableColumnSchema(T);
            nVars = numel(names);
            if any(idx < 1 | idx > nVars | idx ~= round(idx))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', sprintf('Edge-column indices must be integer values between 1 and %g.', nVars), 1, 'red*')];
                return;
            end
            if strcmp(caseInfo.source,'column') && any(idx == caseInfo.columnIndex)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', 'Edge-column indices include the selected case-ID column. Remove it from the edge-column vector.', 1, 'red*')];
                return;
            end
            edgeColumns = names(idx);
            ignoredColumns = setdiff(names, edgeColumns, 'stable');
            numericMask = tableNumericMask(idx);
            if ~all(numericMask)
                bad = edgeColumns(~numericMask);
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', sprintf('Selected edge column(s) must be numeric/logical. Non-numeric selected column(s): %s.', strjoin(bad, ', ')), 1, 'red*')];
                return;
            end
            nEdges = numel(edgeColumns);
            suppliedEdgeIndex = NMDataIOConnectivityTools.fieldOr(spec,'edgeIndex',[]);
            if ~isempty(suppliedEdgeIndex)
                edgeIndex = double(suppliedEdgeIndex);
                nNodes = max(edgeIndex(:));
            else
                nNodesSpec = double(NMDataIOConnectivityTools.pick(spec, {'nNodes','numNodes'}, NaN));
                if isfinite(nNodesSpec) && nNodesSpec > 0
                    nNodes = round(nNodesSpec);
                else
                    nNodes = NMDataIOConnectivityTools.inferNodeCountFromEdges(nEdges, spec);
                end
                if isnan(nNodes)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', sprintf('Cannot infer node count from %g selected edge column(s). Provide nNodes or edgeIndex.', nEdges), 1, 'red*')];
                    return;
                end
                edgeIndex = NMDataIOConnectivityTools.defaultEdgeIndex(nNodes, spec);
            end
            if size(edgeIndex,1) ~= nEdges
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', sprintf('Selected %g edge column(s), but the edge definition implies %g edge(s).', nEdges, size(edgeIndex,1)), 1, 'red*')];
            end
        end

        function tf = isWideNumericTableProbe(T)
            tf = isstruct(T) && isscalar(T) && ...
                isfield(T,'variableNames') && isfield(T,'numericMask') && ...
                isfield(T,'caseIDs') && isfield(T,'caseColumn') && ...
                isfield(T,'caseColumnIndex') && isfield(T,'nRows') && ...
                isfield(T,'importOptions');
        end

        function [names, numericMask] = tableColumnSchema(T)
            if istable(T)
                names = T.Properties.VariableNames;
                numericMask = false(size(names));
                for i = 1:numel(names)
                    v = T.(names{i});
                    numericMask(i) = isnumeric(v) || islogical(v);
                end
                return;
            end
            if NMDataIOConnectivityTools.isWideNumericTableProbe(T)
                names = NMDataIOConnectivityTools.asCellstr(T.variableNames);
                numericMask = logical(T.numericMask(:)');
                if numel(numericMask) ~= numel(names)
                    error('NMDataIOConnectivityTools:wideNumericSchemaMismatch', ...
                        'Wide numeric table schema has %g names but %g numeric-type flags.', numel(names), numel(numericMask));
                end
                return;
            end
            error('NMDataIOConnectivityTools:unsupportedTableSchema', ...
                'Connectivity table schema must be a MATLAB table or a file-backed numeric table probe.');
        end

        function [caseIDs, messages] = validateResolvedTableCaseIDs(caseIDs, nRows, info)
            messages = NMDataIOMessageTools.emptyMessages();
            caseIDs = NMDataIOConnectivityTools.asCellstr(caseIDs);
            caseIDs = caseIDs(:);
            if numel(caseIDs) ~= nRows
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.caseIDs', sprintf('Resolved %g case IDs for a table with %g rows.', numel(caseIDs), nRows), 1, 'red*')];
                return;
            end
            caseIDs = cellfun(@(x)strtrim(NMDataIOConnectivityTools.asChar(x)), caseIDs, 'UniformOutput', false);
            if any(cellfun(@isempty, caseIDs))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.caseIDs', 'Connectivity table case IDs contain empty values.', 1, 'red*')];
                return;
            end
            if numel(unique(caseIDs)) ~= numel(caseIDs)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.caseIDs', 'Connectivity table case IDs must be unique.', 1, 'red*')];
                return;
            end
            if strcmp(info.source,'row_names')
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.table.caseIDs', sprintf('Case IDs resolved from MATLAB table row names for %g subjects; no table feature column was removed.', numel(caseIDs)), 0, 'green*')];
            else
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.table.caseIDs', sprintf('Case IDs resolved from table variable ''%s'' at column %g.', info.columnName, info.columnIndex), 0, 'green*')];
            end
        end

        function [idx, messages] = resolveNumericIndexVector(raw)
            messages = NMDataIOMessageTools.emptyMessages();
            idx = [];
            if isempty(raw), return; end
            if isnumeric(raw) || islogical(raw)
                idx = double(raw(:)');
                return;
            end
            if iscell(raw) && numel(raw) == 1
                raw = raw{1};
            end
            if isstring(raw) && isscalar(raw), raw = char(raw); end
            if ischar(raw)
                expr = strtrim(raw);
                if isempty(expr) || strcmp(expr,'?'), return; end
                if isvarname(expr) && evalin('base', sprintf('exist(''%s'',''var'')', expr))
                    val = evalin('base', expr);
                    if ~(isnumeric(val) || islogical(val))
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', sprintf('Workspace variable ''%s'' is not a numeric vector.', expr), 1, 'red*')];
                        return;
                    end
                    idx = double(val(:)');
                    return;
                end
                try
                    NMDataIOConnectivityTools.validateNumericExpression(expr);
                    val = eval(expr); %#ok<EVLDIR> restricted by validateNumericExpression
                    if ~(isnumeric(val) || islogical(val))
                        error('NMDataIOConnectivityTools:exprNonNumeric','Expression did not evaluate to a numeric vector.');
                    end
                    idx = double(val(:)');
                catch ME
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', sprintf('Could not interpret edge-column expression ''%s'': %s', expr, ME.message), 1, 'red*')];
                end
                return;
            end
            messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.table.edgeColumns', 'Edge-column specification must be a numeric vector, numeric expression, or workspace vector name.', 1, 'red*')];
        end

        function validateNumericExpression(expr)
            expr = char(expr);
            if numel(expr) > 1000
                error('NMDataIOConnectivityTools:exprTooLong','Expression is too long.');
            end
            if contains(expr, ';') || contains(expr, '!') || contains(expr, '=') || contains(expr, char(39)) || contains(expr, char(34)) || contains(expr, '{') || contains(expr, '}') || contains(expr, '@') || contains(expr, '%') || contains(expr, '`')
                error('NMDataIOConnectivityTools:unsafeExpression','Expression contains unsupported or unsafe characters.');
            end
            ids = regexp(expr, '[A-Za-z_]\w*', 'match');
            allowed = {'inf','nan','pi','eps','linspace','logspace','unique','sort','fliplr','round','floor','ceil','abs','sqrt','exp','log','log10','double','single','e'};
            for i = 1:numel(ids)
                if ~any(strcmpi(ids{i}, allowed))
                    error('NMDataIOConnectivityTools:unsafeIdentifier','Identifier/function is not allowed in numeric expressions: %s', ids{i});
                end
            end
            if ~isempty(regexp(expr, '[^0-9A-Za-z_\.\+\-\*\/\^\:\,\[\]\(\)\s]', 'once'))
                error('NMDataIOConnectivityTools:unsafeExpression','Expression contains unsupported characters.');
            end
        end

        function out = normalizedNameList(c)
            c = NMDataIOConnectivityTools.asCellstr(c);
            out = cell(size(c));
            for i = 1:numel(c)
                out{i} = NMDataIOConnectivityTools.normalizeNameToken(c{i});
            end
        end

        function s = normalizeNameToken(s)
            s = lower(strtrim(NMDataIOConnectivityTools.asChar(s)));
            s = regexprep(s, '[^a-z0-9]+', '');
        end

        function s = previewList(c, maxN)
            c = NMDataIOConnectivityTools.asCellstr(c);
            if nargin < 2 || isempty(maxN), maxN = 8; end
            if isempty(c), s = ''; return; end
            n = min(numel(c), maxN);
            s = strjoin(c(1:n), ', ');
            if numel(c) > n, s = sprintf('%s, ...', s); end
        end

        function [atlasProv, messages] = tableFallbackAtlasProvenance(nNodes, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            if isempty(nNodes) || ~isfinite(nNodes) || nNodes < 1
                nNodes = 0;
            end
            nodeIDs = 1:nNodes;
            nodeLabels = arrayfun(@(i)sprintf('ROI_%03d', i), nodeIDs, 'UniformOutput', false);
            atlasProv = struct('atlasFile','','atlasFileProvided',spec.atlasFile, ...
                'atlasLocalizationUsed',false,'atlasLabelFile','','atlasLabelDescriptor',struct(), ...
                'nodeTable',table(nodeIDs(:), nodeLabels(:), 'VariableNames', {'node_id','node_label'}), ...
                'nodeIDs',nodeIDs,'nodeLabels',{nodeLabels},'nNodes',nNodes, ...
                'nodeCoordinates',[],'coordinateSource',{{}}, ...
                'originalNNodes',nNodes,'retainedNodeMask',true(1,nNodes), ...
                'atlasMatchSummary',struct(),'localizationSummary',struct(), ...
                'originalNodeIDs',nodeIDs,'originalNodeLabels',{nodeLabels}, ...
                'originalNodeCoordinates',[]);
            messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.table.noAtlas', 'Connectivity table import is proceeding without an ROI description file because the edge columns were selected explicitly. Atlas-based visualization will not be available for this modality.', 2, 'SystemCommands')];
        end

        function [data, caseIDs, fileInfo, messages] = readFilePerSubjectPayload(spec)
            messages = NMDataIOMessageTools.emptyMessages();
            fileInfo = struct('files',{{}},'matVariable',NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'matVariable','matrixVariable','fileVariable'}, '')));
            [files, groupSizes, groupNames] = NMDataIOConnectivityTools.resolveConnectivityFiles(spec);
            fileInfo.files = files(:)';
            if isempty(files)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.files', 'No connectivity matrix files were supplied.', 1, 'red*')];
                data = [];
                caseIDs = {};
                return;
            end
            nFiles = numel(files);
            caseIDs = NMDataIOConnectivityTools.resolveSubjectCaseIDs(spec, nFiles, files);
            if numel(caseIDs) ~= nFiles
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.caseIDs', sprintf('Explicit case-ID count (%g) differs from number of connectivity matrix files (%g).', numel(caseIDs), nFiles), 1, 'red*')];
                data = [];
                return;
            end
            M0 = [];
            data = [];
            for i = 1:nFiles
                [M, readMessages] = NMDataIOConnectivityTools.readSingleMatrixFile(files{i}, fileInfo.matVariable);
                messages = [messages; readMessages];
                if NMDataIOMessageTools.hasFatal(readMessages)
                    data = [];
                    return;
                end
                [ok, why] = NMDataIOConnectivityTools.isSquareNumericMatrix(M);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.files', sprintf('Connectivity file %s does not contain a valid numeric square matrix: %s.', files{i}, why), 1, 'red*')];
                    data = [];
                    return;
                end
                if isempty(M0)
                    M0 = M;
                    data = nan(nFiles, size(M0,1), size(M0,2));
                elseif any(size(M) ~= size(M0))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.files', sprintf('Connectivity file %s has matrix size %gx%g, but the first file has size %gx%g.', files{i}, size(M,1), size(M,2), size(M0,1), size(M0,2)), 1, 'red*')];
                    data = [];
                    return;
                end
                if ~NMDataIOConnectivityTools.isMirrored(M, spec.symmetryTolerance)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.files.symmetry', sprintf('Connectivity file %s is not mirrored along the diagonal within tolerance %.3g.', files{i}, spec.symmetryTolerance), 1, 'red*')];
                    data = [];
                    return;
                end
                data(i,:,:) = double(M);
            end
            if ~isempty(groupSizes)
                fileInfo.groupSizes = groupSizes;
                fileInfo.groupNames = groupNames;
            end
        end

        function [files, groupSizes, groupNames] = resolveConnectivityFiles(spec)
            groupSizes = [];
            groupNames = {};
            lists = NMDataIOConnectivityTools.fieldOr(spec,'classFileLists',[]);
            if isempty(lists), lists = NMDataIOConnectivityTools.fieldOr(spec,'classFiles',[]); end
            files = {};
            if ~isempty(lists)
                if isstruct(lists)
                    for i = 1:numel(lists)
                        nm = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(lists(i),'name',sprintf('Class_%d',i)));
                        fl = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.fieldOr(lists(i),'files',{}));
                        groupNames{end+1,1} = nm; %#ok<AGROW>
                        groupSizes(end+1) = numel(fl); %#ok<AGROW>
                        files = [files; fl(:)]; %#ok<AGROW>
                    end
                elseif iscell(lists)
                    for i = 1:numel(lists)
                        item = lists{i};
                        if isstruct(item)
                            nm = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.fieldOr(item,'name',sprintf('Class_%d',i)));
                            fl = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.fieldOr(item,'files',{}));
                        else
                            nm = sprintf('Class_%d', i);
                            fl = NMDataIOConnectivityTools.asCellstr(item);
                        end
                        groupNames{end+1,1} = nm; %#ok<AGROW>
                        groupSizes(end+1) = numel(fl); %#ok<AGROW>
                        files = [files; fl(:)]; %#ok<AGROW>
                    end
                end
                return;
            end
            files = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.pick(spec, {'files','matrixFiles','connectivityFiles'}, {}));
        end

        function [M, messages] = readSingleMatrixFile(filePath, matVariable)
            messages = NMDataIOMessageTools.emptyMessages();
            M = [];
            filePath = NMDataIOConnectivityTools.asChar(filePath);
            if isempty(filePath) || exist(filePath,'file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.fileRead', sprintf('Connectivity matrix file does not exist: %s.', filePath), 1, 'red*')];
                return;
            end
            [~,~,ext] = fileparts(filePath);
            ext = lower(ext);
            switch ext
                case '.mat'
                    S = load(filePath);
                    if ~isempty(matVariable)
                        if ~isfield(S, matVariable)
                            messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.fileRead', sprintf('MAT connectivity file %s does not contain variable ''%s''.', filePath, matVariable), 1, 'red*')];
                            return;
                        end
                        M = S.(matVariable);
                    else
                        fn = fieldnames(S);
                        hits = {};
                        for k = 1:numel(fn)
                            v = S.(fn{k});
                            if (isnumeric(v) || islogical(v)) && ismatrix(v) && size(v,1) == size(v,2)
                                hits{end+1} = fn{k}; %#ok<AGROW>
                            end
                        end
                        if numel(hits) ~= 1
                            if isempty(hits)
                                hitText = 'none';
                            else
                                hitText = strjoin(hits, ', ');
                            end
                            messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.fileRead', sprintf('MAT connectivity file %s contains %g numeric square matrix variable(s); provide matVariable to disambiguate. Candidate variable(s): %s.', filePath, numel(hits), hitText), 1, 'red*')];
                            return;
                        end
                        M = S.(hits{1});
                    end
                case {'.csv','.txt','.tsv'}
                    M = NMDataIOConnectivityTools.readSquareCsvMatrix(filePath);
                otherwise
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.fileRead', sprintf('Unsupported connectivity matrix file extension ''%s'' for %s. Supported formats are MAT and CSV/TSV/TXT.', ext, filePath), 1, 'red*')];
            end
        end

        function M = readSquareCsvMatrix(filePath)
            % File-per-subject connectivity CSV files are expected to carry a
            % header row; a nonnumeric row-label column is allowed and ignored.
            T = readtable(filePath, 'VariableNamingRule','preserve');
            varNames = T.Properties.VariableNames;
            numericVars = false(1, numel(varNames));
            for k = 1:numel(varNames)
                col = T.(varNames{k});
                numericVars(k) = isnumeric(col) || islogical(col);
            end
            if ~any(numericVars)
                error('NMDataIOConnectivityTools:csvNonNumeric', 'CSV connectivity matrix could not be converted to a numeric square matrix.');
            end
            A = table2array(T(:, numericVars));
            if size(A,1) ~= size(A,2) && size(A,1) == size(A,2)-1
                A = A(:,2:end);
            end
            M = double(A);
        end

        function [ok, why] = isSquareNumericMatrix(M)
            ok = false;
            why = '';
            if ~(isnumeric(M) || islogical(M))
                why = sprintf('class is %s, not numeric/logical', class(M));
                return;
            end
            if ~ismatrix(M)
                why = 'array is not two-dimensional';
                return;
            end
            if size(M,1) ~= size(M,2)
                why = sprintf('matrix is %gx%g, not square', size(M,1), size(M,2));
                return;
            end
            ok = true;
        end

        function tf = isMirrored(M, tol)
            D = double(M) - double(M.');
            D(~isfinite(D)) = 0;
            tf = max(abs(D(:))) <= tol;
        end

        function caseIDs = resolveSubjectCaseIDs(spec, nSub, files)
            rawIDs = NMDataIOConnectivityTools.pick(spec, {'caseIDs','caseIds','explicitCaseIDs','imageCaseIDs'}, {});
            if ~isempty(rawIDs)
                rawIDs = NMDataIOConnectivityTools.resolveNamedValue(rawIDs);
            end
            caseIDs = NMDataIOConnectivityTools.asCellstr(rawIDs);
            if isempty(caseIDs)
                caseIDMode = lower(NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'caseIDMode','caseMode'}, 'filename')));
                if strcmp(caseIDMode,'explicit')
                    caseIDs = {};
                elseif ~isempty(files)
                    caseIDs = cell(nSub,1);
                    for i = 1:nSub
                        [~,nm,~] = fileparts(files{i});
                        caseIDs{i} = nm;
                    end
                else
                    caseIDs = arrayfun(@(i)sprintf('S%04d', i), 1:nSub, 'UniformOutput', false)';
                end
            end
            caseIDs = caseIDs(:);
        end

        function [edgeIndex, nNodes, messages] = edgeIndexFromSpecAndPayload(spec, data, sourceFormat, fileInfo)
            if nargin < 4 || isempty(fileInfo), fileInfo = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            edgeIndex = [];
            nNodes = [];
            if strcmp(sourceFormat,'table') && isstruct(fileInfo) && isfield(fileInfo,'edgeIndex') && ~isempty(fileInfo.edgeIndex)
                edgeIndex = double(fileInfo.edgeIndex);
                nNodes = double(NMDataIOConnectivityTools.fieldOr(fileInfo,'nNodes', max(edgeIndex(:))));
                return;
            end
            suppliedEdgeIndex = NMDataIOConnectivityTools.fieldOr(spec,'edgeIndex',[]);
            if ~isempty(suppliedEdgeIndex)
                if ~(isnumeric(suppliedEdgeIndex) && size(suppliedEdgeIndex,2) == 2)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.edgeIndex', 'edgeIndex must be a numeric nEdges-by-2 matrix.', 1, 'red*')];
                    return;
                end
                edgeIndex = double(suppliedEdgeIndex);
                nNodes = max(edgeIndex(:));
                return;
            end
            nNodesSpec = double(NMDataIOConnectivityTools.pick(spec, {'nNodes','numNodes'}, NaN));
            switch sourceFormat
                case {'array3d','file_per_subject'}
                    sz = size(data);
                    if strcmp(sourceFormat,'array3d')
                        nodeDims = setdiff(1:3, spec.subjectDim, 'stable');
                        if numel(nodeDims) ~= 2 || sz(nodeDims(1)) ~= sz(nodeDims(2))
                            messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.dimensions', sprintf('3-D connectivity input must have two equal node dimensions; size is [%s] with subjectDim=%g.', num2str(sz), spec.subjectDim), 1, 'red*')];
                            return;
                        end
                        nNodes = sz(nodeDims(1));
                    else
                        nNodes = size(data,2);
                    end
                case {'vectorized','table'}
                    nEdges = size(data,2);
                    if isfinite(nNodesSpec) && nNodesSpec > 0
                        nNodes = round(nNodesSpec);
                    else
                        nNodes = NMDataIOConnectivityTools.inferNodeCountFromEdges(nEdges, spec);
                    end
                    if isnan(nNodes)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.edgeIndex', sprintf('Cannot infer node count from %g vectorized edge feature(s). Provide nNodes or edgeIndex.', nEdges), 1, 'red*')];
                        return;
                    end
                otherwise
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.edgeIndex', sprintf('Cannot determine edge index for source format %s.', sourceFormat), 1, 'red*')];
                    return;
            end
            edgeIndex = NMDataIOConnectivityTools.defaultEdgeIndex(nNodes, spec);
            if ismember(sourceFormat, {'vectorized','table'}) && size(edgeIndex,1) ~= size(data,2)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.edgeIndex', sprintf('Vectorized connectivity input has %g edge column(s), but nNodes=%g with matrixType=%s, triangle=%s, includeDiagonal=%g implies %g edge(s).', size(data,2), nNodes, spec.matrixType, spec.triangle, double(spec.includeDiagonal), size(edgeIndex,1)), 1, 'red*')];
            end
        end

        function nNodes = inferNodeCountFromEdges(nEdges, spec)
            nNodes = NaN;
            nEdges = double(nEdges);
            if strcmp(spec.matrixType,'directed')
                if spec.includeDiagonal
                    n = sqrt(nEdges);
                else
                    n = (1 + sqrt(1 + 4*nEdges))/2;
                end
            else
                if spec.includeDiagonal
                    n = (-1 + sqrt(1 + 8*nEdges))/2;
                else
                    n = (1 + sqrt(1 + 8*nEdges))/2;
                end
            end
            if isfinite(n) && abs(n - round(n)) < 1e-10 && n >= 1
                nNodes = round(n);
            end
        end

        function edgeIndex = defaultEdgeIndex(nNodes, spec)
            if strcmp(spec.matrixType,'directed')
                [i,j] = ndgrid(1:nNodes, 1:nNodes);
                if ~spec.includeDiagonal
                    keep = i ~= j;
                else
                    keep = true(size(i));
                end
                edgeIndex = [i(keep) j(keep)];
                return;
            end
            if strcmp(spec.triangle,'lower')
                mask = tril(true(nNodes), -double(~spec.includeDiagonal));
            else
                mask = triu(true(nNodes), double(~spec.includeDiagonal));
            end
            [i,j] = find(mask);
            edgeIndex = [i(:) j(:)];
        end

        function [atlasProv, messages] = resolveAtlasNodeProvenance(spec, nNodes)
            messages = NMDataIOMessageTools.emptyMessages();
            atlasProv = struct('atlasFile','','atlasFileProvided',spec.atlasFile,'atlasLocalizationUsed',false,'atlasLabelFile',spec.atlasLabelFile, ...
                'atlasLabelDescriptor',struct(),'nodeTable',table(),'nodeIDs',[],'nodeLabels',{{}}, ...
                'nodeCoordinates',nan(nNodes,3), ...
                'retainedNodeMask',true(1,nNodes),'nNodes',nNodes,'originalNNodes',nNodes, ...
                'atlasMatchSummary',struct(),'localizationSummary',struct());
            % Assign the per-node cell vector after scalar struct construction.
            % Passing an N-by-1 cell array directly to struct(...) expands the
            % result into an N-by-1 struct array and breaks subsequent dot assignment.
            atlasProv.coordinateSource = repmat({''}, nNodes, 1);
            if isempty(spec.atlasLabelFile)
                if ~isempty(spec.atlasFile)
                    cand = NMDataIOAtlasDescriptorTools.detectAtlasDescriptorCandidates(spec.atlasFile);
                    if strcmp(NMDataIOConnectivityTools.fieldOr(cand,'status','none'), 'single')
                        spec.atlasLabelFile = cand.files{1};
                        messages = [messages; NMDataIOMessageTools.make('info', false, 'connectivity.nodeDescriptor', sprintf('ROI description file detected automatically for connectivity import: %s.', spec.atlasLabelFile), 0, 'blue')];
                    end
                end
                if isempty(spec.atlasLabelFile)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeDescriptor', 'Connectivity import requires an ROI description file containing node IDs, node names, and their order.', 1, 'red*')];
                    return;
                end
            end
            if exist(spec.atlasLabelFile,'file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeDescriptor', sprintf('Connectivity ROI description file does not exist: %s.', spec.atlasLabelFile), 1, 'red*')];
                return;
            end
            opts = struct('delimiter',spec.atlasLabelDelimiter,'hasHeader',spec.atlasLabelHasHeader, ...
                'idColumn',spec.atlasLabelIDColumn,'nameColumn',spec.atlasLabelNameColumn, ...
                'xColumn',spec.atlasLabelXColumn,'yColumn',spec.atlasLabelYColumn,'zColumn',spec.atlasLabelZColumn, ...
                'coordinateSpace',spec.nodeCoordinateSpace,'coordinateUnits',spec.nodeCoordinateUnits);
            desc = NMDataIOAtlasDescriptorTools.resolveNodeDescriptorTable(spec.atlasLabelFile, opts);
            atlasProv.atlasLabelDescriptor = rmfield(desc, intersect(fieldnames(desc), {'descriptorTable','orderedTable','nodeCoordinates','coordinateSource'}));
            if ~NMDataIOConnectivityTools.fieldOr(desc,'ok',false)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeDescriptor', NMDataIOConnectivityTools.fieldOr(desc,'message','The connectivity ROI description file could not be read.'), 1, 'red*')];
                return;
            end
            nodeTable = NMDataIOConnectivityTools.fieldOr(desc, 'orderedTable', table());
            ids = NMDataIOConnectivityTools.numericVector(NMDataIOConnectivityTools.fieldOr(desc, 'orderedIDs', []));
            names = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.fieldOr(desc, 'orderedNames', {}));
            if isempty(nodeTable) || height(nodeTable) ~= nNodes || numel(ids) ~= nNodes || numel(names) ~= nNodes
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeDescriptor', sprintf('The ROI description file contains %g nodes, but the connectivity data contain %g nodes.', height(nodeTable), nNodes), 1, 'red*')];
                return;
            end
            if numel(unique(ids)) ~= numel(ids)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeDescriptor', 'The connectivity ROI description file contains duplicate node IDs.', 1, 'red*')];
                return;
            end
            if numel(unique(names)) ~= numel(names)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeDescriptor', 'The connectivity ROI description file contains duplicate node names, so edge feature names would be ambiguous.', 1, 'red*')];
                return;
            end
            coords = double(NMDataIOConnectivityTools.fieldOr(desc,'nodeCoordinates',nan(nNodes,3)));
            coordSource = NMDataIOConnectivityTools.fieldOr(desc,'coordinateSource',repmat({''},nNodes,1));
            sidecarValid = all(isfinite(coords),2);
            atlasMatch = struct('status','not_required','nSidecarIDs',double(nNodes),'nMatched',0,'missingSidecarIDs',[],'atlasOnlyIDs',[]);

            if ~all(sidecarValid)
                if isempty(spec.atlasFile)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.atlas', sprintf('Valid MNI coordinates were found for %g/%g nodes in the ROI description file. Select a labelled atlas image to locate the remaining nodes.', nnz(sidecarValid), nNodes), 1, 'red*')];
                    return;
                end
                if exist(spec.atlasFile,'file') ~= 2
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.atlas', sprintf('Connectivity labelled atlas image does not exist: %s.', spec.atlasFile), 1, 'red*')];
                    return;
                end
                atlasProv.atlasFile = spec.atlasFile;
                atlasProv.atlasLocalizationUsed = true;
                atlas = NMDataIOAtlasDescriptorTools.atlasNodeCoordinates(spec.atlasFile, ids);
                matched = logical(NMDataIOConnectivityTools.fieldOr(atlas,'matchedMask',false(1,nNodes)));
                atlasIDs = double(NMDataIOConnectivityTools.fieldOr(atlas,'atlasIDs',[]));
                if ~NMDataIOConnectivityTools.fieldOr(atlas,'ok',false) && isempty(atlasIDs)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.atlas', NMDataIOConnectivityTools.fieldOr(atlas,'message','The labelled atlas image could not be inspected.'), 1, 'red*')];
                    return;
                end
                atlasMatch = NMDataIOConnectivityTools.atlasMatchSummary(ids, atlasIDs, matched);
                if ~any(matched)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.atlasCorrespondence', 'The labelled atlas image and connectivity ROI description file do not contain any matching ROI IDs. Import cannot continue.', 1, 'red*')];
                    return;
                end
                atlasCoords = double(NMDataIOConnectivityTools.fieldOr(atlas,'coordinates',nan(nNodes,3)));
                atlasValid = matched(:) & all(isfinite(atlasCoords),2);
                fillMask = ~sidecarValid & atlasValid;
                coords(fillMask,:) = atlasCoords(fillMask,:);
                coordSource(fillMask) = repmat({'atlas_centroid'},nnz(fillMask),1);
                if strcmp(atlasMatch.status,'partial')
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.atlasCorrespondence', sprintf('The labelled atlas matched %g/%g ROI IDs. Only nodes with valid coordinates from the ROI description file or matching atlas labels will be imported.', atlasMatch.nMatched, nNodes), 2, 'SystemCommands')];
                else
                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.atlasCorrespondence', sprintf('The labelled atlas matched all %g ROI IDs from the ROI description file.', nNodes), 0, 'green*')];
                end
            else
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.nodeCoordinates', sprintf('Valid MNI coordinates were found in the ROI description file for all %g nodes; no atlas image is required.', nNodes), 0, 'green*')];
            end

            localized = all(isfinite(coords),2);
            if ~any(localized)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeLocalization', 'No connectivity nodes could be located using the ROI description file or labelled atlas.', 1, 'red*')];
                return;
            end
            if any(~localized)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.nodeLocalization', sprintf('%g/%g nodes could not be located and will be excluded together with their connected edges.', nnz(~localized), nNodes), 2, 'SystemCommands')];
            end
            nodeTable = NMDataIOConnectivityTools.attachCanonicalNodeCoordinates(nodeTable, coords, coordSource);
            atlasProv.nodeTable = nodeTable;
            atlasProv.nodeIDs = ids(:)';
            atlasProv.nodeLabels = names(:)';
            atlasProv.nodeCoordinates = coords;
            atlasProv.coordinateSource = coordSource(:);
            atlasProv.originalNodeIDs = atlasProv.nodeIDs;
            atlasProv.originalNodeLabels = atlasProv.nodeLabels;
            atlasProv.originalNodeCoordinates = coords;
            atlasProv.retainedNodeMask = localized(:)';
            atlasProv.atlasLabelFile = spec.atlasLabelFile;
            atlasProv.atlasMatchSummary = atlasMatch;
            atlasProv.localizationSummary = struct('status',NMDataIOConnectivityTools.fullPartial(localized), ...
                'nNodes',double(nNodes),'nLocalized',double(nnz(localized)),'nDropped',double(nnz(~localized)), ...
                'sidecarCoordinateCount',double(nnz(sidecarValid)),'atlasRequired',logical(~all(sidecarValid)));
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'connectivity.nodeDescriptor', sprintf('The connectivity ROI description file matches the %g-node edge set in the same node order.', nNodes), 0, 'green*')];
        end

        function [Y, edgeIndex, atlasProv, messages] = applyLocalizedNodeFilter(Y, edgeIndex, atlasProv)
            messages = NMDataIOMessageTools.emptyMessages();
            keepNodes = logical(atlasProv.retainedNodeMask);
            keepNodes = keepNodes(:)';
            if isempty(keepNodes) || all(keepNodes), return; end
            if size(Y,2) ~= size(edgeIndex,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeLocalization', 'Cannot apply node-localization filtering because vectorized edge count and edgeIndex rows differ.', 1, 'red*')];
                return;
            end
            keepEdges = keepNodes(edgeIndex(:,1)) & keepNodes(edgeIndex(:,2));
            if ~any(keepEdges)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.nodeLocalization', 'Node-localization filtering removed every connectivity edge.', 1, 'red*')];
                return;
            end
            map = zeros(1,numel(keepNodes));
            map(keepNodes) = 1:nnz(keepNodes);
            originalEdges = size(edgeIndex,1);
            originalEdgeIndex = edgeIndex;
            Y = Y(:,keepEdges);
            leftNode = map(originalEdgeIndex(keepEdges,1));
            rightNode = map(originalEdgeIndex(keepEdges,2));
            edgeIndex = [leftNode(:) rightNode(:)];
            atlasProv.originalEdgeIndex = originalEdgeIndex;
            atlasProv.retainedOriginalEdgeMask = keepEdges(:)';
            atlasProv.originalNodeTable = atlasProv.nodeTable;
            atlasProv.nodeTable = atlasProv.nodeTable(keepNodes,:);
            atlasProv.nodeIDs = atlasProv.nodeIDs(keepNodes);
            atlasProv.nodeLabels = atlasProv.nodeLabels(keepNodes);
            atlasProv.nodeCoordinates = atlasProv.nodeCoordinates(keepNodes,:);
            atlasProv.coordinateSource = atlasProv.coordinateSource(keepNodes);
            atlasProv.nNodes = nnz(keepNodes);
            atlasProv.retainedNodeMask = keepNodes;
            messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.nodeLocalization', sprintf('Connectivity data were reduced from %g to %g located nodes and from %g to %g edges.', numel(keepNodes), nnz(keepNodes), originalEdges, size(edgeIndex,1)), 2, 'SystemCommands')];
        end

        function [Y, messages] = vectorizePayload(data, sourceFormat, edgeIndex, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            if strcmp(sourceFormat,'array3d')
                order = [spec.subjectDim setdiff(1:3, spec.subjectDim, 'stable')];
                data = permute(data, order);
            end
            if ismember(sourceFormat, {'array3d','file_per_subject'})
                nSub = size(data,1);
                nEdges = size(edgeIndex,1);
                Y = nan(nSub, nEdges);
                for s = 1:nSub
                    M = squeeze(data(s,:,:));
                    if ~strcmp(sourceFormat,'file_per_subject') && strcmp(spec.matrixType,'undirected') && ~NMDataIOConnectivityTools.isMirrored(M, spec.symmetryTolerance)
                        messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.symmetry', sprintf('Subject %g connectivity matrix is not exactly mirrored within tolerance %.3g; %s triangle values are used.', s, spec.symmetryTolerance, spec.triangle), 2, 'SystemCommands')];
                    end
                    idx = sub2ind(size(M), edgeIndex(:,1), edgeIndex(:,2));
                    Y(s,:) = double(M(idx)).';
                end
            else
                Y = double(data);
            end
        end

        function names = edgeNames(edgeIndex, nodeLabels, nodeIDs, spec)
            nodeLabels = NMDataIOConnectivityTools.asCellstr(nodeLabels);
            if isempty(nodeLabels)
                nodeLabels = arrayfun(@(id)sprintf('ROI_%g', id), nodeIDs, 'UniformOutput', false);
            end
            nEdges = size(edgeIndex,1);
            names = cell(nEdges,1);
            if strcmp(spec.matrixType,'directed')
                sep = '->';
            else
                sep = '--';
            end
            for e = 1:nEdges
                names{e} = sprintf('%s%s%s', NMDataIOConnectivityTools.cleanFeatureToken(nodeLabels{edgeIndex(e,1)}), sep, NMDataIOConnectivityTools.cleanFeatureToken(nodeLabels{edgeIndex(e,2)}));
            end
        end

        function s = cleanFeatureToken(s)
            s = regexprep(strtrim(NMDataIOConnectivityTools.asChar(s)), '\s+', '_');
            if isempty(s), s = 'ROI'; end
        end

        function [names, messages] = validateUniqueEdgeNames(names)
            messages = NMDataIOMessageTools.emptyMessages();
            if numel(unique(names)) ~= numel(names)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.edgeNames', 'Generated connectivity edge names are not unique. Check for duplicate node names or provide unique ROI names in the ROI description file.', 1, 'red*')];
            end
        end

        function T = attachCanonicalNodeCoordinates(T, coords, source)
            if isempty(T), return; end
            T.nm_mni_x = coords(:,1);
            T.nm_mni_y = coords(:,2);
            T.nm_mni_z = coords(:,3);
            T.nm_coordinate_source = source(:);
        end

        function summary = atlasMatchSummary(sidecarIDs, atlasIDs, matched)
            sidecarIDs = double(sidecarIDs(:)');
            atlasIDs = double(atlasIDs(:)');
            matched = logical(matched(:)');
            if numel(matched) ~= numel(sidecarIDs), matched = ismember(sidecarIDs,atlasIDs); end
            nMatched = nnz(matched);
            if nMatched == numel(sidecarIDs) && ~isempty(sidecarIDs)
                status = 'full';
            elseif nMatched > 0
                status = 'partial';
            else
                status = 'none';
            end
            summary = struct('status',status,'nSidecarIDs',double(numel(sidecarIDs)),'nMatched',double(nMatched), ...
                'missingSidecarIDs',sidecarIDs(~matched),'atlasOnlyIDs',setdiff(atlasIDs,sidecarIDs,'stable'));
        end

        function status = fullPartial(mask)
            mask = logical(mask(:));
            if all(mask), status = 'full'; elseif any(mask), status = 'partial'; else, status = 'none'; end
        end

        function prov = buildProvenance(spec, sourceFormat, data, caseIDs, edgeIndex, edgeNames, atlasProv, fileInfo)
            prov = struct();
            prov.sourceFamily = 'connectivity';
            prov.sourceFormat = sourceFormat;
            prov.originalShape = size(data);
            prov.nSubjects = numel(caseIDs);
            prov.nNodes = atlasProv.nNodes;
            prov.nEdges = size(edgeIndex,1);
            prov.nodeTable = atlasProv.nodeTable;
            prov.nodeIDs = atlasProv.nodeIDs;
            prov.nodeLabels = atlasProv.nodeLabels;
            prov.edgeIndex = edgeIndex;
            prov.edgeNames = edgeNames(:)';
            prov.matrixType = spec.matrixType;
            prov.triangle = spec.triangle;
            prov.includeDiagonal = logical(spec.includeDiagonal);
            prov.symmetryTolerance = spec.symmetryTolerance;
            prov.vectorizationOrder = NMDataIOConnectivityTools.vectorizationOrderText(spec);
            prov.atlasFile = atlasProv.atlasFile;
            prov.atlasFileProvided = atlasProv.atlasFileProvided;
            prov.atlasLocalizationUsed = logical(atlasProv.atlasLocalizationUsed);
            prov.atlasLabelFile = atlasProv.atlasLabelFile;
            prov.atlasLabelDelimiter = spec.atlasLabelDelimiter;
            prov.atlasLabelHasHeader = spec.atlasLabelHasHeader;
            prov.atlasLabelIDColumn = spec.atlasLabelIDColumn;
            prov.atlasLabelNameColumn = spec.atlasLabelNameColumn;
            prov.atlasLabelXColumn = spec.atlasLabelXColumn;
            prov.atlasLabelYColumn = spec.atlasLabelYColumn;
            prov.atlasLabelZColumn = spec.atlasLabelZColumn;
            prov.nodeCoordinateSpace = spec.nodeCoordinateSpace;
            prov.nodeCoordinateUnits = spec.nodeCoordinateUnits;
            prov.nodeCoordinates = atlasProv.nodeCoordinates;
            prov.nodeCoordinateSource = atlasProv.coordinateSource;
            prov.originalNNodes = atlasProv.originalNNodes;
            prov.retainedNodeMask = atlasProv.retainedNodeMask;
            prov.atlasMatchSummary = atlasProv.atlasMatchSummary;
            prov.nodeLocalizationSummary = atlasProv.localizationSummary;
            prov.originalNodeIDs = atlasProv.originalNodeIDs;
            prov.originalNodeLabels = atlasProv.originalNodeLabels;
            prov.originalNodeCoordinates = atlasProv.originalNodeCoordinates;
            prov.originalEdgeIndex = NMDataIOConnectivityTools.fieldOr(atlasProv,'originalEdgeIndex',edgeIndex);
            prov.retainedOriginalEdgeMask = NMDataIOConnectivityTools.fieldOr(atlasProv,'retainedOriginalEdgeMask',true(1,size(edgeIndex,1)));
            prov.atlasLabelDescriptor = atlasProv.atlasLabelDescriptor;
            prov.fileInfo = fileInfo;
        end

        function txt = vectorizationOrderText(spec)
            if strcmp(spec.matrixType,'directed')
                if spec.includeDiagonal, txt = 'directed_all_i_j_row_major'; else, txt = 'directed_offdiagonal_i_j_row_major'; end
            else
                txt = sprintf('undirected_%s_triangle_diagonal_%s', spec.triangle, NMDataIOConnectivityTools.yesNo(spec.includeDiagonal));
            end
        end

        function [labels, groupNames, messages] = legacyGroupLabels(spec, nSubjects)
            messages = NMDataIOMessageTools.emptyMessages();
            sizes = NMDataIOConnectivityTools.numericVector(NMDataIOConnectivityTools.pick(spec, {'groupSizes','imageGroupSizes','classGroupSizes'}, []));
            groupNames = NMDataIOConnectivityTools.caseCellField(spec, {'groupNames','imageGroupNames','desc_groups'});
            fileInfo = NMDataIOConnectivityTools.fieldOr(spec,'fileInfo',struct());
            if isempty(sizes) && isfield(fileInfo,'groupSizes'), sizes = fileInfo.groupSizes; end
            if isempty(groupNames) && isfield(fileInfo,'groupNames'), groupNames = fileInfo.groupNames; end
            if isempty(sizes)
                [~, sizes, groupNames0] = NMDataIOConnectivityTools.resolveConnectivityFiles(spec);
                if isempty(groupNames), groupNames = groupNames0; end
            end
            if isempty(sizes)
                labels = [];
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.labels.legacyGroups', 'Sequential/auto connectivity label mode requires class-specific file lists or explicit groupSizes.', 1, 'red*')];
                return;
            end
            sizes = round(double(sizes(:)'));
            if any(~isfinite(sizes)) || any(sizes < 1) || sum(sizes) ~= nSubjects
                labels = [];
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.labels.legacyGroups', sprintf('Connectivity group sizes must be positive integers that sum to the number of subjects (%g); received sum=%g.', nSubjects, sum(sizes)), 1, 'red*')];
                return;
            end
            labels = [];
            for i = 1:numel(sizes)
                labels = [labels; i*ones(sizes(i),1)]; %#ok<AGROW>
            end
            if numel(groupNames) < numel(sizes)
                for i = (numel(groupNames)+1):numel(sizes)
                    groupNames{i,1} = sprintf('Class_%d', i); %#ok<AGROW>
                end
            end
            groupNames = groupNames(1:numel(sizes));
        end

        function names = regressionLabelNames(spec, nLabels)
            names = NMDataIOConnectivityTools.caseCellField(spec, {'labelNames','desc_labels','labelnames'});
            if isempty(names)
                names = arrayfun(@(k)sprintf('Label_%03d', k), 1:nLabels, 'UniformOutput', false);
            end
            names = names(:)';
        end

        function mode = normalizedLabelMode(mode)
            mode = lower(strrep(strrep(NMDataIOConnectivityTools.asChar(mode), '-', '_'), ' ', '_'));
            if ismember(mode, {'legacy_group','groups','group_blocks','classification_groups','auto_groups','sequential_groups'})
                mode = 'legacy_groups';
            elseif isempty(mode)
                mode = 'metadata';
            end
        end

        function keys = edgeKeysFromIDs(nodeIDs, edgeIndex, matrixType)
            nodeIDs = NMDataIOConnectivityTools.numericVector(nodeIDs);
            edgeIndex = double(edgeIndex);
            matrixType = lower(NMDataIOConnectivityTools.asChar(matrixType));
            keys = cell(size(edgeIndex,1),1);
            for k = 1:size(edgeIndex,1)
                a = nodeIDs(edgeIndex(k,1));
                b = nodeIDs(edgeIndex(k,2));
                if ~strcmp(matrixType,'directed')
                    if b < a
                        tmp = a; a = b; b = tmp;
                    end
                    keys{k} = sprintf('%s--%s', NMDataIOConnectivityTools.nodeIDKey(a), NMDataIOConnectivityTools.nodeIDKey(b));
                else
                    keys{k} = sprintf('%s->%s', NMDataIOConnectivityTools.nodeIDKey(a), NMDataIOConnectivityTools.nodeIDKey(b));
                end
            end
        end

        function key = nodeIDKey(v)
            if isnumeric(v) || islogical(v)
                key = sprintf('%.15g', double(v));
            else
                key = NMDataIOConnectivityTools.asChar(v);
            end
        end

        function txt = shortNumericList(v, maxN)
            if nargin < 2 || isempty(maxN), maxN = 10; end
            v = double(v(:)');
            if isempty(v), txt = ''; return; end
            n = min(numel(v), maxN);
            parts = arrayfun(@(x)sprintf('%.15g', x), v(1:n), 'UniformOutput', false);
            txt = strjoin(parts, ', ');
            if numel(v) > n
                txt = sprintf('%s, ...', txt);
            end
        end

        function txt = shortCellList(c, maxN)
            if nargin < 2 || isempty(maxN), maxN = 10; end
            c = NMDataIOConnectivityTools.asCellstr(c);
            if isempty(c), txt = ''; return; end
            n = min(numel(c), maxN);
            txt = strjoin(c(1:n), ', ');
            if numel(c) > n
                txt = sprintf('%s, ...', txt);
            end
        end

        function txt = edgeSpaceChangeText(report)
            parts = {};
            if isfield(report,'nodeOrderChanged') && report.nodeOrderChanged
                parts{end+1} = 'node order changed'; %#ok<AGROW>
            end
            if isfield(report,'edgeOrderChanged') && report.edgeOrderChanged
                parts{end+1} = 'edge order changed'; %#ok<AGROW>
            end
            if isfield(report,'nExtraEdges') && report.nExtraEdges > 0
                parts{end+1} = sprintf('%g extra edge(s) ignored', report.nExtraEdges); %#ok<AGROW>
            end
            if isempty(parts)
                txt = '';
            else
                txt = [' (' strjoin(parts, '; ') ')'];
            end
        end

        function tf = hasWeightingSpec(spec)
            tf = false;
            if ~isstruct(spec), return; end
            fields = {'weightingMatrices','weightingMaps','weightingData','Yw','weightingFiles','weightingMapFiles','Pw'};
            for i = 1:numel(fields)
                if isfield(spec, fields{i}) && ~isempty(spec.(fields{i}))
                    tf = true;
                    return;
                end
            end
        end

        function [Yw, names, prov, messages] = resolveWeightingPayload(connOut, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            Yw = [];
            names = {};
            prov = struct();
            edgeIndex = connOut.provenance.edgeIndex;
            nEdges = size(edgeIndex,1);
            nNodes = double(connOut.provenance.nNodes);
            nodeIDs = connOut.provenance.nodeIDs;
            matrixType = connOut.provenance.matrixType;
            source = 'none';

            if ~isempty(NMDataIOConnectivityTools.pick(spec, {'weightingFiles','weightingMapFiles','Pw'}, {}))
                files = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.pick(spec, {'weightingFiles','weightingMapFiles','Pw'}, {}));
                [Yw, messages] = NMDataIOConnectivityTools.resolveWeightingFiles(files, connOut, spec);
                source = 'files';
            else
                raw = NMDataIOConnectivityTools.pick(spec, {'weightingMatrices','weightingMaps','weightingData','Yw'}, []);
                raw = NMDataIOConnectivityTools.resolveNamedValue(raw);
                [Yw, messages, source] = NMDataIOConnectivityTools.resolveWeightingArray(raw, connOut, spec);
            end
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if isempty(Yw)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting', ...
                    'Connectivity weighting maps were specified but no weighting matrix was resolved.', 1, 'red*')];
                return;
            end
            if size(Yw,2) ~= nEdges
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeCount', ...
                    sprintf('Connectivity weighting matrix has %g edge column(s), but the modality has %g edge feature(s).', size(Yw,2), nEdges), 1, 'red*')];
                return;
            end
            if all(isnan(Yw(:)))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.missing', ...
                    'All connectivity weighting values are NaN.', 1, 'red*')];
                return;
            end
            if any(isnan(Yw(:)))
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.missing', ...
                    'Connectivity weighting maps contain NaN values.', 2, 'SystemCommands')];
            end
            names = NMDataIOConnectivityTools.weightingNames(spec, size(Yw,1));
            if numel(names) ~= size(Yw,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.names', ...
                    sprintf('Number of connectivity weighting names (%g) differs from number of weighting maps (%g).', numel(names), size(Yw,1)), 1, 'red*')];
                return;
            end
            prov = struct();
            prov.hasWeightingMaps = true;
            prov.nWeightingMaps = size(Yw,1);
            prov.weightingNames = names(:)';
            prov.source = source;
            prov.nodeOrder = spec.weightingNodeOrder;
            prov.edgeMode = spec.weightingEdgeMode;
            prov.orientation = spec.weightingOrientation;
            prov.nNodes = nNodes;
            prov.nEdges = nEdges;
            prov.matrixType = matrixType;
            prov.edgeIndex = edgeIndex;
            prov.edgeNames = connOut.featnames(:)';
            prov.nodeIDs = nodeIDs;
        end

        function [Yw, messages] = resolveWeightingFiles(files, connOut, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            Yw = [];
            if isempty(files)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.files', ...
                    'No connectivity weighting files were supplied.', 1, 'red*')];
                return;
            end
            nMaps = numel(files);
            nEdges = size(connOut.provenance.edgeIndex,1);
            Yw = nan(nMaps, nEdges);
            matVariable = NMDataIOConnectivityTools.asChar(NMDataIOConnectivityTools.pick(spec, {'weightingVariable','weightingMatVariable','weightingMATVariable'}, ''));
            for i = 1:nMaps
                [M, readMessages] = NMDataIOConnectivityTools.readSingleMatrixFile(files{i}, matVariable);
                messages = [messages; readMessages]; %#ok<AGROW>
                if NMDataIOMessageTools.hasFatal(readMessages), return; end
                [row, mapMessages] = NMDataIOConnectivityTools.vectorizeSquareWeighting(M, connOut, spec, sprintf('file %s', files{i}));
                messages = [messages; mapMessages]; %#ok<AGROW>
                if NMDataIOMessageTools.hasFatal(mapMessages), return; end
                Yw(i,:) = row;
            end
        end

        function [Yw, messages, source] = resolveWeightingArray(raw, connOut, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            Yw = [];
            source = 'array';
            if isempty(raw)
                return;
            end
            if ~(isnumeric(raw) || islogical(raw))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.array', ...
                    sprintf('Connectivity weightingMatrices must be numeric/logical; received %s.', class(raw)), 1, 'red*')];
                return;
            end
            raw = double(raw);
            nNodes = connOut.provenance.nNodes;
            nEdges = size(connOut.provenance.edgeIndex,1);
            if ndims(raw) == 3
                sz = size(raw);
                if isfinite(spec.weightingDim) && ismember(round(spec.weightingDim), 1:3)
                    mapDim = round(spec.weightingDim);
                    nodeDims = setdiff(1:3, mapDim, 'stable');
                    if sz(nodeDims(1)) ~= nNodes || sz(nodeDims(2)) ~= nNodes
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.dimensions', ...
                            sprintf('Connectivity weighting stack dimensions [%s] do not contain %g-by-%g node dimensions for weightingDim=%g.', num2str(sz), nNodes, nNodes, mapDim), 1, 'red*')];
                        return;
                    end
                    raw = permute(raw, [mapDim nodeDims]);
                elseif sz(2) == nNodes && sz(3) == nNodes
                    raw = raw;
                elseif sz(1) == nNodes && sz(2) == nNodes
                    raw = permute(raw, [3 1 2]);
                else
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.dimensions', ...
                        sprintf('Connectivity weighting stack dimensions [%s] are incompatible with %g nodes. Use nMaps-by-nNodes-by-nNodes or nNodes-by-nNodes-by-nMaps.', num2str(sz), nNodes), 1, 'red*')];
                    return;
                end
                nMaps = size(raw,1);
                Yw = nan(nMaps, nEdges);
                for i = 1:nMaps
                    [Yw(i,:), mapMessages] = NMDataIOConnectivityTools.vectorizeSquareWeighting(squeeze(raw(i,:,:)), connOut, spec, sprintf('weighting map %g', i));
                    messages = [messages; mapMessages]; %#ok<AGROW>
                    if NMDataIOMessageTools.hasFatal(mapMessages), return; end
                end
                source = 'square_stack';
                return;
            end
            if ismatrix(raw) && size(raw,1) == nNodes && size(raw,2) == nNodes
                [row, mapMessages] = NMDataIOConnectivityTools.vectorizeSquareWeighting(raw, connOut, spec, 'weighting matrix');
                messages = [messages; mapMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                Yw = row;
                source = 'square_matrix';
                return;
            end
            if ismatrix(raw)
                [Yw, messages] = NMDataIOConnectivityTools.resolveVectorizedWeighting(raw, connOut, spec);
                source = 'vectorized';
                return;
            end
            messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.dimensions', ...
                sprintf('Connectivity weighting matrix has unsupported dimensions [%s].', num2str(size(raw))), 1, 'red*')];
        end

        function [row, messages] = vectorizeSquareWeighting(M, connOut, spec, label)
            messages = NMDataIOMessageTools.emptyMessages();
            row = [];
            if nargin < 4 || isempty(label), label = 'weighting matrix'; end
            [ok, why] = NMDataIOConnectivityTools.isSquareNumericMatrix(M);
            if ~ok
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.square', ...
                    sprintf('Connectivity %s is not a usable square numeric matrix: %s.', label, why), 1, 'red*')];
                return;
            end
            nNodes = connOut.provenance.nNodes;
            if size(M,1) ~= nNodes
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.nNodes', ...
                    sprintf('Connectivity %s has %g nodes, but the connectivity modality has %g nodes.', label, size(M,1), nNodes), 1, 'red*')];
                return;
            end
            if strcmp(connOut.provenance.matrixType,'undirected') && ~NMDataIOConnectivityTools.isMirrored(M, connOut.provenance.symmetryTolerance)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.symmetry', ...
                    sprintf('Connectivity %s is asymmetric, but the modality is undirected. Do not silently average asymmetric weighting matrices.', label), 1, 'red*')];
                return;
            end
            if ~connOut.provenance.includeDiagonal
                d = diag(double(M));
                if any(isfinite(d) & abs(d) > connOut.provenance.symmetryTolerance)
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.diagonal', ...
                        sprintf('Connectivity %s has nonzero diagonal values; diagonal entries are ignored because includeDiagonal=false.', label), 2, 'SystemCommands')];
                end
            end
            if strcmp(spec.weightingNodeOrder,'training') || strcmp(spec.weightingNodeOrder,'row_order')
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.nodeOrder', ...
                    'Connectivity square weighting map is vectorized by declared training row/column order. This is valid only if the weighting matrix uses the same node order as the training connectivity modality.', 2, 'SystemCommands')];
            end
            idx = sub2ind(size(M), connOut.provenance.edgeIndex(:,1), connOut.provenance.edgeIndex(:,2));
            row = double(M(idx)).';
        end

        function [Yw, messages] = resolveVectorizedWeighting(raw, connOut, spec)
            messages = NMDataIOMessageTools.emptyMessages();
            Yw = [];
            nEdges = size(connOut.provenance.edgeIndex,1);
            if size(raw,2) == nEdges
                Yw0 = double(raw);
            elseif size(raw,1) == nEdges && (strcmp(spec.weightingOrientation,'edges_by_maps') || size(raw,2) ~= nEdges)
                Yw0 = double(raw).';
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.orientation', ...
                    'Connectivity vectorized weighting matrix was interpreted as edges-by-maps and transposed to maps-by-edges.', 2, 'SystemCommands')];
            else
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeCount', ...
                    sprintf('Vectorized connectivity weighting matrix size [%s] is incompatible with %g connectivity edges.', num2str(size(raw)), nEdges), 1, 'red*')];
                return;
            end

            edgeIndexW = NMDataIOConnectivityTools.fieldOr(spec, 'weightingEdgeIndex', []);
            edgeNamesW = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.fieldOr(spec, 'weightingEdgeNames', {}));
            mode = spec.weightingEdgeMode;
            if strcmp(mode,'auto')
                if ~isempty(edgeIndexW)
                    mode = 'edge_index';
                elseif ~isempty(edgeNamesW)
                    mode = 'edge_names';
                else
                    mode = 'training_order';
                end
            end
            switch mode
                case 'training_order'
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.edgeOrder', ...
                        'Connectivity vectorized weighting map is assumed to be in exact training feature order. No edge-ID/name remapping was performed.', 2, 'SystemCommands')];
                    Yw = Yw0;
                case 'edge_index'
                    if isempty(edgeIndexW) || ~(isnumeric(edgeIndexW) && size(edgeIndexW,2) == 2)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeIndex', ...
                            'weightingEdgeMode=edge_index requires numeric weightingEdgeIndex with nEdges-by-2 columns.', 1, 'red*')];
                        return;
                    end
                    if size(edgeIndexW,1) ~= size(Yw0,2)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeIndex', ...
                            sprintf('weightingEdgeIndex has %g row(s), but vectorized weighting matrix has %g edge column(s).', size(edgeIndexW,1), size(Yw0,2)), 1, 'red*')];
                        return;
                    end
                    [Yw, mapMessages] = NMDataIOConnectivityTools.reorderVectorizedWeightingByEdgeIndex(Yw0, edgeIndexW, connOut);
                    messages = [messages; mapMessages];
                case 'edge_names'
                    if isempty(edgeNamesW) || numel(edgeNamesW) ~= size(Yw0,2)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeNames', ...
                            'weightingEdgeMode=edge_names requires weightingEdgeNames with one name per vectorized weighting column.', 1, 'red*')];
                        return;
                    end
                    [Yw, mapMessages] = NMDataIOConnectivityTools.reorderVectorizedWeightingByEdgeNames(Yw0, edgeNamesW, connOut.featnames);
                    messages = [messages; mapMessages];
                otherwise
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeMode', ...
                        sprintf('Unsupported weightingEdgeMode: %s.', mode), 1, 'red*')];
            end
        end

        function [Yw, messages] = reorderVectorizedWeightingByEdgeIndex(Yw0, edgeIndexW, connOut)
            messages = NMDataIOMessageTools.emptyMessages();
            Yw = [];
            trainNodeIDs = connOut.provenance.nodeIDs(:);
            edgeIndexW = double(edgeIndexW);
            if all(edgeIndexW(:) >= 1 & edgeIndexW(:) <= numel(trainNodeIDs) & abs(edgeIndexW(:)-round(edgeIndexW(:))) < 1e-10)
                wNodeIDs = trainNodeIDs(round(edgeIndexW));
            else
                wNodeIDs = edgeIndexW;
            end
            trainKeys = NMDataIOConnectivityTools.edgeKeysFromIDs(trainNodeIDs, connOut.provenance.edgeIndex, connOut.provenance.matrixType);
            weightKeys = cell(size(edgeIndexW,1),1);
            for e = 1:size(edgeIndexW,1)
                weightKeys{e} = NMDataIOConnectivityTools.edgeKeyFromNodeIDs(wNodeIDs(e,1), wNodeIDs(e,2), connOut.provenance.matrixType);
            end
            if numel(unique(weightKeys)) ~= numel(weightKeys)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeIndex', ...
                    'weightingEdgeIndex contains duplicate connectivity edges.', 1, 'red*')];
                return;
            end
            [tf, loc] = ismember(trainKeys, weightKeys);
            if ~all(tf)
                missing = trainKeys(~tf);
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeIndex', ...
                    sprintf('Vectorized weighting map is missing %g required connectivity edge(s), e.g. %s.', nnz(~tf), NMDataIOConnectivityTools.shortCellList(missing, 5)), 1, 'red*')];
                return;
            end
            if size(Yw0,2) > numel(trainKeys)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.edgeIndex', ...
                    sprintf('Vectorized weighting map contains %g extra edge column(s); extras are ignored after all training edges were matched.', size(Yw0,2)-numel(trainKeys)), 2, 'SystemCommands')];
            end
            if any(loc(:)' ~= 1:numel(loc))
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.edgeIndex', ...
                    'Vectorized weighting edge order differs from the training connectivity edge order and was reordered.', 2, 'SystemCommands')];
            end
            Yw = Yw0(:, loc);
        end

        function [Yw, messages] = reorderVectorizedWeightingByEdgeNames(Yw0, edgeNamesW, trainingNames)
            messages = NMDataIOMessageTools.emptyMessages();
            Yw = [];
            edgeNamesW = NMDataIOConnectivityTools.asCellstr(edgeNamesW);
            trainingNames = NMDataIOConnectivityTools.asCellstr(trainingNames);
            if numel(unique(edgeNamesW)) ~= numel(edgeNamesW)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeNames', ...
                    'weightingEdgeNames contains duplicate connectivity edge names.', 1, 'red*')];
                return;
            end
            [tf, loc] = ismember(trainingNames(:), edgeNamesW(:));
            if ~all(tf)
                missing = trainingNames(~tf);
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'connectivity.weighting.edgeNames', ...
                    sprintf('Vectorized weighting map is missing %g required connectivity edge name(s), e.g. %s.', nnz(~tf), NMDataIOConnectivityTools.shortCellList(missing, 5)), 1, 'red*')];
                return;
            end
            if size(Yw0,2) > numel(trainingNames)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.edgeNames', ...
                    sprintf('Vectorized weighting map contains %g extra edge name(s); extras are ignored after all training edges were matched.', size(Yw0,2)-numel(trainingNames)), 2, 'SystemCommands')];
            end
            if any(loc(:)' ~= 1:numel(loc))
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'connectivity.weighting.edgeNames', ...
                    'Vectorized weighting edge-name order differs from the training connectivity edge order and was reordered.', 2, 'SystemCommands')];
            end
            Yw = Yw0(:, loc);
        end

        function key = edgeKeyFromNodeIDs(a, b, matrixType)
            if strcmp(matrixType,'undirected')
                aa = min(double(a), double(b));
                bb = max(double(a), double(b));
                key = sprintf('%s--%s', NMDataIOConnectivityTools.nodeIDKey(aa), NMDataIOConnectivityTools.nodeIDKey(bb));
            else
                key = sprintf('%s->%s', NMDataIOConnectivityTools.nodeIDKey(a), NMDataIOConnectivityTools.nodeIDKey(b));
            end
        end

        function names = weightingNames(spec, nMaps)
            names = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.pick(spec, {'weightingNames','weightingMapNames','YwNames'}, {}));
            if isempty(names)
                names = arrayfun(@(i)sprintf('weighting_%03d', i), 1:nMaps, 'UniformOutput', false);
            end
            names = names(:)';
        end

        function v = pick(S, names, defaultValue)
            v = defaultValue;
            for i = 1:numel(names)
                if isstruct(S) && isfield(S,names{i}) && ~isempty(S.(names{i}))
                    v = S.(names{i});
                    return;
                end
            end
        end

        function v = fieldOr(S, name, defaultValue)
            if nargin < 3, defaultValue = []; end
            if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
                v = S.(name);
            else
                v = defaultValue;
            end
        end

        function c = caseCellField(S, names)
            c = NMDataIOConnectivityTools.asCellstr(NMDataIOConnectivityTools.pick(S, names, {}));
            if numel(c) == 1 && strcmp(strtrim(c{1}),'?'), c = {}; end
        end

        function c = asCellstr(v)
            if isempty(v), c = {}; return; end
            if isstring(v)
                c = cellstr(v(:));
            elseif ischar(v)
                c = cellstr(v);
            elseif iscell(v)
                c = cell(size(v));
                for i = 1:numel(v)
                    if isempty(v{i})
                        c{i} = '';
                    else
                        c{i} = NMDataIOConnectivityTools.asChar(v{i});
                    end
                end
                c = c(:);
            elseif isnumeric(v) || islogical(v)
                c = cellstr(num2str(v(:)));
            else
                c = cellstr(string(v(:)));
            end
            for i = 1:numel(c)
                c{i} = strtrim(char(c{i}));
            end
        end

        function s = asChar(v)
            if isempty(v), s = ''; return; end
            if ischar(v)
                s = v;
            elseif isstring(v)
                s = char(v(1));
            elseif isnumeric(v) || islogical(v)
                if isscalar(v), s = num2str(v); else, s = char(string(v)); end
            elseif iscell(v) && numel(v) == 1
                s = NMDataIOConnectivityTools.asChar(v{1});
            else
                s = char(string(v));
            end
            s = strtrim(s);
        end

        function v = numericVector(v)
            if isempty(v), v = []; return; end
            if ischar(v) || isstring(v) || iscell(v)
                v = str2double(NMDataIOConnectivityTools.asCellstr(v));
            end
            v = double(v(:)');
        end

        function v = resolveNamedValue(v)
            if iscell(v) && numel(v) == 1
                v0 = v{1};
                if ischar(v0) || (isstring(v0) && isscalar(v0)), v = v0; end
            end
            if ischar(v) || (isstring(v) && isscalar(v))
                name = char(v);
                if ~isempty(name) && ~strcmp(name,'?') && isvarname(name) && evalin('base', sprintf('exist(''%s'',''var'')', name))
                    v = evalin('base', name);
                end
            end
        end

        function tf = toLogical(v)
            if islogical(v), tf = v(1); return; end
            if isnumeric(v), tf = v(1) ~= 0; return; end
            s = lower(strtrim(NMDataIOConnectivityTools.asChar(v)));
            tf = ismember(s, {'true','yes','y','1','on','include','included'});
        end

        function s = yesNo(tf)
            if tf, s = 'yes'; else, s = 'no'; end
        end
    end
end

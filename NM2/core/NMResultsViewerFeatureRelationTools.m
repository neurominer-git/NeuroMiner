classdef NMResultsViewerFeatureRelationTools
% NMResultsViewerFeatureRelationTools
% -------------------------------------------------------------------------
% Canonical read-only normalization of feature-relation matrices stored by
% the NeuroMiner visualization pipeline.
%
% The authoritative relation quantity is the CV-aggregated feature-by-
% feature Pearson correlation matrix of preprocessed training-space feature
% values. Associated evidence matrices contain mean -log10(P) and mean
% -log10(FDR q) values across CV models. These matrices are emitted only for
% non-decomposed feature spaces and are invariant to the Results Viewer
% backprojection-component selection.
%
% This class performs no browser rendering. Graph and edge-community
% construction are delegated to NMResultsViewerFeatureGraphTools while the same
% normalized relation state is preserved. It validates exact stored fields,
% preserves non-estimable cells, mirrors the authoritative upper triangle of
% evidence matrices, and returns fixed-schema payloads with stable feature
% identities and scientific provenance. Bounded service views add stable
% subset, feature-level filter, ordering, pagination, and cache identity without
% changing matrix-normalization semantics. Correlation-derived hierarchical
% clustering, optional deterministic cluster extraction, and aligned transfer
% of every available correlation/evidence layer share one feature order.
% Deterministic average linkage and exact optimal leaf ordering use base-MATLAB
% utilities without a Statistics Toolbox dependency. The persisted all-modality
% early- or intermediate-fusion CombinedRelation object enters this same
% normalization/service path; modality matrices are never joined in the viewer, and persisted
% varind/native-feature keys remain graph-node identity. Explicit source-scope
% and relation-identity assertions propagate through browser and Report Builder
% requests so exports cannot silently materialize a different authoritative
% relation source. The combined normalizer consumes the exact nk_VisModelsC
% CombinedRelation schema: fusionMode, featureNames, featureVarind, native
% indices/keys, member blocks, and the writer-defined provenance descriptions.
% -------------------------------------------------------------------------

    methods (Static)
        function matrix = matrixTemplate()
            % matrixTemplate  Create the fixed-schema feature-relation payload.
            %
            % matrix = NMResultsViewerFeatureRelationTools.matrixTemplate() returns
            % one disabled scalar descriptor. Passing [] returns an empty struct
            % array with the same schema for deterministic preallocation.
            tmpl = struct( ...
                'schemaVersion',2, ...
                'relationContractVersion','C17a.1', ...
                'relationServiceContractVersion','C17b.1', ...
                'relationSourceScopeContractVersion','C17j5b.1', ...
                'relationServiceOperation','results_viewer_alpha_feature_relation', ...
                'relationServiceAvailable',false, ...
                'inlineTransferLimit',150, ...
                'matrixId','', ...
                'contextId','', ...
                'analysisIndex',0, ...
                'targetIndex',1, ...
                'resultTargetIndex',1, ...
                'classIndex',1, ...
                'modalityIndex',1, ...
                'modalityLabel','', ...
                'sourceScope','modality', ...
                'sourceScopeLabel','Modality', ...
                'relationId','', ...
                'memberContextIds',{{}}, ...
                'memberVarind',[], ...
                'memberFeatureCounts',[], ...
                'secondaryFeatureMetricsSupported',true, ...
                'featureIdSemantics','context_qualified_native_feature_index', ...
                'varind',1, ...
                'componentId','', ...
                'componentIndex',NaN, ...
                'componentLabel','', ...
                'componentApplicability','invariant', ...
                'componentSelectionAffectsContent',false, ...
                'measureId','feature_correlation_matrix', ...
                'matrixKind','feature_relation', ...
                'primaryLayerId','feature_correlation', ...
                'labels',{{}}, ...
                'featureIds',{{}}, ...
                'values',[], ...
                'validityMask',[], ...
                'diagonalMask',[], ...
                'invalidReasonCodes',{{}}, ...
                'layers',repmat(NMResultsViewerFeatureRelationTools.layerTemplate(),1,0), ...
                'availableLayerIds',{{}}, ...
                'nRows',0, ...
                'nColumns',0, ...
                'nValidPairs',0, ...
                'validPairFraction',NaN, ...
                'sourceField','', ...
                'filterSourceField','', ...
                'filterThresholdValue',NaN, ...
                'filterThresholdLabel','', ...
                'scientificQuantity','', ...
                'sourceSpaceDescription','', ...
                'aggregationDescription','', ...
                'missingValueHandling','', ...
                'evidenceInterpretation','', ...
                'provenanceId','', ...
                'availabilityCode','not_evaluated', ...
                'available',false, ...
                'inlineTransferAvailable',false, ...
                'enabled',false, ...
                'disabledReason','');
            matrix = tmpl;
        end

        function layer = layerTemplate()
            % layerTemplate  Create one normalized relation-matrix layer descriptor.
            tmpl = struct( ...
                'layerId','', ...
                'label','', ...
                'sourceField','', ...
                'scientificQuantity','', ...
                'valuePolarity','signed', ...
                'triangleSemantics','symmetric', ...
                'normalizationApplied','none', ...
                'values',[], ...
                'validityMask',[], ...
                'diagonalMask',[], ...
                'invalidReasonCodes',{{}}, ...
                'nValidPairs',0, ...
                'validPairFraction',NaN, ...
                'available',false, ...
                'disabledReason','');
            layer = tmpl;
        end

        function layer = displayLayerTemplate()
            % displayLayerTemplate  Create one bounded aligned relation-layer view.
            %
            % The display-layer contract carries the correlation, uncorrected
            % evidence, and corrected evidence values through the same feature
            % permutation. It permits exact hover comparison without recomputing or
            % independently ordering any matrix layer in the browser.
            tmpl = struct( ...
                'layerId','', ...
                'label','', ...
                'sourceField','', ...
                'scientificQuantity','', ...
                'valuePolarity','signed', ...
                'values',[], ...
                'validityMask',[], ...
                'diagonalMask',[], ...
                'invalidReasonCodes',{{}}, ...
                'available',false);
            layer = tmpl;
        end

        function [matrix, diagnostics] = buildMatrixPayload(v, ctx, classIndex, varargin)
            % buildMatrixPayload  Resolve relation availability first; normalize values only when transferable/requested.
            matrix=NMResultsViewerFeatureRelationTools.matrixTemplate(); diagnostics=repmat(NMResultsViewerFeatureRelationTools.diagnosticTemplate(),1,0);
            buildOptions=NMResultsViewerFeatureRelationTools.buildOptions(varargin{:}); matrix=NMResultsViewerFeatureRelationTools.populateIdentity(matrix,ctx,classIndex);
            nFeatures=NMResultsViewerFeatureRelationTools.contextFeatureCount(ctx); matrix.nRows=nFeatures; matrix.nColumns=nFeatures;
            matrix.sourceField='CorrMat_CV2';
            matrix.scientificQuantity='CV-aggregated feature-by-feature Pearson correlation of preprocessed training-space feature values';
            matrix.sourceSpaceDescription='Model-specific preprocessed training feature space represented by the stored VIS context';
            matrix.aggregationDescription='Arithmetic mean across CV1 models and subsequently CV2 partitions with unavailable values omitted by the legacy VIS generator';
            matrix.missingValueHandling='Non-finite or non-estimable feature pairs remain unavailable and are never converted to zero';
            matrix.evidenceInterpretation='Evidence layers are means of -log10(P) or -log10(FDR q) across CV models; they are not P or q values for the final averaged correlation';
            matrix.provenanceId=sprintf('%s:class%d:training_feature_relation',matrix.contextId,matrix.classIndex);
            % nm2-allow: nk_VisModelsC conditionally writes CorrMat_CV2 only for non-decomposed relation-capable VIS contexts.
            if ~isfield(v,'CorrMat_CV2') || isempty(v.CorrMat_CV2)
                matrix.availabilityCode='not_stored_for_context';
                matrix.disabledReason=['No CorrMat_CV2 relation matrix is stored for this VIS context. ' ...
                    'The legacy VIS generator emits feature-relation matrices only for non-decomposed feature spaces.'];
                diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('info','relation_not_stored',matrix.disabledReason,'CorrMat_CV2',matrix.contextId,'','','');
                return;
            end

            materialize=logical(buildOptions.includeFullValues)||(nFeatures>0&&nFeatures<=matrix.inlineTransferLimit);
            layerDefs=NMResultsViewerFeatureRelationTools.layerDefinitions(); layers=repmat(NMResultsViewerFeatureRelationTools.layerTemplate(),1,numel(layerDefs));
            diagnosticBlocks=cell(1,numel(layerDefs)); availableIds=cell(1,numel(layerDefs)); availableCount=0; primaryOk=false;
            for ii=1:numel(layerDefs)
                def=layerDefs(ii); layers(ii)=NMResultsViewerFeatureRelationTools.layerFromDefinition(def);
                [raw,present,readOk,readDiagnostic]=NMResultsViewerFeatureRelationTools.readStoredMatrix(v,def.sourceField,classIndex,matrix.contextId); diagnosticBlocks{ii}=readDiagnostic;
                if ~present, layers(ii).disabledReason=sprintf('Stored VIS field %s is unavailable for this context and classifier.',def.sourceField); continue; end
                if ~readOk, layers(ii).disabledReason=readDiagnostic.message; continue; end
                if nFeatures==0&&strcmp(def.layerId,'feature_correlation'), nFeatures=size(raw,1); matrix.nRows=nFeatures; matrix.nColumns=nFeatures; materialize=logical(buildOptions.includeFullValues)||nFeatures<=matrix.inlineTransferLimit; end
                % nm2-allow: persisted relation matrix must match the authoritative Feature Inspection feature axis
            if nFeatures>0&&(size(raw,1)~=nFeatures||size(raw,2)~=nFeatures)
                    msg=sprintf('%s is %d-by-%d but the feature context declares %d stable features.',def.sourceField,size(raw,1),size(raw,2),nFeatures);
                    layers(ii).disabledReason=msg; diagnosticBlocks{ii}=NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_dimension_mismatch',msg,def.sourceField,matrix.contextId,'','',''); continue;
                end
                if ~materialize
                    layers(ii).normalizationApplied='deferred_to_relation_service'; layers(ii).available=true; layers(ii).disabledReason='';
                    availableCount=availableCount+1; availableIds{availableCount}=def.layerId; if strcmp(def.layerId,'feature_correlation'),primaryOk=true;end
                    continue;
                end
                if strcmp(def.normalizer,'correlation')
                    [normalized,validMask,diagonalMask,reasons,normalizationLabel,normalizeOk,normalizeDiagnostic]=NMResultsViewerFeatureRelationTools.normalizeCorrelation(raw,def.sourceField,matrix.contextId);
                else
                    [normalized,validMask,diagonalMask,reasons,normalizationLabel,normalizeOk,normalizeDiagnostic]=NMResultsViewerFeatureRelationTools.normalizeEvidence(raw,def.sourceField,matrix.contextId);
                end
                if ~isempty(normalizeDiagnostic), diagnosticBlocks{ii}=NMResultsViewerFeatureRelationTools.appendDiagnostics(diagnosticBlocks{ii},normalizeDiagnostic); end
                if ~normalizeOk
                    if ~isempty(normalizeDiagnostic),layers(ii).disabledReason=normalizeDiagnostic(end).message;else,layers(ii).disabledReason=sprintf('%s failed relation normalization.',def.sourceField);end
                    continue;
                end
                [nValidPairs,validPairFraction]=NMResultsViewerFeatureRelationTools.validPairSummary(validMask,diagonalMask);
                layers(ii).values=NMResultsViewerFeatureRelationTools.numericMatrixRows(normalized); layers(ii).validityMask=NMResultsViewerFeatureRelationTools.logicalMatrixRows(validMask);
                layers(ii).diagonalMask=NMResultsViewerFeatureRelationTools.logicalMatrixRows(diagonalMask); layers(ii).invalidReasonCodes=NMResultsViewerFeatureRelationTools.textMatrixRows(reasons);
                layers(ii).normalizationApplied=normalizationLabel; layers(ii).nValidPairs=nValidPairs; layers(ii).validPairFraction=validPairFraction; layers(ii).available=true; layers(ii).disabledReason='';
                availableCount=availableCount+1; availableIds{availableCount}=def.layerId;
                if strcmp(def.layerId,'feature_correlation')
                    primaryOk=true; matrix.values=layers(ii).values; matrix.validityMask=layers(ii).validityMask; matrix.diagonalMask=layers(ii).diagonalMask; matrix.invalidReasonCodes=layers(ii).invalidReasonCodes;
                    matrix.nRows=size(normalized,1); matrix.nColumns=size(normalized,2); matrix.nValidPairs=nValidPairs; matrix.validPairFraction=validPairFraction;
                end
            end
            matrix.layers=layers; matrix.availableLayerIds=availableIds(1:availableCount); diagnostics=NMResultsViewerFeatureRelationTools.flattenDiagnostics(diagnosticBlocks);
            fdrIndex=find(strcmp({layers.layerId},'mean_log10_fdr_q'),1,'first'); pIndex=find(strcmp({layers.layerId},'mean_log10_p'),1,'first');
            if ~isempty(fdrIndex)&&layers(fdrIndex).available, matrix.filterSourceField=layers(fdrIndex).sourceField; matrix.filterThresholdValue=-log10(0.05); matrix.filterThresholdLabel='FDR q <= 0.05 [-log10(q) >= 1.301]';
            elseif ~isempty(pIndex)&&layers(pIndex).available, matrix.filterSourceField=layers(pIndex).sourceField; matrix.filterThresholdValue=-log10(0.05); matrix.filterThresholdLabel='P <= 0.05 [-log10(P) >= 1.301]'; end
            if ~primaryOk
                matrix.availabilityCode='stored_contract_invalid'; matrix.disabledReason=NMResultsViewerFeatureRelationTools.primaryLayerFailure(layers); return;
            end
            matrix.available=true; matrix.relationServiceAvailable=true; matrix.inlineTransferAvailable=materialize&&max(matrix.nRows,matrix.nColumns)<=matrix.inlineTransferLimit;
            if materialize
                matrix.featureIds=NMResultsViewerFeatureRelationTools.featureIds(matrix.contextId,matrix.nRows); matrix.labels=matrix.featureIds;
                matrix.enabled=true; matrix.disabledReason='';
                if buildOptions.includeFullValues, matrix.availabilityCode='available_service'; else, matrix.availabilityCode='available_inline'; end
            else
                matrix.enabled=false; matrix.availabilityCode='available_service_only';
                matrix.disabledReason=sprintf('The authoritative relation matrix is %d-by-%d. Use the feature-relation service to request a bounded subset or page; full matrix values are intentionally omitted from the initial payload.',matrix.nRows,matrix.nColumns);
            end
        end

        function [matrix, diagnostics] = buildCombinedMatrixPayload(relation, ctx, classIndex, buildOptions)
            % buildCombinedMatrixPayload  Normalize the fixed persisted fusion CombinedRelation contract.
            matrix=NMResultsViewerFeatureRelationTools.matrixTemplate();
            diagnostics=repmat(NMResultsViewerFeatureRelationTools.diagnosticTemplate(),1,0);
            matrix=NMResultsViewerFeatureRelationTools.populateIdentity(matrix,ctx,classIndex);
            matrix.sourceScope='combined';
            matrix.sourceScopeLabel='Combined modalities';
            matrix.modalityIndex=0;
            matrix.varind=0;
            matrix.secondaryFeatureMetricsSupported=true;
            matrix.featureIdSemantics='persisted_varind_native_feature_key';
            matrix.componentApplicability='invariant';
            matrix.componentSelectionAffectsContent=false;
            try
                matrix.relationId=relation.relationId;
                matrix.memberVarind=double(relation.memberVarind(:)');
                matrix.memberFeatureCounts=double(relation.memberFeatureCounts(:)');
                matrix.memberContextIds=ctx.memberContextIds;
                fusionMode=relation.fusionMode;
                if isempty(matrix.relationId) || ~ismember(fusionMode,{'early','intermediate'})
                    error('NMResultsViewerFeatureRelationTools:combinedRelationIdentityInvalid', ...
                        'CombinedRelation must provide a stable relationId and declare early or intermediate fusion.');
                end
                matrix.matrixId=sprintf('%s_matrix_%s',matrix.contextId,matrix.relationId);
                if ~relation.available
                    matrix.availabilityCode=relation.availabilityCode;
                    matrix.disabledReason=relation.disabledReason;
                    diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('info','combined_relation_unavailable', ...
                        matrix.disabledReason,'CombinedRelation',matrix.contextId,'buildCombinedMatrixPayload','','');
                    return;
                end

                featureKeys=relation.featureKeys(:);
                featureNames=relation.featureNames(:);
                featureMembership=double(relation.featureVarind(:));
                featureNativeIndex=double(relation.featureNativeIndex(:));
                n=numel(featureKeys);
                % nm2-allow: persisted CombinedRelation identity vectors share one scientific feature axis and featureKeys must be unique.
                if n<1 || numel(unique(featureKeys))~=n || numel(featureNames)~=n || ...
                        numel(featureMembership)~=n || numel(featureNativeIndex)~=n % nm2-allow: nk_VisModelsC writes parallel CombinedRelation feature identity axes.
                    error('NMResultsViewerFeatureRelationTools:combinedFeatureIdentityInvalid', ...
                        'CombinedRelation feature identity vectors must be non-empty, unique, and have equal lengths.');
                end
                % nm2-allow: memberVarind/memberFeatureCounts define the complete persisted CombinedRelation native feature blocks.
                if isempty(matrix.memberVarind) || isempty(matrix.memberFeatureCounts) || ...
                        numel(matrix.memberVarind)~=numel(matrix.memberFeatureCounts) || ... % nm2-allow: nk_VisModelsC memberVarind/memberFeatureCounts are parallel scientific member axes.
                        any(matrix.memberVarind<1) || any(matrix.memberVarind~=round(matrix.memberVarind)) || ...
                        numel(unique(matrix.memberVarind))~=numel(matrix.memberVarind) || ... % nm2-allow: CombinedRelation memberVarind uniquely identifies each persisted member block.
                        any(matrix.memberFeatureCounts<1) || ...
                        any(matrix.memberFeatureCounts~=round(matrix.memberFeatureCounts)) || ...
                        sum(matrix.memberFeatureCounts)~=n
                    error('NMResultsViewerFeatureRelationTools:combinedMemberBlocksInvalid', ...
                        'CombinedRelation memberVarind/memberFeatureCounts do not define unique positive native-feature blocks for the complete feature axis.');
                end
                expectedVarind=[];
                expectedNativeIndex=[];
                for memberIndex=1:numel(matrix.memberVarind)
                    count=matrix.memberFeatureCounts(memberIndex);
                    expectedVarind=[expectedVarind repmat(matrix.memberVarind(memberIndex),1,count)]; %#ok<AGROW>
                    expectedNativeIndex=[expectedNativeIndex 1:count]; %#ok<AGROW>
                end
                if ~isequal(featureMembership(:)',expectedVarind) || ~isequal(featureNativeIndex(:)',expectedNativeIndex)
                    error('NMResultsViewerFeatureRelationTools:combinedFeatureAxisInvalid', ...
                        'CombinedRelation featureVarind/featureNativeIndex do not match the persisted member block order.');
                end
                featureOffsets=double(relation.featureOffsets(:)');
                if ~isequal(featureOffsets,[0 cumsum(matrix.memberFeatureCounts)])
                    error('NMResultsViewerFeatureRelationTools:combinedFeatureOffsetsInvalid', ...
                        'CombinedRelation featureOffsets do not match memberFeatureCounts.');
                end
                displayNames=ctx.relationFeatureLabels(:);
                if numel(displayNames)~=n
                    error('NMResultsViewerFeatureRelationTools:combinedDisplayAxisInvalid', ...
                        'Combined relation display labels do not match the persisted feature axis.');
                end

                adapter=struct();
                adapter.params=struct('features',{displayNames},'nfeats',n,'varind',0,'visflag',0);
                adapter.CorrMat_CV2=relation.CorrMat_CV2;
                adapter.CorrMat_CV2_STD=relation.CorrMat_CV2_STD;
                adapter.CorrMat_CV2_p_uncorr=relation.CorrMat_CV2_p_uncorr;
                adapter.CorrMat_CV2_p_uncorr_STD=relation.CorrMat_CV2_p_uncorr_STD;
                adapter.CorrMat_CV2_p_fdr=relation.CorrMat_CV2_p_fdr;
                adapter.CorrMat_CV2_p_fdr_STD=relation.CorrMat_CV2_p_fdr_STD;
                ctx2=ctx;
                ctx2.nFeatures=n;
                [matrix,diagnostics]=NMResultsViewerFeatureRelationTools.buildMatrixPayload(adapter,ctx2,classIndex,buildOptions);
                matrix.sourceScope='combined';
                matrix.sourceScopeLabel='Combined modalities';
                matrix.relationId=relation.relationId;
                matrix.memberContextIds=ctx.memberContextIds;
                matrix.memberVarind=double(relation.memberVarind(:)');
                matrix.memberFeatureCounts=double(relation.memberFeatureCounts(:)');
                matrix.secondaryFeatureMetricsSupported=true;
                matrix.featureIdSemantics='persisted_varind_native_feature_key';
                matrix.modalityIndex=0;
                matrix.varind=0;
                matrix.modalityLabel=ctx.modalityLabel;
                matrix.matrixId=sprintf('%s_matrix_%s',matrix.contextId,matrix.relationId);
                matrix.featureIds=featureKeys;
                matrix.labels=displayNames;
                matrix.sourceField='CombinedRelation.CorrMat_CV2';
                matrix.filterSourceField=strrep(matrix.filterSourceField,'CorrMat_CV2','CombinedRelation.CorrMat_CV2');
                for ii=1:numel(matrix.layers)
                    matrix.layers(ii).sourceField=strrep(matrix.layers(ii).sourceField,'CorrMat_CV2','CombinedRelation.CorrMat_CV2');
                end
                if strcmp(fusionMode,'intermediate')
                    matrix.scientificQuantity='CV-aggregated all-modality feature-by-feature Pearson correlation after modality-specific intermediate-fusion preprocessing, mapped to native feature identities';
                else
                    matrix.scientificQuantity='CV-aggregated all-modality feature-by-feature Pearson correlation in the restored early-fusion native feature space';
                end
                matrix.sourceSpaceDescription=relation.sourceSpaceDescription;
                matrix.aggregationDescription=relation.aggregationDescription;
                matrix.missingValueHandling=relation.missingValueHandling;
                matrix.evidenceInterpretation=relation.evidenceInterpretation;
                matrix.provenanceId=sprintf('%s:class%d:%s',matrix.contextId,matrix.classIndex,matrix.relationId);
            % nm2-allow: persisted CombinedRelation scientific-contract failures are converted into an explicit Results Viewer diagnostic.
            catch ME
                matrix=NMResultsViewerFeatureRelationTools.matrixTemplate();
                matrix=NMResultsViewerFeatureRelationTools.populateIdentity(matrix,ctx,classIndex);
                matrix.sourceScope='combined';
                matrix.sourceScopeLabel='Combined modalities';
                matrix.secondaryFeatureMetricsSupported=true;
                matrix.featureIdSemantics='persisted_varind_native_feature_key';
                matrix.modalityIndex=0;
                matrix.varind=0;
                matrix.availabilityCode='combined_relation_contract_invalid';
                matrix.disabledReason=sprintf('%s: %s',ME.identifier,ME.message);
                diagnostics=NMResultsViewerFeatureRelationTools.diagnosticFromException('buildCombinedMatrixPayload',ME,matrix.contextId);
            end
        end

        function [matrix, present, ok, diagnostic] = readStoredMatrix(v, fieldName, classIndex, contextId)
            % readStoredMatrix  Read one exact classifier-indexed persisted VIS relation matrix.
            %
            % nk_VisModelsC writes CorrMat_CV2 and its evidence companions as
            % classifier-indexed cell arrays. Direct numeric containers are not a
            % persisted schema variant. Matrix shape/type checks below validate the
            % scientific relation payload after that fixed container has been read.
            matrix = [];
            present = true;
            ok = false;
            diagnostic = repmat(NMResultsViewerFeatureRelationTools.diagnosticTemplate(),1,0);
            raw = v.(fieldName){classIndex};
            if isempty(raw)
                present = false;
                diagnostic = NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_class_missing', ...
                    sprintf('%s does not contain classifier entry %d.', fieldName, classIndex), ...
                    fieldName,contextId,'','','');
                return;
            end
            % nm2-allow: persisted nk_VisModelsC relation field must be numeric scientific matrix material
            if ~(isnumeric(raw) || islogical(raw))
                diagnostic = NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_type_invalid', ...
                    sprintf('%s must contain a numeric or logical square matrix.', fieldName), ...
                    fieldName,contextId,'','','');
                return;
            end
            % nm2-allow: persisted relation scientific matrix must be square on one feature axis
            if ndims(raw) ~= 2 || size(raw,1) ~= size(raw,2)
                diagnostic = NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_shape_invalid', ...
                    sprintf(['%s dimensions %s do not define one square feature-relation matrix. ' ...
                    'Component-resolved matrix stacks are not part of the authoritative VIS contract.'], ...
                    fieldName, mat2str(size(raw))), fieldName,contextId,'','','');
                return;
            end
            if ~isreal(raw)
                diagnostic=NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_complex_invalid',sprintf('%s contains complex values and requires an explicit upstream real-valued relation contract.',fieldName),fieldName,contextId,'readStoredMatrix','','');
                return;
            end
            matrix = raw;
            ok = true;
        end

        function request = relationViewRequestTemplate()
            % relationViewRequestTemplate  Create the normalized bounded relation-view request schema.
            %
            % Syntax:
            %   request = NMResultsViewerFeatureRelationTools.relationViewRequestTemplate()
            %
            % Outputs:
            %   request  Scalar or empty struct containing matrix identity, optional
            %            source-scope/relation-identity assertions, physical layer
            %            selection, stable feature subset, secondary feature filter,
            %            ordering, feature clustering, graph pruning, relation-pattern,
            %            and pagination fields.
            %
            % Scientific contract:
            %   The header Feature source selects the authoritative relation source.
            %   matrixId, sourceScope and relationId are internal identity assertions
            %   used by browser/report replay and never expose a second source choice
            %   or reconstruct another matrix. primaryLayerId
            %   selects the physical relation layer used both for graph-edge pruning
            %   and for the final relation-pattern edge universe. Feature indices are
            %   stable source indices before ordering or pagination. Secondary
            %   thresholds are feature-level filters applied before graph construction.
            %
            % Invariants and mutability:
            %   Returns a new fixed-schema value and does not inspect or mutate NM/VIS state.
            %
            % Errors and diagnostics:
            %   None. Validation occurs in normalizeRelationViewRequest.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'schemaVersion',1, ...
                'relationServiceContractVersion','C17b.1', ...
                'relationReportScopeContractVersion','C17j5a.1', ...
                'matrixId','', ...
                'sourceScope','', ...
                'relationId','', ...
                'primaryLayerId','feature_correlation', ...
                'featureIndexExpression','', ...
                'featureIndices',[], ...
                'resolvedFeatureIndices',[], ...
                'alternativeLabels',{{}}, ...
                'alternativeLabelsExpression','', ...
                'alternativeLabelSourceId','', ...
                'resolvedAlternativeLabels',{{}}, ...
                'secondaryFeatureMetricId','', ...
                'secondaryThresholdMode','', ...
                'secondaryThresholdLow',NaN, ...
                'secondaryThresholdHigh',NaN, ...
                'secondaryThresholdValue',NaN, ...
                'orderingMode','original', ...
                'orderingSource','primary_relation_summary', ...
                'clusteringContractVersion','C17d2.1', ...
                'clusteringMode','none', ...
                'clusterExtractionMode','none', ...
                'clusterCount',4, ...
                'clusterCutHeight',0.5, ...
                'graphContractVersion','C17g.1', ...
                'edgeSelectionMode','legacy_topk_union', ...
                'graphKPerNode',5, ...
                'graphMaxGlobal',250, ...
                'graphTargetDensity',0.10, ...
                'graphAbsoluteThreshold',0.30, ...
                'relationPatternEnabled',true, ...
                'relationPatternMethod','hierarchical_link_communities', ...
                'relationPatternCutMode','max_partition_density', ...
                'relationPatternSimilarityThreshold',0.5, ...
                'relationPatternMinEdges',2, ...
                'showAllRows',false, ...
                'pageSize',150, ...
                'currentPage',1);
            request = tmpl;
        end

        function metric = secondaryFeatureMetricTemplate()
            % secondaryFeatureMetricTemplate  Create one feature-level filter metric descriptor.
            tmpl = struct( ...
                'metricId','', ...
                'label','', ...
                'sourceField','', ...
                'valuePolarity','signed', ...
                'values',[], ...
                'validityMask',[], ...
                'defaultThresholdMode','none', ...
                'defaultThresholdLow',NaN, ...
                'defaultThresholdHigh',NaN, ...
                'defaultThresholdValue',NaN, ...
                'defaultThresholdLabel','No threshold', ...
                'available',false, ...
                'disabledReason','');
            metric = tmpl;
        end

        function summary = clusterSummaryTemplate()
            % clusterSummaryTemplate  Create one ordered feature-cluster summary row.
            %
            % The summary is derived from the canonical hierarchical feature
            % assignments and is intended for browser/report explanation. It does
            % not redefine pairwise relation clusters or graph communities.
            tmpl = struct( ...
                'clusterId',0, ...
                'size',0, ...
                'singleton',false, ...
                'featureIndices',[], ...
                'featureIds',{{}}, ...
                'labels',{{}});
            summary = tmpl;
        end

        function view = relationViewTemplate()
            % relationViewTemplate  Create the fixed-schema matrix/graph relation-view payload.
            %
            % Syntax:
            %   view = NMResultsViewerFeatureRelationTools.relationViewTemplate()
            %
            % Outputs:
            %   view  Scalar or empty struct containing physical matrix layers, stable feature
            %         subsets, ordering/clustering state, the canonical pruned graph, relation-
            %         pattern slices, pagination, identities, availability, and diagnostics state.
            %
            % Scientific contract:
            %   graph and relationPatternGraph describe the same final pruned edge universe.
            %   displayRelationClusterAssignments and displayGraphEdgeMask are bounded projections
            %   onto displayFeatureIndices; they never redefine the backend graph or patterns.
            %
            % Invariants and mutability:
            %   Stable source-feature indices precede filtering, ordering, and pagination. The
            %   returned value is newly allocated and contains no caller-owned mutable handles.
            %
            % Errors and diagnostics:
            %   None. Builders populate availabilityCode, disabledReason, and diagnostics.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'schemaVersion',1, ...
                'relationServiceContractVersion','C17b.1', ...
                'relationSourceScopeContractVersion','C17j5b.1', ...
                'viewId','', ...
                'matrixId','', ...
                'contextId','', ...
                'analysisIndex',0, ...
                'targetIndex',1, ...
                'resultTargetIndex',1, ...
                'classIndex',1, ...
                'modalityIndex',1, ...
                'modalityLabel','', ...
                'sourceScope','modality', ...
                'sourceScopeLabel','Modality', ...
                'relationId','', ...
                'memberContextIds',{{}}, ...
                'memberVarind',[], ...
                'memberFeatureCounts',[], ...
                'secondaryFeatureMetricsSupported',true, ...
                'featureIdSemantics','context_qualified_native_feature_index', ...
                'componentApplicability','invariant', ...
                'componentSelectionAffectsContent',false, ...
                'primaryLayerId','', ...
                'primaryLayerLabel','', ...
                'primarySourceField','', ...
                'primaryValuePolarity','signed', ...
                'featureIndexSemantics','stable_source_indices_before_filter_order_and_page', ...
                'allFeatureCount',0, ...
                'requestedFeatureIndices',[], ...
                'selectedFeatureIndices',[], ...
                'excludedFeatureIndices',[], ...
                'orderedFeatureIndices',[], ...
                'displayFeatureIndices',[], ...
                'featureIds',{{}}, ...
                'originalLabels',{{}}, ...
                'displayLabels',{{}}, ...
                'alternativeLabelsApplied',false, ...
                'secondaryFeatureMetricId','', ...
                'secondaryFeatureMetricLabel','', ...
                'secondaryFeatureMetricSourceField','', ...
                'secondaryThresholdMode','none', ...
                'secondaryThresholdLow',NaN, ...
                'secondaryThresholdHigh',NaN, ...
                'secondaryThresholdValue',NaN, ...
                'secondaryFeatureValues',[], ...
                'nodeAdmissibilityMask',[], ...
                'pairwiseAdmissibilityMask',[], ...
                'orderingMode','original', ...
                'orderingSource','primary_relation_summary', ...
                'orderingScores',[], ...
                'effectiveOrderingMode','original', ...
                'effectiveOrderingSource','primary_relation_summary', ...
                'clusteringContractVersion','C17d2.1', ...
                'clusteringRequested',false, ...
                'clusteringMode','none', ...
                'clusteringLabel','No clustering', ...
                'clusteringDistanceDefinition','', ...
                'clusteringSourceLayerId','feature_correlation', ...
                'clusteringSourceField','CorrMat_CV2', ...
                'clusteringLinkageMethod','average', ...
                'clusteringLeafOrderingMethod','exact_optimal_leaf_order', ...
                'clusteringImplementation','base_matlab', ...
                'clusteringToolboxIndependent',true, ...
                'clusteringTieBreak','stable_source_index_orientation', ...
                'clusteringApplied',false, ...
                'clusteringAvailable',false, ...
                'clusteringDisabledReason','', ...
                'clusteringFeatureCount',0, ...
                'clusteringValidPairFraction',NaN, ...
                'clusteringMaxFeatures',500, ...
                'clusterExtractionMode','none', ...
                'clusterExtractionApplied',false, ...
                'clusterExtractionDisabledReason','', ...
                'clusterCountRequested',NaN, ...
                'clusterCutHeight',NaN, ...
                'clusterCountResolved',0, ...
                'clusterSizes',[], ...
                'singletonClusterCount',0, ...
                'clusterSummaries',repmat(NMResultsViewerFeatureRelationTools.clusterSummaryTemplate(),1,0), ...
                'orderedClusterAssignments',[], ...
                'displayClusterAssignments',[], ...
                'clusterBoundaryPositions',[], ...
                'linkageMatrix',[], ...
                'graph',NMResultsViewerFeatureGraphTools.graphTemplate(), ...
                'relationPatternGraph',NMResultsViewerFeatureGraphTools.graphTemplate(), ...
                'displayRelationClusterAssignments',[], ...
                'displayGraphEdgeMask',[], ...
                'displayPartialRelationClusterIds',[], ...
                'clusteringStateIdentity','', ...
                'clusteringCacheIdentity','', ...
                'showAllRows',false, ...
                'pageSize',150, ...
                'requestedPage',1, ...
                'currentPage',1, ...
                'pageCount',0, ...
                'pageAdjusted',false, ...
                'pageAdjustmentReason','', ...
                'subsetFeatureCount',0, ...
                'filteredFeatureCount',0, ...
                'displayedFeatureCount',0, ...
                'values',[], ...
                'validityMask',[], ...
                'diagonalMask',[], ...
                'invalidReasonCodes',{{}}, ...
                'displayLayers',repmat(NMResultsViewerFeatureRelationTools.displayLayerTemplate(),1,0), ...
                'nValidPairs',0, ...
                'validPairFraction',NaN, ...
                'baseRelationIdentity','', ...
                'scientificStateIdentity','', ...
                'presentationStateIdentity','', ...
                'scientificCacheIdentity','', ...
                'viewCacheIdentity','', ...
                'availabilityCode','not_evaluated', ...
                'available',false, ...
                'enabled',false, ...
                'disabledReason','');
            view = tmpl;
        end

        function descriptor = matrixServiceDescriptor(matrix)
            % matrixServiceDescriptor  Project the fixed relation-matrix schema into a lightweight selector.
            descriptor = struct('matrixId',matrix.matrixId,'contextId',matrix.contextId, ...
                'analysisIndex',matrix.analysisIndex,'targetIndex',matrix.targetIndex, ...
                'resultTargetIndex',matrix.resultTargetIndex,'classIndex',matrix.classIndex, ...
                'modalityIndex',matrix.modalityIndex,'modalityLabel',matrix.modalityLabel, ...
                'sourceScope',matrix.sourceScope,'sourceScopeLabel',matrix.sourceScopeLabel, ...
                'relationId',matrix.relationId,'memberContextIds',{matrix.memberContextIds}, ...
                'memberVarind',matrix.memberVarind,'memberFeatureCounts',matrix.memberFeatureCounts, ...
                'secondaryFeatureMetricsSupported',logical(matrix.secondaryFeatureMetricsSupported), ...
                'featureIdSemantics',matrix.featureIdSemantics, ...
                'componentApplicability',matrix.componentApplicability,'nFeatures',matrix.nRows, ...
                'availableLayerIds',{matrix.availableLayerIds}, ...
                'relationServiceContractVersion',matrix.relationServiceContractVersion, ...
                'relationSourceScopeContractVersion',matrix.relationSourceScopeContractVersion, ...
                'relationServiceOperation',matrix.relationServiceOperation, ...
                'serviceAvailable',logical(matrix.relationServiceAvailable), ...
                'available',logical(matrix.available),'disabledReason',matrix.disabledReason);
        end

        function [view, diagnostics] = buildRelationView(matrix, request, secondaryMetric)
            % buildRelationView  Build one bounded matrix/graph view from an authoritative relation payload.
            %
            % Syntax:
            %   [view,diagnostics] = NMResultsViewerFeatureRelationTools.buildRelationView( ...
            %       matrix,request,secondaryMetric)
            %
            % Inputs:
            %   matrix           Full normalized feature-relation matrix contract.
            %   request          Partial or normalized relation-view request.
            %   secondaryMetric Optional feature-level metric descriptor used only when
            %                   request.secondaryFeatureMetricId is non-empty.
            %
            % Outputs:
            %   view         Fixed-schema bounded view containing filtered stable features,
            %                selected layer values, ordering/pagination, canonical graph,
            %                relation-pattern projection, and explicit availability state.
            %   diagnostics  Structured diagnostics preserving source, identifier/message,
            %                context, and stack frames.
            %
            % Scientific contract:
            %   The method first resolves the stable feature subset and optional secondary
            %   feature-level filter. It then constructs one canonical graph from the selected
            %   primary relation layer. Relation patterns are link communities of that exact
            %   final pruned graph and are not derived from a second correlation-only graph.
            %   The same pattern graph is projected onto the matrix page, guaranteeing that
            %   every selectable pattern contains retained graph edges and participating nodes.
            %   Feature clustering affects ordering only and remains distinct from edge-based
            %   relation patterns.
            %
            % Invariants and mutability:
            %   Stable source feature indices determine identity; display positions never do.
            %   The input matrix, request, secondary metric, and stored VIS results are read-only.
            %   Pagination changes presentation only and does not alter the graph edge universe.
            %
            % Errors and diagnostics:
            %   Invalid requests, unavailable layers/metrics, dimension mismatches, and graph or
            %   clustering failures produce explicit availability codes and diagnostics. No
            %   alternate source or relation layer is substituted.
            %
            % Side effects:
            %   None.
            if isempty(request), request=struct(); end
            if isempty(secondaryMetric)
                secondaryMetric=NMResultsViewerFeatureRelationTools.secondaryFeatureMetricTemplate();
            end
            view = NMResultsViewerFeatureRelationTools.relationViewTemplate();
            diagnostics = repmat(NMResultsViewerFeatureRelationTools.diagnosticTemplate(),1,0);
            view = NMResultsViewerFeatureRelationTools.populateViewIdentity(view,matrix);
            if ~matrix.available
                view.availabilityCode='base_relation_unavailable';
                view.disabledReason=matrix.disabledReason;
                return;
            end
            try
                normalizedRequest = NMResultsViewerFeatureRelationTools.normalizeRelationViewRequest(request,matrix.nRows);
            % nm2-allow: public relation request failures become explicit Results Viewer diagnostics
            catch ME
                view.availabilityCode='request_invalid';
                view.disabledReason=sprintf('%s: %s',ME.identifier,ME.message);
                diagnostics=NMResultsViewerFeatureRelationTools.diagnosticFromException('relation_view_request',ME,matrix.contextId);
                return;
            end
            view.primaryLayerId=normalizedRequest.primaryLayerId;
            layerIndex=find(strcmp({matrix.layers.layerId},normalizedRequest.primaryLayerId),1,'first');
            if isempty(layerIndex) || ~matrix.layers(layerIndex).available
                view.availabilityCode='primary_layer_unavailable';
                view.disabledReason=sprintf('Relation layer "%s" is unavailable for matrix %s.', ...
                    normalizedRequest.primaryLayerId,matrix.matrixId);
                diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_layer_unavailable', ...
                    view.disabledReason,'',matrix.contextId,'buildRelationView','','');
                return;
            end
            layer=matrix.layers(layerIndex);
            fullValues=NMResultsViewerFeatureRelationTools.matrixFromRows(layer.values);
            fullValidity=NMResultsViewerFeatureRelationTools.logicalMatrixFromRows(layer.validityMask);
            fullDiagonal=NMResultsViewerFeatureRelationTools.logicalMatrixFromRows(layer.diagonalMask);
            fullReasons=NMResultsViewerFeatureRelationTools.textMatrixFromRows(layer.invalidReasonCodes);
            n=size(fullValues,1);
            % nm2-allow: materialized H12 row-cell matrix must match its canonical square feature axis
            if n ~= matrix.nRows || size(fullValues,2) ~= n
                view.availabilityCode='base_values_not_materialized';
                view.disabledReason=['The requested relation service requires the full normalized matrix values. ' ...
                    'The supplied descriptor contains only initial-payload metadata.'];
                diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('error','relation_values_missing', ...
                    view.disabledReason,layer.sourceField,matrix.contextId,'buildRelationView','','');
                return;
            end

            view.primaryLayerLabel=layer.label;
            view.primarySourceField=layer.sourceField;
            view.primaryValuePolarity=layer.valuePolarity;
            view.allFeatureCount=n;
            view.requestedFeatureIndices=normalizedRequest.resolvedFeatureIndices;
            if isempty(view.requestedFeatureIndices), view.requestedFeatureIndices=1:n; end
            view.subsetFeatureCount=numel(view.requestedFeatureIndices);
            originalLabels=NMResultsViewerFeatureRelationTools.normalizedLabelVector(matrix.labels,n,'Original feature labels');
            displayLabels=originalLabels;
            if ~isempty(normalizedRequest.resolvedAlternativeLabels)
                displayLabels=normalizedRequest.resolvedAlternativeLabels;
                view.alternativeLabelsApplied=true;
            end

            fullNodeMask=false(n,1);
            fullNodeMask(view.requestedFeatureIndices)=true;
            secondaryValues=nan(n,1);
            if ~isempty(normalizedRequest.secondaryFeatureMetricId)
                if isempty(secondaryMetric.metricId) || ...
                        ~strcmp(secondaryMetric.metricId,normalizedRequest.secondaryFeatureMetricId) || ...
                        ~secondaryMetric.available
                    view.availabilityCode='secondary_metric_unavailable';
                    view.disabledReason=sprintf('Secondary feature metric "%s" is unavailable for this relation context.', ...
                        normalizedRequest.secondaryFeatureMetricId);
                    diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('warning','secondary_metric_unavailable', ...
                        view.disabledReason,'',matrix.contextId,'buildRelationView','','');
                    return;
                end
                secondaryValues=double(secondaryMetric.values(:));
                if numel(secondaryValues) ~= n
                    view.availabilityCode='secondary_metric_dimension_mismatch';
                    view.disabledReason=sprintf('Secondary feature metric %s contains %d values but the relation context contains %d features.', ...
                        secondaryMetric.metricId,numel(secondaryValues),n);
                    diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('error','secondary_metric_dimension_mismatch', ...
                        view.disabledReason,secondaryMetric.sourceField,matrix.contextId,'buildRelationView','','');
                    return;
                end
                metricSpec=struct( ...
                    'valuePolarity',secondaryMetric.valuePolarity, ...
                    'thresholdMode',normalizedRequest.secondaryThresholdMode, ...
                    'thresholdLow',normalizedRequest.secondaryThresholdLow, ...
                    'thresholdHigh',normalizedRequest.secondaryThresholdHigh, ...
                    'thresholdValue',normalizedRequest.secondaryThresholdValue);
                metricContract=NMResultsViewerDisplaySemanticsTools.resolveContract( ...
                    secondaryValues,metricSpec,struct('DisplayRangeMode','full_data_range'), ...
                    struct('contextId',matrix.contextId,'measureId',secondaryMetric.metricId, ...
                        'pathway','feature_relation_node_filter'));
                metricMask=NMResultsViewerDisplaySemanticsTools.eligibilityMask( ...
                    secondaryValues,metricContract,true(size(secondaryValues)));
                fullNodeMask=fullNodeMask & metricMask;
                view.secondaryFeatureMetricId=secondaryMetric.metricId;
                view.secondaryFeatureMetricLabel=secondaryMetric.label;
                view.secondaryFeatureMetricSourceField=secondaryMetric.sourceField;
            end
            view.secondaryThresholdMode=normalizedRequest.secondaryThresholdMode;
            view.secondaryThresholdLow=normalizedRequest.secondaryThresholdLow;
            view.secondaryThresholdHigh=normalizedRequest.secondaryThresholdHigh;
            view.secondaryThresholdValue=normalizedRequest.secondaryThresholdValue;
            view.nodeAdmissibilityMask=fullNodeMask(:)';

            selected=view.requestedFeatureIndices(ismember(view.requestedFeatureIndices,find(fullNodeMask)));
            view.selectedFeatureIndices=selected;
            view.excludedFeatureIndices=setdiff(view.requestedFeatureIndices,selected,'stable');
            view.filteredFeatureCount=numel(selected);
            view.orderingMode=normalizedRequest.orderingMode;
            view.orderingSource=normalizedRequest.orderingSource;
            view.effectiveOrderingMode=normalizedRequest.orderingMode;
            view.effectiveOrderingSource=normalizedRequest.orderingSource;
            view.clusteringRequested=~strcmp(normalizedRequest.clusteringMode,'none');
            view.clusteringMode=normalizedRequest.clusteringMode;
            view.clusteringLabel=NMResultsViewerFeatureRelationTools.clusteringModeLabel(normalizedRequest.clusteringMode);
            view.clusteringDistanceDefinition=NMResultsViewerFeatureRelationTools.clusteringDistanceDefinition(normalizedRequest.clusteringMode);
            view.clusterExtractionMode=normalizedRequest.clusterExtractionMode;
            view.clusterCountRequested=normalizedRequest.clusterCount;
            view.clusterCutHeight=normalizedRequest.clusterCutHeight;
            view.clusteringFeatureCount=numel(selected);
            view.showAllRows=normalizedRequest.showAllRows;
            view.pageSize=normalizedRequest.pageSize;
            view.requestedPage=normalizedRequest.currentPage;
            if isempty(selected)
                view.available=true;
                view.availabilityCode='empty_after_filter';
                view.disabledReason='No features remain after applying the requested stable subset and secondary feature-metric filter.';
                view=NMResultsViewerFeatureRelationTools.assignViewIdentities(view,normalizedRequest,displayLabels);
                return;
            end

            graphRequest=NMResultsViewerFeatureGraphTools.graphRequestTemplate();
            graphRequest.sourceLayerId=normalizedRequest.primaryLayerId;
            graphRequest.edgeSelectionMode=normalizedRequest.edgeSelectionMode;
            graphRequest.kPerNode=normalizedRequest.graphKPerNode;
            graphRequest.maxGlobal=normalizedRequest.graphMaxGlobal;
            graphRequest.targetDensity=normalizedRequest.graphTargetDensity;
            graphRequest.absoluteThreshold=normalizedRequest.graphAbsoluteThreshold;
            graphRequest.relationPatternEnabled=normalizedRequest.relationPatternEnabled;
            graphRequest.relationPatternMethod=normalizedRequest.relationPatternMethod;
            graphRequest.relationPatternCutMode=normalizedRequest.relationPatternCutMode;
            graphRequest.relationPatternSimilarityThreshold=normalizedRequest.relationPatternSimilarityThreshold;
            graphRequest.relationPatternMinEdges=normalizedRequest.relationPatternMinEdges;
            [view.graph,graphDiagnostics]=NMResultsViewerFeatureGraphTools.buildGraphContract(matrix,selected,graphRequest);
            diagnostics=NMResultsViewerFeatureRelationTools.appendDiagnostics(diagnostics,graphDiagnostics);

            % Relation patterns are edge communities of the final pruned graph.
            % They must therefore use exactly the same retained edge universe as
            % the graph displayed for the selected primary relation layer. Keeping
            % a second correlation-derived pattern graph would expose selectable
            % patterns whose edges are absent from the current graph.
            view.relationPatternGraph=view.graph;

            ordered=[];
            orderScores=[];
            orderedAssignments=zeros(1,0);
            if view.clusteringRequested
                [clusterResult,clusterDiagnostics]=NMResultsViewerFeatureRelationTools.clusterFeatureIndices( ...
                    matrix,selected,normalizedRequest);
                diagnostics=NMResultsViewerFeatureRelationTools.appendDiagnostics(diagnostics,clusterDiagnostics);
                view.clusteringAvailable=clusterResult.available;
                view.clusteringApplied=clusterResult.applied;
                view.clusteringDisabledReason=clusterResult.disabledReason;
                view.clusteringValidPairFraction=clusterResult.validPairFraction;
                view.clusterCountResolved=clusterResult.clusterCount;
                view.clusterSizes=clusterResult.clusterSizes;
                view.singletonClusterCount=clusterResult.singletonClusterCount;
                view.clusterExtractionApplied=clusterResult.extractionApplied;
                view.clusterExtractionDisabledReason=clusterResult.extractionDisabledReason;
                view.linkageMatrix=clusterResult.linkageMatrix;
                if clusterResult.applied
                    ordered=clusterResult.orderedFeatureIndices;
                    orderedAssignments=clusterResult.orderedClusterAssignments;
                    view.effectiveOrderingMode='hierarchical_cluster';
                    view.effectiveOrderingSource='feature_correlation';
                end
            end
            if isempty(ordered)
                [ordered,orderScores]=NMResultsViewerFeatureRelationTools.orderFeatureIndices( ...
                    fullValues,fullValidity,selected,secondaryValues,normalizedRequest);
            end
            view.orderedFeatureIndices=ordered;
            view.orderingScores=orderScores(:)';
            view.orderedClusterAssignments=orderedAssignments(:)';
            if ~isempty(orderedAssignments)
                view.clusterSummaries=NMResultsViewerFeatureRelationTools.buildClusterSummaries( ...
                    matrix,displayLabels,ordered,orderedAssignments);
            end
            if normalizedRequest.showAllRows
                view.pageSize=max(1,numel(ordered));
                view.pageCount=1;
                view.currentPage=1;
                view.requestedPage=1;
            else
                view.pageCount=max(1,ceil(numel(ordered)/view.pageSize));
            view.currentPage=min(view.requestedPage,view.pageCount);
                if view.currentPage ~= view.requestedPage
                    view.pageAdjusted=true;
                    view.pageAdjustmentReason=sprintf('Requested page %d exceeds the available %d page(s); page %d is returned.', ...
                        view.requestedPage,view.pageCount,view.currentPage);
                    diagnostics=NMResultsViewerFeatureRelationTools.appendDiagnostics(diagnostics, ...
                        NMResultsViewerFeatureRelationTools.diagnostic('info','relation_page_adjusted', ...
                        view.pageAdjustmentReason,'',matrix.contextId,'buildRelationView','',''));
                end
            end
            first=(view.currentPage-1)*view.pageSize+1;
            last=min(numel(ordered),first+view.pageSize-1);
            displayIndices=ordered(first:last);
            view.displayFeatureIndices=displayIndices;
            view.displayedFeatureCount=numel(displayIndices);
            view.featureIds=matrix.featureIds(displayIndices);
            view.originalLabels=originalLabels(displayIndices);
            view.displayLabels=displayLabels(displayIndices);
            if ~isempty(view.secondaryFeatureMetricId)
                view.secondaryFeatureValues=secondaryValues(displayIndices)';
            end
            if ~isempty(orderedAssignments)
                displayAssignments=orderedAssignments(first:last);
                view.displayClusterAssignments=displayAssignments(:)';
                view.clusterBoundaryPositions=find(diff(displayAssignments(:)')~=0);
            end
            nextValues=fullValues(displayIndices,displayIndices);
            nextValidity=fullValidity(displayIndices,displayIndices);
            nextDiagonal=fullDiagonal(displayIndices,displayIndices);
            nextReasons=fullReasons(displayIndices,displayIndices);
            pairMask=nextValidity & ~nextDiagonal;
            view.values=NMResultsViewerFeatureRelationTools.numericMatrixRows(nextValues);
            view.validityMask=NMResultsViewerFeatureRelationTools.logicalMatrixRows(nextValidity);
            view.diagonalMask=NMResultsViewerFeatureRelationTools.logicalMatrixRows(nextDiagonal);
            view.invalidReasonCodes=NMResultsViewerFeatureRelationTools.textMatrixRows(nextReasons);
            view.pairwiseAdmissibilityMask=NMResultsViewerFeatureRelationTools.logicalMatrixRows(pairMask);
            view.displayLayers=NMResultsViewerFeatureRelationTools.displayLayersForIndices(matrix,displayIndices);
            relationPatternSlice=NMResultsViewerFeatureGraphTools.displayRelationClusterSlice(view.relationPatternGraph,displayIndices);
            if relationPatternSlice.available
                view.displayRelationClusterAssignments=relationPatternSlice.clusterIds;
                view.displayGraphEdgeMask=relationPatternSlice.selectedEdgeMask;
                view.displayPartialRelationClusterIds=relationPatternSlice.partialClusterIds;
            end
            [view.nValidPairs,view.validPairFraction]=NMResultsViewerFeatureRelationTools.validPairSummary(nextValidity,nextDiagonal);
            view.available=true;
            if view.displayedFeatureCount < 2
                view.availabilityCode='insufficient_displayed_features';
                view.enabled=false;
                view.disabledReason='At least two displayed features are required for a pairwise relation matrix.';
            else
                view.availabilityCode='available';
                view.enabled=true;
                view.disabledReason='';
            end
            view=NMResultsViewerFeatureRelationTools.assignViewIdentities(view,normalizedRequest,displayLabels);
        end

        function request = normalizeRelationViewRequest(request, nFeatures)
            % normalizeRelationViewRequest  Validate and normalize public matrix/graph view state.
            %
            % Syntax:
            %   request = NMResultsViewerFeatureRelationTools.normalizeRelationViewRequest(request,nFeatures)
            %
            % Inputs:
            %   request    Partial relation-view request or wrapper containing relationState.
            %   nFeatures  Authoritative feature count of the selected matrix context.
            %
            % Outputs:
            %   request  Complete fixed-schema request with normalized layer, stable subset,
            %            filter, ordering, clustering, graph-pruning, pattern, and page settings.
            %
            % Scientific contract:
            %   primaryLayerId controls both graph pruning and the relation-pattern edge universe.
            %   Inactive graph-pruning parameters remain normalized but are excluded from the
            %   active edge-selection identity. Feature filters operate before graph construction.
            %
            % Invariants and mutability:
            %   The input value is not mutated. Pattern minimum size is at least two retained
            %   edges; fixed-count clustering requires at least two clusters.
            %
            % Errors and diagnostics:
            %   Invalid layers, ambiguous subset/label inputs, out-of-range indices, unsupported
            %   modes, and invalid numeric parameters raise explicit identified MATLAB errors.
            %
            % Side effects:
            %   None.
            if isempty(request), request=struct(); end
            % nm2-allow: public relation request boundary accepts the browser relationState wrapper
            if isstruct(request) && isfield(request,'relationState') && isstruct(request.relationState)
                request=request.relationState;
            end
            tmpl=NMResultsViewerFeatureRelationTools.relationViewRequestTemplate();
            fields=fieldnames(tmpl);
            for ii=1:numel(fields)
                % nm2-allow: public relation request boundary merges only documented request fields
                if isstruct(request) && isfield(request,fields{ii}) && ~isempty(request.(fields{ii}))
                    tmpl.(fields{ii})=request.(fields{ii});
                end
            end
            request=tmpl;
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.matrixId=strtrim(char(string(request.matrixId)));
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.sourceScope=lower(strtrim(char(string(request.sourceScope))));
            if ~isempty(request.sourceScope) && ~ismember(request.sourceScope,{'modality','combined'})
                error('NMResultsViewerFeatureRelationTools:sourceScopeInvalid', ...
                    'Unsupported relation source scope: %s.',request.sourceScope);
            end
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.relationId=strtrim(char(string(request.relationId)));
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.primaryLayerId=lower(strtrim(char(string(request.primaryLayerId))));
            allowedLayers={'feature_correlation','mean_log10_p','mean_log10_fdr_q'};
            if ~ismember(request.primaryLayerId,allowedLayers)
                error('NMResultsViewerFeatureRelationTools:primaryLayerInvalid', ...
                    'Unsupported primary relation layer: %s.',request.primaryLayerId);
            end
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            expression=strtrim(char(string(request.featureIndexExpression)));
            explicit=request.featureIndices;
            if ~isempty(expression) && ~isempty(explicit)
                error('NMResultsViewerFeatureRelationTools:ambiguousFeatureSubset', ...
                    'Specify either featureIndexExpression or featureIndices, not both.');
            end
            if ~isempty(expression)
                [indices,~]=NMSerializationTools.interpretNumericExpression(expression,'numeric_vector');
            elseif isempty(explicit)
                indices=[];
            % nm2-allow: public relation request boundary accepts numeric stable feature-index transport
            elseif isnumeric(explicit) || islogical(explicit)
                indices=double(explicit(:)');
            else
                error('NMResultsViewerFeatureRelationTools:featureIndicesType', ...
                    'featureIndices must be a numeric vector.');
            end
            if any(~isfinite(indices)) || any(indices ~= round(indices)) || any(indices < 1) || any(indices > nFeatures)
                error('NMResultsViewerFeatureRelationTools:featureIndicesRange', ...
                    'Feature indices must be finite integers in the range 1:%d.',nFeatures);
            end
            request.resolvedFeatureIndices=unique(round(indices),'stable');
            if (~isempty(expression)||~isempty(explicit))&&isempty(request.resolvedFeatureIndices)
                error('NMResultsViewerFeatureRelationTools:featureSubsetEmpty','The requested feature subset is empty.');
            end
            directLabels=request.alternativeLabels;
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            labelExpression=strtrim(char(string(request.alternativeLabelsExpression)));
            if ~isempty(directLabels) && ~isempty(labelExpression)
                error('NMResultsViewerFeatureRelationTools:ambiguousAlternativeLabels', ...
                    'Specify either alternativeLabels or alternativeLabelsExpression, not both.');
            end
            resolvedLabels={};
            if ~isempty(labelExpression)
                [resolvedLabels,~]=NMSerializationTools.interpretTextLabelsExpression(labelExpression,max(1,nFeatures));
            elseif ~isempty(directLabels)
                resolvedLabels=NMSerializationTools.normalizeTextLabelVector(directLabels,max(1,nFeatures));
            end
            % nm2-allow: public alternative-label request must preserve the canonical relation feature axis
            if ~isempty(resolvedLabels) && numel(resolvedLabels) ~= nFeatures
                error('NMResultsViewerFeatureRelationTools:alternativeLabelCount', ...
                    'Alternative labels contain %d entries; exactly %d stable feature labels are required.', ...
                    numel(resolvedLabels),nFeatures);
            end
            request.resolvedAlternativeLabels=resolvedLabels;
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.secondaryFeatureMetricId=lower(strtrim(char(string(request.secondaryFeatureMetricId))));
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.secondaryThresholdMode=lower(strtrim(char(string(request.secondaryThresholdMode))));
            if isempty(request.secondaryThresholdMode), request.secondaryThresholdMode='none'; end
            request.secondaryThresholdLow=NMResultsViewerFeatureRelationTools.scalarOrNaN(request.secondaryThresholdLow);
            request.secondaryThresholdHigh=NMResultsViewerFeatureRelationTools.scalarOrNaN(request.secondaryThresholdHigh);
            request.secondaryThresholdValue=NMResultsViewerFeatureRelationTools.scalarOrNaN(request.secondaryThresholdValue);
            threshold=NMResultsViewerDisplaySemanticsTools.thresholdFromSpec(struct( ...
                'thresholdMode',request.secondaryThresholdMode, ...
                'thresholdLow',request.secondaryThresholdLow, ...
                'thresholdHigh',request.secondaryThresholdHigh, ...
                'thresholdValue',request.secondaryThresholdValue));
            request.secondaryThresholdMode=threshold.mode;
            request.secondaryThresholdLow=NaN;
            request.secondaryThresholdHigh=NaN;
            request.secondaryThresholdValue=NaN;
            switch threshold.mode
                case 'outside_interval'
                    request.secondaryThresholdLow=threshold.lower;
                    request.secondaryThresholdHigh=threshold.upper;
                case {'above_abs','above','below'}
                    request.secondaryThresholdValue=threshold.value;
            end
            if isempty(request.secondaryFeatureMetricId) && ~strcmp(request.secondaryThresholdMode,'none')
                error('NMResultsViewerFeatureRelationTools:secondaryMetricRequired', ...
                    'A secondary feature metric is required when a secondary threshold is active.');
            end
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.orderingMode=lower(strtrim(char(string(request.orderingMode))));
            allowedOrdering={'original','ascending','descending','absolute_ascending','absolute_descending'};
            if ~ismember(request.orderingMode,allowedOrdering)
                error('NMResultsViewerFeatureRelationTools:orderingModeInvalid', ...
                    'Unsupported relation ordering mode: %s.',request.orderingMode);
            end
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.orderingSource=lower(strtrim(char(string(request.orderingSource))));
            allowedSources={'primary_relation_summary','secondary_feature_metric'};
            if ~ismember(request.orderingSource,allowedSources)
                error('NMResultsViewerFeatureRelationTools:orderingSourceInvalid', ...
                    'Unsupported relation ordering source: %s.',request.orderingSource);
            end
            if strcmp(request.orderingSource,'secondary_feature_metric') && isempty(request.secondaryFeatureMetricId)
                error('NMResultsViewerFeatureRelationTools:secondaryOrderingMetricRequired', ...
                    'Secondary-feature ordering requires secondaryFeatureMetricId.');
            end
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.clusteringMode=lower(strtrim(char(string(request.clusteringMode))));
            allowedClustering={'none','signed_covariation','absolute_dependency'};
            if ~ismember(request.clusteringMode,allowedClustering)
                error('NMResultsViewerFeatureRelationTools:clusteringModeInvalid', ...
                    'Unsupported feature-relation clustering mode: %s.',request.clusteringMode);
            end
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.clusterExtractionMode=lower(strtrim(char(string(request.clusterExtractionMode))));
            allowedExtraction={'none','fixed_count','cut_height'};
            if ~ismember(request.clusterExtractionMode,allowedExtraction)
                error('NMResultsViewerFeatureRelationTools:clusterExtractionModeInvalid', ...
                    'Unsupported feature-cluster extraction mode: %s.',request.clusterExtractionMode);
            end
            if strcmp(request.clusteringMode,'none') && ~strcmp(request.clusterExtractionMode,'none')
                error('NMResultsViewerFeatureRelationTools:clusterExtractionRequiresClustering', ...
                    'Cluster extraction requires a non-empty clusteringMode.');
            end
            request.clusterCount=NMResultsViewerFeatureRelationTools.positiveInteger( ...
                request.clusterCount,'clusterCount',1,1000000);
            request.clusterCutHeight=NMResultsViewerFeatureRelationTools.scalarOrNaN(request.clusterCutHeight);
            if strcmp(request.clusterExtractionMode,'fixed_count') && request.clusterCount < 2
                error('NMResultsViewerFeatureRelationTools:clusterCountInvalid', ...
                    'fixed_count extraction requires at least two available features.');
            end
            if strcmp(request.clusterExtractionMode,'fixed_count') && request.clusterCount > nFeatures
                error('NMResultsViewerFeatureRelationTools:clusterCountRange', ...
                    'clusterCount must not exceed the %d stable features in the relation context.',nFeatures);
            end
            if strcmp(request.clusterExtractionMode,'cut_height') && ...
                    (~isfinite(request.clusterCutHeight) || request.clusterCutHeight < 0 || request.clusterCutHeight > 1)
                error('NMResultsViewerFeatureRelationTools:clusterCutHeightInvalid', ...
                    'cut_height extraction requires clusterCutHeight in the interval [0,1].');
            end
            if ~strcmp(request.clusterExtractionMode,'cut_height')
                request.clusterCutHeight=NaN;
            end
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.edgeSelectionMode=lower(strtrim(char(string(request.edgeSelectionMode))));
            if ~ismember(request.edgeSelectionMode,{'legacy_topk_union','fixed_density','absolute_threshold'})
                error('NMResultsViewerFeatureRelationTools:edgeSelectionModeInvalid', ...
                    'Unsupported graph edge-selection mode: %s.',request.edgeSelectionMode);
            end
            request.graphKPerNode=NMResultsViewerFeatureRelationTools.positiveInteger(request.graphKPerNode,'graphKPerNode',0,1000000);
            request.graphMaxGlobal=NMResultsViewerFeatureRelationTools.positiveInteger(request.graphMaxGlobal,'graphMaxGlobal',0,100000000);
            request.graphTargetDensity=NMResultsViewerFeatureRelationTools.scalarOrNaN(request.graphTargetDensity);
            if ~isfinite(request.graphTargetDensity) || request.graphTargetDensity<0 || request.graphTargetDensity>1
                error('NMResultsViewerFeatureRelationTools:graphTargetDensityInvalid', ...
                    'graphTargetDensity must lie in [0,1].');
            end
            request.graphAbsoluteThreshold=NMResultsViewerFeatureRelationTools.scalarOrNaN(request.graphAbsoluteThreshold);
            if ~isfinite(request.graphAbsoluteThreshold) || request.graphAbsoluteThreshold<0
                error('NMResultsViewerFeatureRelationTools:graphAbsoluteThresholdInvalid', ...
                    'graphAbsoluteThreshold must be finite and non-negative.');
            end
            request.relationPatternEnabled=NMResultsViewerFeatureRelationTools.logicalScalar(request.relationPatternEnabled,true);
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.relationPatternMethod=lower(strtrim(char(string(request.relationPatternMethod))));
            if ~strcmp(request.relationPatternMethod,'hierarchical_link_communities')
                error('NMResultsViewerFeatureRelationTools:relationPatternMethodInvalid', ...
                    'Only hierarchical_link_communities relation clustering is supported.');
            end
            % nm2-allow: public relation request boundary canonicalizes browser text tokens
            request.relationPatternCutMode=lower(strtrim(char(string(request.relationPatternCutMode))));
            if ~ismember(request.relationPatternCutMode,{'max_partition_density','manual_similarity'})
                error('NMResultsViewerFeatureRelationTools:relationPatternCutModeInvalid', ...
                    'Unsupported relation-pattern cut mode: %s.',request.relationPatternCutMode);
            end
            request.relationPatternSimilarityThreshold=NMResultsViewerFeatureRelationTools.scalarOrNaN(request.relationPatternSimilarityThreshold);
            if ~isfinite(request.relationPatternSimilarityThreshold) || request.relationPatternSimilarityThreshold<0 || request.relationPatternSimilarityThreshold>1
                error('NMResultsViewerFeatureRelationTools:relationPatternThresholdInvalid', ...
                    'Relation-pattern similarity threshold must lie in [0,1].');
            end
            request.relationPatternMinEdges=NMResultsViewerFeatureRelationTools.positiveInteger(request.relationPatternMinEdges,'relationPatternMinEdges',2,1000000);
            request.showAllRows=NMResultsViewerFeatureRelationTools.logicalScalar(request.showAllRows,false);
            if request.showAllRows
                request.pageSize=max(1,nFeatures);
                request.currentPage=1;
            else
                request.pageSize=NMResultsViewerFeatureRelationTools.positiveInteger(request.pageSize,'pageSize',1,250);
                request.currentPage=NMResultsViewerFeatureRelationTools.positiveInteger(request.currentPage,'currentPage',1,1000000);
            end
        end

    end

    methods (Static, Access=private)

        function options = buildOptions(varargin)
            options=struct('includeFullValues',false);
            if isempty(varargin), return; end
            raw=varargin{1};
            % nm2-allow: relation materialization call boundary owns optional transfer controls
            if isfield(raw,'includeFullValues') && ~isempty(raw.includeFullValues)
                options.includeFullValues=logical(raw.includeFullValues(1));
            % nm2-allow: relation materialization call boundary accepts the documented service transfer mode
            elseif isfield(raw,'transferMode') && strcmp(raw.transferMode,'service')
                options.includeFullValues=true;
            end
        end

        function view = populateViewIdentity(view,matrix)
            fields={'matrixId','contextId','analysisIndex','targetIndex','resultTargetIndex', ...
                'classIndex','modalityIndex','modalityLabel','sourceScope','sourceScopeLabel', ...
                'relationId','memberContextIds','memberVarind','memberFeatureCounts', ...
                'secondaryFeatureMetricsSupported','featureIdSemantics','componentApplicability', ...
                'componentSelectionAffectsContent'};
            for ii=1:numel(fields)
                view.(fields{ii})=matrix.(fields{ii});
            end
            view.baseRelationIdentity=matrix.provenanceId;
        end

        function view = assignViewIdentities(view,request,displayLabels)
            % assignViewIdentities  Finalize deterministic scientific and presentation identities.
            %
            % Syntax:
            %   view = NMResultsViewerFeatureRelationTools.assignViewIdentities(view,request,displayLabels)
            %
            % Scientific contract:
            %   The scientific identity includes base relation provenance, selected physical
            %   layer, stable subset/filter, ordering/clustering, graph-pruning settings, and
            %   relation-pattern settings. The graph token invalidates stale relation-
            %   pattern selections whenever the retained edge universe changes. Alternative
            %   labels and pagination remain presentation-only identity fields.
            %
            % Invariants and mutability:
            %   Returns an updated copy of view; request and labels are not mutated.
            %
            % Side effects:
            %   None.
            subsetToken=NMResultsViewerFeatureRelationTools.numericVectorToken(view.requestedFeatureIndices);
            filterToken=sprintf('%s:%s:%.17g:%.17g:%.17g', ...
                request.secondaryFeatureMetricId,request.secondaryThresholdMode, ...
                request.secondaryThresholdLow,request.secondaryThresholdHigh,request.secondaryThresholdValue);
            clustering=sprintf('C17d2.1:base_matlab:average:exact_optimal_leaf_order:%s:%s:%d:%.17g',request.clusteringMode, ...
                request.clusterExtractionMode,request.clusterCount,request.clusterCutHeight);
            graphRequest=NMResultsViewerFeatureGraphTools.graphRequestTemplate();
            graphRequest.sourceLayerId=request.primaryLayerId;
            graphRequest.edgeSelectionMode=request.edgeSelectionMode;
            graphRequest.kPerNode=request.graphKPerNode;
            graphRequest.maxGlobal=request.graphMaxGlobal;
            graphRequest.targetDensity=request.graphTargetDensity;
            graphRequest.absoluteThreshold=request.graphAbsoluteThreshold;
            graphSelectionState=NMResultsViewerFeatureGraphTools.edgeSelectionIdentity(graphRequest);
            graphState=sprintf('C17h1.1:%s:%d:%s:%s:%.17g:%d', ...
                graphSelectionState,double(request.relationPatternEnabled),request.relationPatternMethod, ...
                request.relationPatternCutMode,request.relationPatternSimilarityThreshold,request.relationPatternMinEdges);
            clusteringState=sprintf('%s|subset=%s|filter=%s|cluster=%s', ...
                view.baseRelationIdentity,subsetToken,filterToken,clustering);
            scientific=sprintf('%s|layer=%s|subset=%s|filter=%s|order=%s:%s|cluster=%s|graph=%s', ...
                view.baseRelationIdentity,request.primaryLayerId,subsetToken,filterToken, ...
                request.orderingSource,request.orderingMode,clustering,graphState);
            labelToken=NMResultsViewerFeatureRelationTools.labelVectorToken(displayLabels);
            presentation=sprintf('labels=%s|all=%d|page=%d:%d',labelToken,double(request.showAllRows),view.pageSize,view.currentPage);
            view.clusteringStateIdentity=clusteringState;
            view.clusteringCacheIdentity=sprintf('feature_relation_cluster_%08x', ...
                NMResultsViewerFeatureRelationTools.textChecksum(clusteringState));
            view.scientificStateIdentity=scientific;
            view.presentationStateIdentity=presentation;
            view.scientificCacheIdentity=sprintf('feature_relation_science_%08x', ...
                NMResultsViewerFeatureRelationTools.textChecksum(scientific));
            fullToken=[scientific '|' presentation];
            view.viewCacheIdentity=sprintf('feature_relation_view_%08x', ...
                NMResultsViewerFeatureRelationTools.textChecksum(fullToken));
            view.viewId=sprintf('%s_view_%08x',view.matrixId, ...
                NMResultsViewerFeatureRelationTools.textChecksum(fullToken));
        end

        function summaries = buildClusterSummaries(matrix,displayLabels,orderedIndices,orderedAssignments)
            summaries=repmat(NMResultsViewerFeatureRelationTools.clusterSummaryTemplate(),1,0);
            assignments=double(orderedAssignments(:)');
            orderedIndices=double(orderedIndices(:)');
            if isempty(assignments), return; end
            assert(numel(assignments)==numel(orderedIndices),'NMResultsViewerFeatureRelationTools:clusterAssignmentMismatch', ...
                'Cluster assignments must share the ordered feature axis.');
            clusterIds=unique(assignments,'stable');
            summaries=repmat(NMResultsViewerFeatureRelationTools.clusterSummaryTemplate(),1,numel(clusterIds));
            ids=matrix.featureIds;
            for ii=1:numel(clusterIds)
                clusterId=clusterIds(ii);
                positions=find(assignments==clusterId);
                featureIndices=orderedIndices(positions);
                summaries(ii).clusterId=clusterId;
                summaries(ii).size=numel(featureIndices);
                summaries(ii).singleton=numel(featureIndices)==1;
                summaries(ii).featureIndices=featureIndices;
                summaries(ii).featureIds=ids(featureIndices);
                summaries(ii).labels=displayLabels(featureIndices);
            end
        end

        function out = logicalScalar(value,fallback)
            out=logical(fallback);
            if isempty(value), return; end
            % nm2-allow: public relation request boundary accepts logical or numeric boolean transport
            if islogical(value) || isnumeric(value)
                out=logical(value(1));
                return;
            end
            % nm2-allow: public relation request boundary canonicalizes boolean text transport
            txt=lower(strtrim(char(string(value))));
            if ismember(txt,{'1','true','yes','on'})
                out=true;
            elseif ismember(txt,{'0','false','no','off'})
                out=false;
            end
        end

        function layers = displayLayersForIndices(matrix,displayIndices)
            % displayLayersForIndices  Slice every physical relation layer by one common stable order.
            %
            % Syntax:
            %   layers = NMResultsViewerFeatureRelationTools.displayLayersForIndices(matrix,displayIndices)
            %
            % Inputs:
            %   matrix          Full normalized relation-matrix contract.
            %   displayIndices  Stable source-feature indices in current display order.
            %
            % Outputs:
            %   layers  Bounded aligned value/validity/diagonal/reason matrices for hover and render.
            %
            % Scientific contract:
            %   All physical layers share exactly the same feature permutation, allowing browser
            %   comparison without independently reordering or recomputing evidence.
            %
            % Invariants and mutability:
            %   This is a presentation slice only; it does not alter graph pruning, graph statistics,
            %   relation-pattern membership, or the full matrix contract.
            %
            % Errors and diagnostics:
            %   Dimension-incompatible layers remain unavailable rather than being padded or imputed.
            %
            % Side effects:
            %   None.
            layers=repmat(NMResultsViewerFeatureRelationTools.displayLayerTemplate(),1,0);
            if isempty(matrix.layers) || isempty(displayIndices), return; end
            available=find([matrix.layers.available]);
            if isempty(available), return; end
            layers=repmat(NMResultsViewerFeatureRelationTools.displayLayerTemplate(),1,numel(available));
            for outputIndex=1:numel(available)
                source=matrix.layers(available(outputIndex));
                values=NMResultsViewerFeatureRelationTools.matrixFromRows(source.values);
                validity=NMResultsViewerFeatureRelationTools.logicalMatrixFromRows(source.validityMask);
                diagonal=NMResultsViewerFeatureRelationTools.logicalMatrixFromRows(source.diagonalMask);
                reasons=NMResultsViewerFeatureRelationTools.textMatrixFromRows(source.invalidReasonCodes);
                layers(outputIndex).layerId=source.layerId;
                layers(outputIndex).label=source.label;
                layers(outputIndex).sourceField=source.sourceField;
                layers(outputIndex).scientificQuantity=source.scientificQuantity;
                layers(outputIndex).valuePolarity=source.valuePolarity;
                layers(outputIndex).values=NMResultsViewerFeatureRelationTools.numericMatrixRows( ...
                    values(displayIndices,displayIndices));
                layers(outputIndex).validityMask=NMResultsViewerFeatureRelationTools.logicalMatrixRows( ...
                    validity(displayIndices,displayIndices));
                layers(outputIndex).diagonalMask=NMResultsViewerFeatureRelationTools.logicalMatrixRows( ...
                    diagonal(displayIndices,displayIndices));
                layers(outputIndex).invalidReasonCodes=NMResultsViewerFeatureRelationTools.textMatrixRows( ...
                    reasons(displayIndices,displayIndices));
                layers(outputIndex).available=true;
            end
        end

        function [result,diagnostics] = clusterFeatureIndices(matrix,selected,request)
            % clusterFeatureIndices  Derive deterministic hierarchical order from correlation coefficients.
            result=struct('available',false,'applied',false,'disabledReason','', ...
                'validPairFraction',NaN,'orderedFeatureIndices',selected(:), ...
                'orderedClusterAssignments',zeros(1,0),'clusterCount',0, ...
                'clusterSizes',zeros(1,0),'singletonClusterCount',0, ...
                'extractionApplied',false,'extractionDisabledReason','', ...
                'linkageMatrix',[]);
            diagnostics=repmat(NMResultsViewerFeatureRelationTools.diagnosticTemplate(),1,0);
            selected=selected(:);
            n=numel(selected);
            if n<2
                result.disabledReason='At least two admissible features are required for hierarchical clustering.';
                return;
            end
            if n>500
                result.disabledReason=sprintf(['Hierarchical clustering is limited to 500 admissible features per request; ' ...
                    '%d features are selected. Use the feature-index expression or secondary filter to define a bounded scientific subset.'],n);
                diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_clustering_size_limit', ...
                    result.disabledReason,'CorrMat_CV2',matrix.contextId,'clusterFeatureIndices','','');
                return;
            end
            correlationIndex=find(strcmp({matrix.layers.layerId},'feature_correlation'),1,'first');
            if isempty(correlationIndex) || ~matrix.layers(correlationIndex).available
                result.disabledReason='Correlation-derived clustering requires the authoritative feature-correlation layer.';
                diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_clustering_source_unavailable', ...
                    result.disabledReason,'CorrMat_CV2',matrix.contextId,'clusterFeatureIndices','','');
                return;
            end
            correlation=NMResultsViewerFeatureRelationTools.matrixFromRows(matrix.layers(correlationIndex).values);
            validity=NMResultsViewerFeatureRelationTools.logicalMatrixFromRows(matrix.layers(correlationIndex).validityMask);
            subCorrelation=correlation(selected,selected);
            subValidity=validity(selected,selected) & isfinite(subCorrelation);
            offDiagonal=~eye(n);
            validOffDiagonal=subValidity & offDiagonal;
            possible=n*(n-1);
            result.validPairFraction=nnz(validOffDiagonal)/max(1,possible);
            if ~all(validOffDiagonal(offDiagonal))
                missingPairs=(possible-nnz(validOffDiagonal))/2;
                result.disabledReason=sprintf(['Hierarchical clustering requires a complete correlation dissimilarity matrix. ' ...
                    '%d selected feature pair(s) are unavailable; values are not imputed or replaced by zero.'],round(missingPairs));
                diagnostics=NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_clustering_incomplete_matrix', ...
                    result.disabledReason,'CorrMat_CV2',matrix.contextId,'clusterFeatureIndices','','');
                return;
            end
            switch request.clusteringMode
                case 'signed_covariation'
                    distance=(1-subCorrelation)/2;
                case 'absolute_dependency'
                    distance=1-abs(subCorrelation);
                otherwise
                    result.disabledReason=sprintf('Unsupported clustering mode: %s.',request.clusteringMode);
                    return;
            end
            distance=(distance+distance')/2;
            distance(1:n+1:end)=0;
            distance=max(0,min(1,distance));
            try
                [linkageMatrix,leafOrder]=NMHierarchicalClusteringTools.averageLinkageOptimalOrder( ...
                    distance,selected);
                leafOrder=leafOrder(:);
                result.available=true;
                result.applied=true;
                result.orderedFeatureIndices=selected(leafOrder);
                result.linkageMatrix=NMResultsViewerFeatureRelationTools.numericMatrixRows(linkageMatrix);
                if ~strcmp(request.clusterExtractionMode,'none')
                    [assignments,count]=NMHierarchicalClusteringTools.extractClusters( ...
                        linkageMatrix,leafOrder,request.clusterExtractionMode,request.clusterCount,request.clusterCutHeight);
                    if isempty(assignments)
                        result.extractionDisabledReason=sprintf(['Cluster extraction mode %s is incompatible with the %d admissible ' ...
                            'features and the requested parameters.'],request.clusterExtractionMode,n);
                    else
                        result.orderedClusterAssignments=assignments;
                        result.clusterCount=count;
                        result.clusterSizes=accumarray(assignments(:),1,[count 1])';
                        result.singletonClusterCount=nnz(result.clusterSizes==1);
                        result.extractionApplied=true;
                    end
                end
            % nm2-allow: deterministic clustering failures become explicit Results Viewer diagnostics
            catch ME
                result.available=false;
                result.applied=false;
                result.orderedFeatureIndices=selected;
                result.orderedClusterAssignments=zeros(1,0);
                result.clusterCount=0;
                result.clusterSizes=zeros(1,0);
                result.singletonClusterCount=0;
                result.extractionApplied=false;
                result.extractionDisabledReason='';
                result.linkageMatrix=[];
                result.disabledReason=sprintf('%s: %s',ME.identifier,ME.message);
                diagnostics=NMResultsViewerFeatureRelationTools.diagnosticFromException( ...
                    'relation_clustering',ME,matrix.contextId);
            end
        end

        function label = clusteringModeLabel(mode)
            switch mode
                case 'signed_covariation'
                    label='Signed co-variation clustering';
                case 'absolute_dependency'
                    label='Absolute-dependency clustering';
                otherwise
                    label='No clustering';
            end
        end

        function definition = clusteringDistanceDefinition(mode)
            switch mode
                case 'signed_covariation'
                    definition='d(i,j) = (1 - r(i,j)) / 2';
                case 'absolute_dependency'
                    definition='d(i,j) = 1 - abs(r(i,j))';
                otherwise
                    definition='';
            end
        end

        function [ordered,scores] = orderFeatureIndices(values,validity,selected,secondaryValues,request)
            selected=selected(:);
            scores=nan(numel(selected),1);
            if strcmp(request.orderingSource,'secondary_feature_metric')
                scores=secondaryValues(selected);
            else
                subValues=values(selected,selected);
                subValidity=validity(selected,selected);
                subValidity(1:size(subValidity,1)+1:end)=false;
                for ii=1:numel(selected)
                    rowMask=subValidity(ii,:) & isfinite(subValues(ii,:));
                    if any(rowMask), scores(ii)=mean(subValues(ii,rowMask)); end
                end
            end
            if strcmp(request.orderingMode,'original')
                ordered=selected;
                return;
            end
            finiteMask=isfinite(scores);
            finitePositions=find(finiteMask);
            missingPositions=find(~finiteMask);
            key=scores(finitePositions);
            switch request.orderingMode
                case 'ascending'
                    primaryKey=key;
                case 'descending'
                    primaryKey=-key;
                case 'absolute_ascending'
                    primaryKey=abs(key);
                case 'absolute_descending'
                    primaryKey=-abs(key);
                otherwise
                    primaryKey=(1:numel(key))';
            end
            [~,order]=sortrows([primaryKey(:) finitePositions(:)],[1 2]);
            ordered=[selected(finitePositions(order)); selected(missingPositions)];
            scoreMap=nan(max(selected),1);
            scoreMap(selected)=scores;
            scores=scoreMap(ordered);
        end

        function labels = normalizedLabelVector(labels,n,labelName)
            if isempty(labels)
                labels=arrayfun(@(x) sprintf('Feature %d',x),1:n,'UniformOutput',false);
                return;
            end
            labels=NMSerializationTools.normalizeTextLabelVector(labels,max(1,n));
            if numel(labels) ~= n
                error('NMResultsViewerFeatureRelationTools:labelCountMismatch', ...
                    '%s contain %d entries but the relation matrix contains %d features.',labelName,numel(labels),n);
            end
        end

        function matrix = matrixFromRows(rows)
            if isempty(rows), matrix=[]; return; end
            matrix=vertcat(rows{:});
        end

        function matrix = logicalMatrixFromRows(rows)
            if isempty(rows), matrix=[]; return; end
            matrix=logical(vertcat(rows{:}));
        end

        function matrix = textMatrixFromRows(rows)
            if isempty(rows), matrix={}; return; end
            matrix=vertcat(rows{:});
        end

        function value = scalarOrNaN(value)
            if isempty(value), value=NaN; return; end
            % nm2-allow: public relation request boundary accepts numeric text transport
            if ischar(value) || isstring(value), value=str2double(char(string(value))); end
            % nm2-allow: public relation request boundary validates one scalar numeric control
            if ~(isnumeric(value) || islogical(value)) || numel(value) ~= 1
                value=NaN; return;
            end
            value=double(value(1));
        end

        function value = positiveInteger(value,fieldName,minValue,maxValue)
            % nm2-allow: public relation request boundary accepts integer text transport
            if ischar(value) || isstring(value), value=str2double(char(string(value))); end
            % nm2-allow: public relation request boundary validates one bounded integer control
            if ~(isnumeric(value) || islogical(value)) || numel(value) ~= 1 || ...
                    ~isfinite(double(value)) || double(value) ~= round(double(value)) || ...
                    double(value) < minValue || double(value) > maxValue
                error('NMResultsViewerFeatureRelationTools:positiveIntegerInvalid', ...
                    '%s must be an integer from %d to %d.',fieldName,minValue,maxValue);
            end
            value=round(double(value));
        end

        function token = numericVectorToken(values)
            if isempty(values), token='none'; return; end
            parts=arrayfun(@(x) sprintf('%d',round(double(x))),values(:)','UniformOutput',false);
            token=strjoin(parts,',');
        end

        function token = labelVectorToken(labels)
            if isempty(labels), token='original'; return; end
            token=sprintf('%08x',NMResultsViewerFeatureRelationTools.textChecksum(strjoin(labels(:)',char(31))));
        end

        function checksum = textChecksum(text)
            bytes=unicode2native(text,'UTF-8');
            checksum=uint32(hex2dec('FFFFFFFF'));
            polynomial=uint32(hex2dec('EDB88320'));
            for ii=1:numel(bytes)
                checksum=bitxor(checksum,uint32(bytes(ii)));
                for bitIndex=1:8
                    if bitand(checksum,uint32(1))
                        checksum=bitxor(bitshift(checksum,-1),polynomial);
                    else
                        checksum=bitshift(checksum,-1);
                    end
                end
            end
            checksum=bitcmp(checksum);
        end

        function diagnostic = diagnosticFromException(source,ME,contextId)
            stack1=''; stack2=''; stack3='';
            if ~isempty(ME.stack), stack1=NMResultsViewerFeatureRelationTools.stackText(ME.stack(1)); end
            if numel(ME.stack)>=2, stack2=NMResultsViewerFeatureRelationTools.stackText(ME.stack(2)); end
            if numel(ME.stack)>=3, stack3=NMResultsViewerFeatureRelationTools.stackText(ME.stack(3)); end
            diagnostic=NMResultsViewerFeatureRelationTools.diagnostic('error',source, ...
                sprintf('%s: %s',ME.identifier,ME.message),'',contextId,stack1,stack2,stack3);
        end

        function text = stackText(frame)
            text='';
            name=frame.name;
            file=frame.file;
            line=double(frame.line);
            if isfinite(line), text=sprintf('%s (%s:%d)',name,file,round(line)); else, text=sprintf('%s (%s)',name,file); end
        end

        function matrix = populateIdentity(matrix, ctx, classIndex)
            matrix.classIndex = classIndex;
            matrix.contextId = ctx.contextId;
            matrix.analysisIndex = ctx.analysisIndex;
            matrix.targetIndex = ctx.targetIndex;
            matrix.resultTargetIndex = ctx.resultTargetIndex;
            matrix.modalityIndex = ctx.modalityIndex;
            matrix.modalityLabel = ctx.modalityLabel;
            matrix.varind = ctx.varind;
            matrix.matrixId = sprintf('%s_matrix_training_feature_relation', matrix.contextId);
        end

        function n = contextFeatureCount(ctx)
            n = ctx.nFeatures;
            assert(isfinite(n) && n>=0 && n==round(n), ...
                'NMResultsViewerFeatureRelationTools:InvalidFeatureCount', ...
                'Canonical Feature Inspection context nFeatures must be a non-negative integer.');
        end

        function defs = layerDefinitions()
            tmpl = struct('layerId','','label','','sourceField','','scientificQuantity','', ...
                'valuePolarity','signed','triangleSemantics','symmetric','normalizer','correlation');
            defs = repmat(tmpl,1,3);
            defs(1) = struct('layerId','feature_correlation','label','Feature correlation', ...
                'sourceField','CorrMat_CV2', ...
                'scientificQuantity','Mean Pearson correlation of preprocessed training-space feature values across CV models', ...
                'valuePolarity','signed','triangleSemantics','symmetric','normalizer','correlation');
            defs(2) = struct('layerId','mean_log10_p','label','Mean -log10(P) evidence across CV models', ...
                'sourceField','CorrMat_CV2_p_uncorr', ...
                'scientificQuantity','Arithmetic mean of -log10(unadjusted P) evidence across CV models', ...
                'valuePolarity','positive','triangleSemantics','authoritative_upper_triangle','normalizer','evidence');
            defs(3) = struct('layerId','mean_log10_fdr_q','label','Mean -log10(FDR q) evidence across CV models', ...
                'sourceField','CorrMat_CV2_p_fdr', ...
                'scientificQuantity','Arithmetic mean of -log10(FDR-adjusted q) evidence across CV models', ...
                'valuePolarity','positive','triangleSemantics','authoritative_upper_triangle','normalizer','evidence');
        end

        function layer = layerFromDefinition(def)
            layer = NMResultsViewerFeatureRelationTools.layerTemplate();
            layer.layerId = def.layerId;
            layer.label = def.label;
            layer.sourceField = def.sourceField;
            layer.scientificQuantity = def.scientificQuantity;
            layer.valuePolarity = def.valuePolarity;
            layer.triangleSemantics = def.triangleSemantics;
        end

        function [matrix, validMask, diagonalMask, reasons, normalizationLabel, ok, diagnostic] = normalizeCorrelation(raw, sourceField, contextId)
            matrix = double(raw);
            n = size(matrix,1);
            diagnostic = repmat(NMResultsViewerFeatureRelationTools.diagnosticTemplate(),1,0);
            ok = true;
            normalizationLabel = 'validated_symmetric_correlation';
            tol = 1e-8;
            finiteMask = isfinite(matrix);
            if any(abs(matrix(finiteMask)) > 1 + tol)
                ok = false;
                diagnostic = NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_value_out_of_range', ...
                    sprintf('%s contains finite correlation values outside [-1, 1].', sourceField), ...
                    sourceField,contextId,'','','');
                validMask = false(n); diagonalMask = eye(n)>0; reasons = repmat({''},n,n);
                return;
            end
            matrix(finiteMask & matrix > 1) = 1;
            matrix(finiteMask & matrix < -1) = -1;
            % Compare stable upper-triangle pairs in bulk; keep the original
            % row-first diagnostic order when a stored pair is inconsistent.
            [row,column] = find(triu(true(n),1));
            upperIdx = sub2ind([n n],row,column);
            lowerIdx = sub2ind([n n],column,row);
            upper = matrix(upperIdx);
            lower = matrix(lowerIdx);
            upperFinite = isfinite(upper);
            lowerFinite = isfinite(lower);
            both = upperFinite & lowerFinite;
            mismatched = both & abs(upper-lower)>tol;
            if any(mismatched)
                badRows = row(mismatched);
                rr = min(badRows);
                cc = min(column(mismatched & row==rr));
                a = matrix(rr,cc); b = matrix(cc,rr);
                ok = false;
                diagnostic = NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_asymmetry', ...
                    sprintf('%s is materially asymmetric at feature pair (%d,%d): %.16g versus %.16g.', ...
                    sourceField,rr,cc,a,b), sourceField,contextId,'','','');
                validMask = false(n); diagonalMask = eye(n)>0; reasons = repmat({''},n,n);
                return;
            end
            average = (upper(both)+lower(both))/2;
            matrix(upperIdx(both)) = average;
            matrix(lowerIdx(both)) = average;
            upperOnly = upperFinite & ~lowerFinite;
            lowerOnly = ~upperFinite & lowerFinite;
            matrix(lowerIdx(upperOnly)) = upper(upperOnly);
            matrix(upperIdx(lowerOnly)) = lower(lowerOnly);
            recovered = nnz(upperOnly)+nnz(lowerOnly);
            if recovered > 0
                normalizationLabel = 'validated_symmetric_correlation_with_single_triangle_recovery';
                diagnostic = NMResultsViewerFeatureRelationTools.diagnostic('info','relation_triangle_recovered', ...
                    sprintf('%s recovered %d feature pair(s) from a single finite triangle entry.', sourceField,recovered), ...
                    sourceField,contextId,'','','');
            end
            validMask = isfinite(matrix);
            diagonalMask = eye(n)>0;
            reasons = NMResultsViewerFeatureRelationTools.reasonMatrix(validMask, diagonalMask);
        end

        function [matrix, validMask, diagonalMask, reasons, normalizationLabel, ok, diagnostic] = normalizeEvidence(raw, sourceField, contextId)
            raw = double(raw);
            n = size(raw,1);
            matrix = nan(n,n);
            diagnostic = repmat(NMResultsViewerFeatureRelationTools.diagnosticTemplate(),1,0);
            ok = true;
            normalizationLabel = 'mirrored_authoritative_upper_triangle';
            tol = 1e-12;
            finiteMask = isfinite(raw);
            if any(raw(finiteMask) < -tol)
                ok = false;
                diagnostic = NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_evidence_negative', ...
                    sprintf('%s contains negative finite -log10 evidence values.', sourceField), ...
                    sourceField,contextId,'','','');
                validMask = false(n); diagonalMask = eye(n)>0; reasons = repmat({''},n,n);
                return;
            end
            raw(finiteMask & raw < 0) = 0;
            % Only the upper triangle is an evidence authority. The lower
            % triangle may be nonzero, but it cannot supply a missing value.
            [row,column] = find(triu(true(n),1));
            upperIdx = sub2ind([n n],row,column);
            lowerIdx = sub2ind([n n],column,row);
            upper = raw(upperIdx);
            lower = raw(lowerIdx);
            ignoredLowerOnly = nnz(~isfinite(upper) & isfinite(lower) & abs(lower)>tol);
            matrix(upperIdx) = upper;
            matrix(lowerIdx) = upper;
            diagonalIdx = 1:n+1:n*n;
            finiteDiagonal = isfinite(raw(diagonalIdx));
            matrix(diagonalIdx(finiteDiagonal)) = raw(diagonalIdx(finiteDiagonal));
            if ignoredLowerOnly > 0
                diagnostic = NMResultsViewerFeatureRelationTools.diagnostic('warning','relation_evidence_lower_only_ignored', ...
                    sprintf(['%s contains %d non-zero lower-triangle value(s) without an authoritative ' ...
                    'upper-triangle counterpart; these values were ignored rather than guessed.'], ...
                    sourceField,ignoredLowerOnly), sourceField,contextId,'','','');
            end
            validMask = isfinite(matrix);
            diagonalMask = eye(n)>0;
            reasons = NMResultsViewerFeatureRelationTools.reasonMatrix(validMask, diagonalMask);
        end

        function reasons = reasonMatrix(validMask, diagonalMask)
            n = size(validMask,1);
            reasons = repmat({''},n,n);
            reasons(diagonalMask) = repmat({'self_relation'},nnz(diagonalMask),1);
            missing = ~validMask & ~diagonalMask;
            reasons(missing) = repmat({'stored_relation_not_estimable'},nnz(missing),1);
        end

        function [nValidPairs, fraction] = validPairSummary(validMask, diagonalMask)
            pairMask = triu(validMask & ~diagonalMask,1);
            nValidPairs = nnz(pairMask);
            n = size(validMask,1);
            nPossible = n*(n-1)/2;
            if nPossible > 0, fraction = nValidPairs/nPossible; else, fraction = NaN; end
        end

        function ids = featureIds(contextId, n)
            ids = cell(n,1);
            for ii=1:n, ids{ii}=sprintf('%s:f%d',contextId,ii); end
        end

        function rows = numericMatrixRows(matrix)
            if isempty(matrix), rows=[]; return; end
            rows = num2cell(double(matrix),2);
        end

        function rows = logicalMatrixRows(matrix)
            if isempty(matrix), rows=[]; return; end
            rows = num2cell(logical(matrix),2);
        end

        function rows = textMatrixRows(matrix)
            if isempty(matrix), rows={}; return; end
            rows = cell(size(matrix,1),1);
            for rr=1:size(matrix,1), rows{rr}=matrix(rr,:); end
        end

        function message = primaryLayerFailure(layers)
            message = 'The stored CorrMat_CV2 field does not satisfy the authoritative square, context-matched feature-relation contract.';
            hit = find(strcmp({layers.layerId},'feature_correlation'),1,'first');
            if ~isempty(hit) && ~isempty(layers(hit).disabledReason), message=layers(hit).disabledReason; end
        end


        function diagnostics = appendDiagnostics(diagnostics, extra)
            if isempty(extra), return; end
            if isempty(diagnostics), diagnostics=extra; else, diagnostics=[diagnostics extra]; end
        end

        function diagnostics = flattenDiagnostics(blocks)
            diagnostics = repmat(NMResultsViewerFeatureRelationTools.diagnosticTemplate(),1,0);
            for ii=1:numel(blocks)
                if ~isempty(blocks{ii}), diagnostics=NMResultsViewerFeatureRelationTools.appendDiagnostics(diagnostics,blocks{ii}); end
            end
        end

        function d = diagnosticTemplate()
            tmpl = struct('severity','','source','','message','','legacyField','', ...
                'contextId','','stackFunction1','','stackFunction2','','stackFunction3','');
            d=tmpl;
        end

        function d = diagnostic(severity, source, message, legacyField, contextId, stack1, stack2, stack3)
            d = NMResultsViewerFeatureRelationTools.diagnosticTemplate();
            d.severity=severity; d.source=source;
            d.message=message; d.legacyField=legacyField;
            d.contextId=contextId; d.stackFunction1=stack1;
            d.stackFunction2=stack2; d.stackFunction3=stack3;
        end
    end
end

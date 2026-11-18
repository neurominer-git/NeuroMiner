classdef NMResultsViewerTools
% NMResultsViewerTools
% -------------------------------------------------------------------------
% Read-only browser payload extraction for the alpha NM Results Viewer.
%
% The alpha viewer deliberately keeps the legacy MATLAB Results Viewer as the
% full fallback.  For browser-native classification inspection, this backend
% follows the legacy NM_Results_Viewer state flow:
%
%   perf_display -> switch_analysis -> load_analysis -> load_GDdims
%   display_classplot/display_roc/display_contigmat/display_contigplot
%
% The code below does not read raw GDdims fields naively.  It first builds a
% small GUIDE-compatible handles subset and delegates the central result
% transformation to load_GDdims.m when available on the legacy NM path.  The
% browser payload then disentangles the plotting primitives from the legacy
% display functions.  The model-optimization Stage 1 backend also extracts
% read-only GDdims.grid metric registries for later browser panels without
% invoking legacy GUIDE axes or mutating NM result structures.
% -------------------------------------------------------------------------

    methods (Static)
        function state = buildInitialState(NM, spec)
            % Purpose: Build the initial browser Results Viewer state and first authoritative payload for the requested result type.
            % Syntax: state = NMResultsViewerTools.buildInitialState(NM,spec)
            % Inputs: NM is the read-only workspace; spec contains requested analysis/target/result/source/model selectors.
            % Outputs: state is the JSON-safe browser state including catalogues, selected coordinates, payload context and active Scientific State.
            % Authority and flow: Initial result-type admission uses the compact resultTypesForAnalysis inventory over the already-resident analysis catalogue; only the selected result family is materialized. comparison is a top-level multi-analysis workspace whose internal selectors are owned by NMResultsViewerCrossAnalysisTools.
            % Scientific/state contract: Cross-analysis workspacePayload always publishes its fixed Scientific State. Ordinary result families publish one selected payload and derive active Scientific State from that payload.
            % Invariants: Result-type selection precedes source/model/classifier materialization; comparison never inherits stale single-analysis selector state.
            % Materialization and performance: Performs compact catalogue/selector queries and materializes exactly one initial payload.
            % Failure semantics: Delegated selector/materializer errors remain explicit; unavailable result types carry their established reasons rather than browser repair.
            % Side effects: None; profiling output may be emitted when enabled.
            if ~isfield(spec,'resultType'), spec.resultType=''; end % nm2-allow: initial Results Viewer ingress leaves omitted result family to the scientific catalogue.
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            doProfile = NMResultsViewerTools.profileEnabled(spec);
            tReturnBoundary = tic;
            returnBoundaryProfiler = onCleanup(@() NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]     results state function return boundary:     %.3fs\n', toc(tReturnBoundary))); %#ok<NASGU>
            tTotal = tic; t = tic;

            % nm2-allow: NMResultsViewerUI_main.stateRequestSpecForChange alone supplies the optional navigation marker; direct MATLAB builders omit it.
            navigation = isfield(spec,'selectionTransition') && ~isempty(spec.selectionTransition);
            analyses = NMResultsViewerTools.listAnalyses(NM);
            selected = NMResultsViewerTools.selectedAnalysisIndex(analyses, spec);
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]     results state catalogue/selection: %.3fs (analyses=%d, selected=%d)\n', ...
                toc(t), double(numel(analyses)), double(selected));

            state = struct();
            state.page = 'results_viewer_alpha';
            state.title = 'New NM Results Viewer (alpha)';
            state.analyses = analyses;
            state.selectedAnalysisIndex = selected;

            tHelper=tic;
            state.targets = NMResultsViewerTools.targetOptions(NM, selected);
            sourceSpec=spec;
            if navigation && isfinite(double(sourceSpec.targetNativeIndex)) && ...
                    ~any([state.targets.enabled] & [state.targets.index] == double(sourceSpec.targetNativeIndex))
                sourceSpec.targetNativeIndex = NaN;
                sourceSpec.targetIndex = NaN;
            end
            state.selectedTargetIndex = NMResultsViewerTools.selectedTargetIndex(state.targets, sourceSpec);
            state.selectedTargetResultIndex = NMResultsViewerTools.selectedTargetResultIndex(state.targets, state.selectedTargetIndex);
            sourceSpec.targetNativeIndex=state.selectedTargetIndex;
            sourceSpec.targetIndex=state.selectedTargetResultIndex;
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       selector targets:               %.3fs (count=%d)\n', ...
                toc(tHelper), double(numel(state.targets)));

            tHelper=tic;
            [state.resultTypes,~,~] = NMResultsViewerTools.resultTypesForAnalysis(NM, selected, sourceSpec, analyses);
            if navigation && ~any(strcmp({state.resultTypes.id}, ...
                    NMResultsViewerTools.normalizeResultType(sourceSpec.resultType)) & [state.resultTypes.enabled])
                sourceSpec.resultType = '';
            end
            state.selectedResultType = NMResultsViewerTools.selectedResultType(state.resultTypes, sourceSpec);
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       scientific state/result types:  %.3fs (count=%d)\n', ...
                toc(tHelper), double(numel(state.resultTypes)));

            sourceSpec.resultType = state.selectedResultType;
            if strcmp(NMResultsViewerTools.normalizeResultType(state.selectedResultType),'comparison')
                state.effectiveResultType = 'comparison';
                state.sources = repmat(struct('id','','label','','enabled',false,'reason',''),1,0);
                state.selectedSource = 'cv';
                state.oocvSubgroups = repmat(struct('index',1,'label','','enabled',false),1,0);
                state.selectedOOCVSubgroupIndex = 1;
                state.modelSources = repmat(struct('id','','label','','enabled',false,'reason','','kind','','index',NaN),1,0);
                state.selectedModelSource = '';
                state.classifiers = repmat(struct('index',1,'label','','enabled',false,'reason',''),1,0);
                state.multiClassModes = repmat(struct('index',1,'id','','label','','enabled',false,'reason',''),1,0);
                state.selectedMultiClassModeIndex = 1;
                state.yAxisOptions = repmat(struct('index',1,'label','','enabled',false,'reason',''),1,0);
                % nm2-allow: external NM1.4 Results Viewer dependency is optional at the NM2 browser boundary.
                state.legacyViewerAvailable = exist('NM_Results_Viewer','file') == 2;
                state.canInspect = selected > 0;
                payloadSpec = sourceSpec;
                payloadSpec.analysisIndex = selected;
                payloadSpec.resultType = 'comparison';
                t = tic;
                state.payload = NMResultsViewerTools.getPayload(NM,payloadSpec);
                state.payloadContext = NMResultsViewerTools.payloadContextFromSpec(payloadSpec,state.payload);
                state.activeScientificState = state.payload.scientificState;
                state.scientificState = state.payload.scientificState;
                state.message = state.payload.message;
                NMResultsViewerTools.profileLog(doProfile, '[nm-prof]     results state cross-analysis payload: %.3fs\n', toc(t));
                NMResultsViewerTools.profileLog(doProfile, '[nm-prof]     results state TOTAL:                %.3fs\n', toc(tTotal));
                return;
            end

            tHelper = tic;
            if navigation
                [navOOCV,~] = NMResultsViewerTools.parseOOCVSourceId(sourceSpec.source);
                if navOOCV && ~ismember(state.selectedResultType,{'classification','regression','multiclass','mli'})
                    sourceSpec.source = 'cv';
                end
            end
            state.effectiveResultType = NMResultsViewerTools.effectiveResultTypeFromSpec(NM, selected, state.selectedResultType, sourceSpec);
            state.sources = NMResultsViewerTools.sourcesForAnalysis(NM, selected, state.effectiveResultType);
            if navigation && ~any(strcmp({state.sources.id},sourceSpec.source) & [state.sources.enabled])
                sourceSpec.source = '';
            end
            state.selectedSource = NMResultsViewerTools.selectedSourceId(state.sources, sourceSpec);
            sourceSpec.source = state.selectedSource;
            state.effectiveResultType = NMResultsViewerTools.effectiveResultTypeFromSpec(NM, selected, state.selectedResultType, sourceSpec);
            [isOOCVStateSource, ~] = NMResultsViewerTools.parseOOCVSourceId(state.selectedSource);
            if isOOCVStateSource
                sourceSpec.resultType = state.effectiveResultType;
                state.sources = NMResultsViewerTools.sourcesForAnalysis(NM, selected, state.effectiveResultType);
                state.selectedSource = NMResultsViewerTools.selectedSourceId(state.sources, sourceSpec);
                sourceSpec.source = state.selectedSource;
            end
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       selector source resolution:     %.3fs (count=%d)\n', ...
                toc(tHelper), double(numel(state.sources)));
            if navigation
                % Subgroup identity is meaningful only inside its selected OOCV
                % source; CV and a different grouping catalogue begin at all cases.
                [isOOCVTransitionSource,~] = NMResultsViewerTools.parseOOCVSourceId(sourceSpec.source);
                if ~isOOCVTransitionSource
                    sourceSpec.oocvSubgroupIndex = 1;
                end
            end
            [state.oocvSubgroups,state.selectedOOCVSubgroupIndex] = NMResultsViewerTools.oocvSubgroupsForAnalysis(NM, selected, sourceSpec);
            sourceSpec.oocvSubgroupIndex = state.selectedOOCVSubgroupIndex;

            tHelper = tic;
            state.modelSources = NMResultsViewerTools.modelSourcesForAnalysis(NM, selected, state.effectiveResultType, sourceSpec);
            if navigation && ~any(strcmp({state.modelSources.id},sourceSpec.modelSource) & [state.modelSources.enabled])
                sourceSpec.modelSource = '';
            end
            state.selectedModelSource = NMResultsViewerTools.selectedModelSourceId(state.modelSources, sourceSpec);
            sourceSpec.modelSource = state.selectedModelSource;
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       selector model-source:          %.3fs (count=%d)\n', ...
                toc(tHelper), double(numel(state.modelSources)));

            tHelper = tic;
            state.classifiers = NMResultsViewerTools.classifierOptions(NM, selected, state.selectedResultType, sourceSpec);
            if navigation && ~any([state.classifiers.enabled] & [state.classifiers.index] == double(sourceSpec.classifierIndex))
                firstClassifier = find([state.classifiers.enabled],1,'first');
                if ~isempty(firstClassifier)
                    sourceSpec.classifierIndex = state.classifiers(firstClassifier).index;
                end
            end
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       selector classifiers:           %.3fs (count=%d)\n', ...
                toc(tHelper), double(numel(state.classifiers)));
            tHelper = tic;
            state.multiClassModes = NMResultsViewerTools.multiClassModeOptions(NM, selected, sourceSpec);
            if navigation && any([state.multiClassModes.enabled]) && ...
                    ~any([state.multiClassModes.enabled] & [state.multiClassModes.index] == double(sourceSpec.multiClassModeIndex))
                firstMode = find([state.multiClassModes.enabled],1,'first');
                sourceSpec.multiClassModeIndex = state.multiClassModes(firstMode).index;
            end
            state.selectedMultiClassModeIndex = NMResultsViewerTools.selectedMultiClassModeIndex(state.multiClassModes, sourceSpec);
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       selector multiclass modes:      %.3fs (count=%d)\n', ...
                toc(tHelper), double(numel(state.multiClassModes)));
            tHelper = tic;
            state.yAxisOptions = NMResultsViewerTools.yAxisOptionsForAnalysis(NM, selected, state.effectiveResultType, sourceSpec);
            if navigation && any([state.yAxisOptions.enabled]) && ...
                    ~any([state.yAxisOptions.enabled] & [state.yAxisOptions.index] == double(sourceSpec.graphType))
                firstYAxis = find([state.yAxisOptions.enabled],1,'first');
                sourceSpec.graphType = state.yAxisOptions(firstYAxis).index;
            end
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       selector y-axis options:        %.3fs (count=%d)\n', ...
                toc(tHelper), double(numel(state.yAxisOptions)));
            % nm2-allow: external NM1.4 Results Viewer dependency is optional at the NM2 browser boundary.
            state.legacyViewerAvailable = exist('NM_Results_Viewer','file') == 2;
            state.canInspect = selected > 0;
            state.message = NMResultsViewerTools.initialMessage(state);

            payloadSpec = sourceSpec;
            payloadSpec.analysisIndex = selected;
            payloadSpec.source = state.selectedSource;
            payloadSpec.modelSource = state.selectedModelSource;
            payloadSpec.resultType = state.effectiveResultType;
            payloadSpec.targetNativeIndex = state.selectedTargetIndex;
            payloadSpec.targetIndex = state.selectedTargetResultIndex;
            payloadSpec.multiClassModeIndex = state.selectedMultiClassModeIndex;
            t = tic;
            tPayload = tic;
            state.payload = NMResultsViewerTools.getPayload(NM, payloadSpec);
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       results state selected payload materialization: %.3fs\n', toc(tPayload));
            tProjection = tic;
            state.payloadContext = NMResultsViewerTools.payloadContextFromSpec(payloadSpec, state.payload);
            state.activeScientificState = NMResultsViewerScientificState.clientView( ...
                NMResultsViewerScientificState.fromPayloads({state.payload},payloadSpec));
            state.scientificState = state.activeScientificState;
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       results state browser/state projection:         %.3fs\n', toc(tProjection));
            NMResultsViewerTools.profileLog(doProfile, '[nm-prof]     results state initial payload:      %.3fs\n', toc(t));
            NMResultsViewerTools.profileLog(doProfile, '[nm-prof]     results state TOTAL:                %.3fs\n', toc(tTotal));
        end

        function payload = getPayload(NM, spec)
            % Purpose: Dispatch a normalized Results Viewer payload request to the owning result-domain materializer.
            % Syntax: payload = NMResultsViewerTools.getPayload(NM,spec)
            % Inputs: NM is read-only; spec identifies resultType plus its domain selectors/source.
            % Outputs: payload is the JSON-safe scientific/presentation materialization for the normalized result type.
            % Authority and flow: normalizeResultType selects the domain owner. comparison delegates immediately to NMResultsViewerCrossAnalysisTools.workspacePayload; performance, optimization, Feature Inspection and MLI retain their existing authorities.
            % Scientific/state contract: This dispatcher never treats cross-analysis as classification and does not compute cross-analysis metrics itself.
            % Invariants: Each normalized result type has one materialization path; source/model coordinates retain their existing domain meanings.
            % Materialization and performance: Dispatcher overhead is O(1); actual cost belongs to the selected authority. The comparison workspace path is metadata-only and performs no file/XML/atlas/annotation/mesh reads, voxel/vertex scans, or feature-scale allocations.
            % Resource declaration: The dispatcher itself reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; delegated result-type authorities own any such work. The comparison workspace branch is compact and safe for interactive refresh.
            % Failure semantics: Unsupported/unavailable domain requests use existing explicit payload/error semantics; no fallback to another scientific result type except established normalization rules.
            % Side effects: None except optional profiling output.
            % Consumers and dependencies: Results Viewer UI, Report Builder, Cross-analysis peer consumers and API callers.
            if nargin < 2 || isempty(spec), spec = struct(); end
            % nm2-allow: getPayload accepts non-struct public request input; only
            % MATLAB struct requests can receive canonical dispatch selectors.
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            canRewriteSpec = isstruct(spec);
            resultType = spec.resultType;
            requestedSource = spec.source;
            payloadSource = requestedSource;
            doProfile = NMResultsViewerTools.profileEnabled(spec);
            tPayload = tic;
            payloadCleanup = onCleanup(@() NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]     results getPayload type=%s source=%s TOTAL: %.3fs\n', ...
                resultType, requestedSource, toc(tPayload))); %#ok<NASGU>
            [isOOCVSource, ~] = NMResultsViewerTools.parseOOCVSourceId(requestedSource);
            normalizedResultType = NMResultsViewerTools.normalizeResultType(resultType);
            if strcmp(normalizedResultType,'comparison')
                if canRewriteSpec, spec.resultType='comparison'; end
                payload=NMResultsViewerCrossAnalysisTools.workspacePayload(NM,spec);
                return;
            end
            if strcmp(normalizedResultType, 'model_optimization')
                if isOOCVSource
                    payload = NMResultsViewerTools.emptyPayload('model_optimization');
                    payload.message = sprintf('Model optimization is available for training/CV result containers only; requested source %s is an OOCV/application source.', requestedSource);
                    payload.unsupportedPanels = {payload.message};
                else
                    if canRewriteSpec
                        spec.resultType = 'model_optimization';
                        spec.source = 'cv';
                    end
                    payload = NMResultsViewerTools.getModelOptimizationPayload(NM, spec);
                    payloadSource = 'cv';
                end
            elseif strcmp(normalizedResultType, 'mli')
                if canRewriteSpec, spec.resultType = 'mli'; end
                payload = NMResultsViewerMLITools.getPayload(NM, spec);
            elseif strcmp(normalizedResultType, 'model_feature_inspection')
                if isOOCVSource
                    payload = NMResultsViewerTools.emptyModelFeatureInspectionPayload();
                    payload.message = sprintf('Model feature inspection is available for training/CV VIS outputs only; requested source %s is an OOCV/application source.', requestedSource);
                    payload.unsupportedPanels = {payload.message};
                else
                    if canRewriteSpec
                        spec.resultType = 'model_feature_inspection';
                        spec.source = 'cv';
                    end
                    payload = NMResultsViewerTools.getModelFeatureInspectionPayload(NM, spec);
                end
            else
                if strcmp(normalizedResultType, 'classification') && NMResultsViewerTools.isMultiGroupClassifierRequest(NM, spec)
                    normalizedResultType = 'multiclass';
                    resultType = 'multiclass';
                    if canRewriteSpec, spec.resultType = 'multiclass'; end
                end
                if isOOCVSource
                    if canRewriteSpec
                        spec.source = requestedSource;
                        spec.resultType = normalizedResultType;
                    end
                    switch normalizedResultType
                        case 'classification'
                            payload = NMResultsViewerTools.getClassificationPayload(NM, spec);
                            payload = NMResultsViewerTools.enforceOOCVPayloadInvariant(payload, requestedSource);
                        case 'regression'
                            payload = NMResultsViewerTools.getRegressionPayload(NM, spec);
                        case 'multiclass'
                            payload = NMResultsViewerTools.getMultiClassPayload(NM, spec);
                        otherwise
                            payload = NMResultsViewerTools.emptyPayload(resultType);
                            payload.message = sprintf('OOCV source %s is not supported for result type %s.', requestedSource, resultType);
                    end
                else
                    % Non-OOCV comparison, optimization, MLI and Feature Inspection
                    % were dispatched above. The remaining CV family is fixed.
                    switch normalizedResultType
                        case 'classification'
                            payload = NMResultsViewerTools.getClassificationPayload(NM, spec);
                        case 'multiclass'
                            payload = NMResultsViewerTools.getMultiClassPayload(NM, spec);
                        case 'regression'
                            payload = NMResultsViewerTools.getRegressionPayload(NM, spec);
                    end
                end
            end
            % Source identity is attached once for every non-comparison result.
            payload = NMResultsViewerTools.attachPayloadSource(payload, payloadSource);
            % Attach identical QC presentation state once for each non-comparison
            % result, after its owning scientific materializer has completed.
            payload.subjectQCScalars = NMResultsViewerTools.subjectQCScalarPayload(NM, spec);
        end

        function context = payloadContextFromSpec(spec, payload)
            % payloadContextFromSpec  Build the canonical scientific-payload cache context.
            %
            % context = NMResultsViewerTools.payloadContextFromSpec(spec,payload)
            % returns a fixed-schema, backend-normalized description of the fields
            % that can change Results Viewer payload extraction. Irrelevant fields
            % are reset to neutral values for each result type so browser panel
            % state, stale selector DOM values and unrelated display controls do
            % not fragment the session-local scientific-payload cache.
            %
            % The returned context is read-only metadata. It does not alter NM,
            % the payload, the selected analysis or any Results Viewer state.
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            context = struct( ...
                'schemaVersion',1, ...
                'analysisIndex',0, ...
                'resultType','classification', ...
                'source','cv', ...
                'modelSource','', ...
                'classifierIndex',1, ...
                'targetIndex',1, ...
                'graphType',0, ...
                'multiClassModeIndex',0, ...
                'oocvSubgroupIndex',0, ...
                'binarizationEnabled',false, ...
                'binarizationThreshold','', ...
                'plotSort',false, ...
                'colorSwap',false, ...
                'percentRank',false, ...
                'probTransform',false, ...
                'calibrationMethod','', ...
                'xAxisExpression','', ...
                'xAxisLabel','', ...
                'subgroupExpression','', ...
                'maxFeatures',0, ...
                'maxComponents',0, ...
                'modalityIndex',0, ...
                'featureContextId','', ...
                'backprojectionComponentId','', ...
                'measureId','', ...
                'subjectCaseId','', ...
                'subjectCaseIndex',0);

            kind = NMResultsViewerTools.structAnyField(payload, 'kind', '');
            if isempty(kind), kind = NMResultsViewerTools.normalizeResultType(spec.resultType); end
            context.resultType = kind;

            analysisIndex = spec.analysisIndex;
            if ~isfinite(analysisIndex), analysisIndex = 0; end
            context.analysisIndex = max(0, round(double(analysisIndex)));
            resolvedAnalysis = NaN;
            if isfield(payload,'analysisIndex'), resolvedAnalysis = payload.analysisIndex; end % nm2-allow: domain payloads from getPayload and MLI have different presentation fields; cache context prefers the resolved field only when provided.
            if isfinite(resolvedAnalysis), context.analysisIndex = max(0, round(resolvedAnalysis)); end

            source = NMResultsViewerTools.structAnyField(payload,'selectedSource', ...
                spec.source);
            if isempty(strtrim(source)), source = 'cv'; end
            context.source = source;
            context.modelSource = NMResultsViewerTools.structAnyField(payload,'selectedModelSource', ...
                strtrim(spec.modelSource));

            targetIndex = spec.targetIndex;
            if ~isfinite(targetIndex), targetIndex = 1; end
            context.targetIndex = max(1, round(double(targetIndex)));
            resolvedTarget = NaN;
            if isfield(payload,'targetIndex'), resolvedTarget = payload.targetIndex; end % nm2-allow: domain payloads from getPayload and MLI have different presentation fields; cache context prefers the resolved field only when provided.
            if isfinite(resolvedTarget), context.targetIndex = max(1, round(resolvedTarget)); end
            classifierIndex = spec.classifierIndex;
            if ~isfinite(classifierIndex), classifierIndex = 1; end
            context.classifierIndex = max(1, round(double(classifierIndex)));
            resolvedClassifier = NaN;
            if isfield(payload,'classifierIndex'), resolvedClassifier = payload.classifierIndex; end % nm2-allow: domain payloads from getPayload and MLI have different presentation fields; cache context prefers the resolved field only when provided.
            if isfinite(resolvedClassifier), context.classifierIndex = max(1, round(resolvedClassifier)); end

            switch kind
                case 'model_optimization'
                    % Model optimization cache identity keeps application source and model source distinct,
                    % together with learner/classifier and target.
                case 'model_feature_inspection'
                    maxFeatures = spec.maxFeatures;
                    if ~isfinite(maxFeatures), maxFeatures = 200; end
                    context.maxFeatures = max(1, round(double(maxFeatures)));
                    maxComponents = spec.maxComponents;
                    if ~isfinite(maxComponents), maxComponents = 200; end
                    context.maxComponents = max(1, round(double(maxComponents)));
                    modalityIndex = spec.modalityIndex;
                    if ~isfinite(modalityIndex), modalityIndex = 0; end
                    context.modalityIndex = max(0, round(double(modalityIndex)));
                    context.featureContextId = NMResultsViewerTools.structAnyField(payload,'selectedFeatureContextId', ...
                        strtrim(spec.featureContextId));
                    if ~isempty(context.featureContextId)
                        % featureContextId is the canonical scientific identity;
                        % modalityIndex remains only an input compatibility selector.
                        context.modalityIndex = 0;
                    end
                    context.backprojectionComponentId = NMResultsViewerTools.structAnyField(payload,'selectedBackprojectionComponentId', ...
                        strtrim(spec.backprojectionComponentId));
                    context.measureId = strtrim(spec.measureId);
                case 'mli'
                    context.featureContextId = NMResultsViewerTools.structAnyField(payload,'selectedFeatureContextId', ...
                        strtrim(spec.featureContextId));
                    context.measureId = NMResultsViewerTools.structAnyField(payload,'selectedMeasureId', ...
                        strtrim(spec.measureId));
                    context.subjectCaseId = NMResultsViewerTools.structAnyField(payload,'selectedSubjectCaseId', ...
                        strtrim(spec.subjectCaseId));
                    subjectCaseIndex = spec.subjectCaseIndex;
                    resolvedSubject = NaN;
            if isfield(payload,'selectedSubjectIndex'), resolvedSubject = payload.selectedSubjectIndex; end % nm2-allow: domain payloads from getPayload and MLI have different presentation fields; cache context prefers the resolved field only when provided.
                    if isfinite(resolvedSubject), subjectCaseIndex = resolvedSubject; end
                    if ~isfinite(subjectCaseIndex), subjectCaseIndex = 0; end
                    context.subjectCaseIndex = max(0, round(double(subjectCaseIndex)));
                otherwise
                    graphType = spec.graphType;
                    if ~isfinite(graphType), graphType = 1; end
                    graphType = max(1, round(double(graphType)));
                    if strcmp(kind,'regression'), graphType = min(3, graphType); end
                    context.graphType = graphType;
                    context.plotSort = spec.plotSort;
                    context.colorSwap = spec.colorSwap;
                    context.percentRank = spec.percentRank;
                    context.probTransform = spec.probTransform;
                    if context.probTransform
                        method = spec.calibrationMethod;
                        context.calibrationMethod = method;
                    end
                    context.xAxisExpression = strtrim(spec.xAxisExpression);
                    if ~isempty(context.xAxisExpression)
                        context.xAxisLabel = strtrim(spec.xAxisLabel);
                    end
                    context.subgroupExpression = strtrim(spec.subgroupExpression);
                    [isOOCVSource, ~] = NMResultsViewerTools.parseOOCVSourceId(context.source);
                    if isOOCVSource
                        oocv = NMResultsViewerTools.structAnyField(payload, 'oocv', struct());
                        context.oocvSubgroupIndex = 0;
                        if isfield(oocv,'selectedSubgroupIndex') % nm2-allow: OOCV payloads may lack resolved subgroup metadata when source is unavailable.
                            context.oocvSubgroupIndex = oocv.selectedSubgroupIndex;
                        end
                    end
                    if strcmp(kind,'multiclass')
                        modeIdx = spec.multiClassModeIndex;
                        if isfield(payload,'selectedMultiClassModeIndex'), modeIdx = payload.selectedMultiClassModeIndex; end % nm2-allow: multiclass presentation payloads optionally carry a resolved mode selection; reader uses the displayed selection when present.
                        if ~isfinite(modeIdx), modeIdx = 1; end
                        context.multiClassModeIndex = max(1, round(double(modeIdx)));
                    elseif strcmp(kind,'regression')
                        % nm2-allow: NMResultsViewerReportTools may omit binarizationEnabled until single-specification construction replaces optional action selectors.
                        context.binarizationEnabled = spec.binarizationEnabled;
                        context.binarizationThreshold = strtrim(spec.binarizationThreshold);
                    end
            end
        end


        function payload = getModelFeatureInspectionPayload(NM, spec)
            if NMResultsViewerScientificCapability.isQuery(NM)
                P=@NMResultsViewerScientificCapability.provide;
                capabilities=[P('feature_inspection_payload','scientific_artefact','feature_inspection','feature_inspection_payload'), ...
                    P('feature_ranking','scientific_artefact','feature_inspection','feature_ranking'), ...
                    P('feature_metric_table','scientific_artefact','feature_inspection','feature_metric_table'), ...
                    P('feature_relation_matrix','scientific_artefact','feature_inspection','feature_relation_matrix'), ...
                    P('feature_modality_contribution','scientific_artefact','feature_inspection','modality_contribution'), ...
                    P('feature_component_summary','scientific_artefact','feature_inspection','component_summary'), ...
                    P('feature_component_modality','scientific_artefact','feature_inspection','component_modality'), ...
                    P('feature_fractionated_decision','scientific_artefact','feature_inspection','fractionated_decision'), ...
                    P('feature_extra_label_generalization','scientific_artefact','feature_inspection','extra_label_generalization'), ...
                    P('voxel_feature_map','scientific_artefact','feature_inspection','voxel_feature_map'), ...
                    P('surface_feature_map','scientific_artefact','feature_inspection','surface_feature_map'), ...
                    P('connectivity_feature_map','scientific_artefact','feature_inspection','connectivity_feature_map'), ...
                    P('roi_feature_map','scientific_artefact','feature_inspection','roi_feature_map'), ...
                    P('feature_ranking_view','visualization','',''),P('feature_metric_table_view','visualization','',''), ...
                    P('feature_metric_bar','visualization','',''),P('feature_metric_distribution','visualization','',''), ...
                    P('feature_metric_relationship','visualization','',''),P('feature_relation_matrix_view','visualization','',''), ...
                    P('feature_network','visualization','',''),P('feature_modality_contribution_view','visualization','',''), ...
                    P('feature_component_summary_view','visualization','',''),P('feature_component_modality_view','visualization','',''), ...
                    P('feature_fractionated_individual_view','visualization','',''), ...
                    P('feature_fractionated_population_view','visualization','',''), ...
                    P('feature_fractionated_clusters_view','visualization','',''), ...
                    P('feature_extra_label_generalization_view','visualization','',''),P('spatial_feature_map_summary','visualization','','')];
                ids={capabilities.id};
                % nm2-allow: NMResultsViewerScientificCapability.interrogate calls providers without a context; available() supplies the canonical payload context.
                if nargin>=2
                    q=spec.payload;
                    ids={};
                    if strcmp(q.scientificAnnotation.domain,'feature_inspection')
                        featurePayloadAvailable=logical(q.ok)||~isempty(q.featureTable)|| ...
                            ~isempty(q.matrixPayloads)||~isempty(q.networkPayloads)||~isempty(q.spatialMaps);
                        if featurePayloadAvailable
                            ids={'feature_inspection_payload'};
                            if ~isempty(q.featureTable)
                                ids(end+1:end+5)={'feature_ranking','feature_metric_table','feature_ranking_view','feature_metric_table_view','feature_metric_bar'};
                                if numel(q.featureTable)>=50,ids{end+1}='feature_metric_distribution';end
                                if numel(q.featureTable)>=2,ids{end+1}='feature_metric_relationship';end
                            elseif strcmp(q.payloadScope,'metadata')&&~isempty(q.contexts)&& ...
                                    ~isempty(q.measures)&&any([q.measures.enabled])
                                ids(end+1:end+5)={'feature_ranking','feature_metric_table','feature_ranking_view','feature_metric_table_view','feature_metric_bar'};
                                featureCount=max([q.contexts.nFeatures]);
                                if featureCount>=50,ids{end+1}='feature_metric_distribution';end
                                if featureCount>=2,ids{end+1}='feature_metric_relationship';end
                            end
                            relationAvailable=false;
                            for mm=1:numel(q.matrixPayloads)
                                matrixDescriptor=q.matrixPayloads(mm);
                                relationAvailable=relationAvailable||(logical(matrixDescriptor.available)&&logical(matrixDescriptor.relationServiceAvailable));
                            end
                            if ~relationAvailable&&strcmp(q.payloadScope,'metadata')&& ...
                                    logical(q.selectedFeatureContext.isCombined)&& ...
                                    strcmp(q.selectedFeatureContext.rendererFamily,'relation')&& ...
                                    strcmp(q.selectedFeatureContext.sourceKind,'visdata_combined_relation')
                                relationAvailable=true;
                            end
                            if relationAvailable
                                ids(end+1:end+3)={'feature_relation_matrix','feature_relation_matrix_view','feature_network'};
                            end
                            ca=q.componentAnalysis;
                            if ~isempty(ca.modalityShareTable),ids(end+1:end+2)={'feature_modality_contribution','feature_modality_contribution_view'};end
                            if ~isempty(ca.componentTable)||~isempty(ca.modalityComponentTable),ids(end+1:end+2)={'feature_component_summary','feature_component_summary_view'};end
                            if ~isempty(ca.componentModalityTable),ids(end+1:end+2)={'feature_component_modality','feature_component_modality_view'};end
                            if ca.fractionatedDecisionAvailable,ids(end+1:end+4)={'feature_fractionated_decision','feature_fractionated_individual_view','feature_fractionated_population_view','feature_fractionated_clusters_view'};end
                            if logical(q.extraLabelGeneralization.ok),ids(end+1:end+2)={'feature_extra_label_generalization','feature_extra_label_generalization_view'};end
                            if ~isempty(q.spatialMaps)
                                ids{end+1}='spatial_feature_map_summary';
                                for kk=1:numel(q.spatialMaps)
                                    sp=q.spatialMaps(kk);
                                    if ~logical(sp.enabled),continue;end
                                    switch sp.mapKind
                                        case 'voxel',ids{end+1}='voxel_feature_map';
                                        case 'surface_vertex',ids{end+1}='surface_feature_map';
                                        case 'connectivity_edge',ids{end+1}='connectivity_feature_map';
                                        case 'roi',ids{end+1}='roi_feature_map';
                                    end
                                end
                            end
                        end
                    end
                end
                payload=NMResultsViewerScientificCapability.contract('feature_inspection',{},NMResultsViewerScientificCapability.subset(capabilities,unique(ids,'stable'))); return;
            end
            % getModelFeatureInspectionPayload  Build one Feature-source-scoped inspection payload.
            %
            % payload = NMResultsViewerTools.getModelFeatureInspectionPayload(NM,spec)
            % derives an analysis-specific VIS context catalogue, resolves the public
            % target through targetOptions.resultIndex, and extracts only the selected
            % feature context. This prevents feature rows from heterogeneous modalities
            % from being merged into one ambiguous feature space. A combined context is
            % exposed for bounded early-fusion VIS members, using the same member
            % feature-vector machinery as intermediate fusion. Native ROI/tabular
            % representations are retained; cross-source relation matrices require
            % a separately persisted CombinedRelation contract.
            %
            % Authoritative selectors:
            %   spec.featureContextId  Stable context identity returned in
            %                          payload.featureContexts.
            %   spec.backprojectionComponentId
            %                          Stable retained-component identity returned in
            %                          payload.backprojectionComponents. The payload
            %                          also records original componentIndex and retained
            %                          componentPosition explicitly.
            % Transitional selector coordinates:
            %   spec.modalityIndex     VIS-row index. It is consulted only when
            %                          featureContextId is absent.
            %   spec.componentIndex    Original CompKept index, consulted only when
            %                          backprojectionComponentId is absent.
            %
            % Output:
            %   payload.featureContexts is the complete analysis-specific catalogue;
            %   payload.contexts and featureTable contain only the selected physical
            %   source(s); payload.matrixPayloads contains at most one authoritative
            %   relation source derived from the same header Feature source selection;
            %   component-resolved feature vectors are extracted only after
            %   validating an exact retained/all-component column axis;
            %   payload.componentAnalysis contains strictly normalized
            %   Report.modality, Report.components and Report.comp_by_mod summaries.
            %   Unsupported or dimensionally ambiguous layouts remain explicit in
            %   payload.diagnostics and are never truncated or positionally guessed.
            %
            % The method is read-only. It neither mutates NM nor recomputes VIS outputs.
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            payload = NMResultsViewerTools.emptyModelFeatureInspectionPayload();
            payload.analysisIndex = spec.analysisIndex;
            payload.targetIndex = spec.targetIndex;
            payload.classifierIndex = spec.classifierIndex;
            payload.selectedMeasureId = strtrim(spec.measureId);
            requestedMeasureId = payload.selectedMeasureId;
            % nm2-allow: payload scope is a public request token normalized once at the service boundary.
            payloadScope = spec.featureInspectionPayloadScope;
            if ~any(strcmp(payloadScope,{'full','metadata'}))
                error('NMResultsViewerTools:InvalidFeatureInspectionPayloadScope', ...
                    'Feature Inspection payload scope must be full or metadata; received "%s".',payloadScope);
            end
            % nm2-allow: catalogue scope is a public request token normalized once at the service boundary.
            catalogueScope = spec.featureInspectionCatalogueScope;
            if ~any(strcmp(catalogueScope,{'complete','selected'}))
                error('NMResultsViewerTools:InvalidFeatureInspectionCatalogueScope', ...
                    'Feature Inspection catalogue scope must be complete or selected; received "%s".',catalogueScope);
            end
            maxFeatures = spec.maxFeatures;
            if ~isfinite(double(maxFeatures)) || maxFeatures < 1, maxFeatures = 200; end
            maxFeatures = max(1, round(double(maxFeatures)));
            if maxFeatures > 5000, error('NMResultsViewerTools:InteractiveFeatureLimit','Interactive Feature Inspection is bounded to at most 5000 returned features per context.'); end
            maxComponents = spec.maxComponents;
            if ~isfinite(double(maxComponents)) || maxComponents < 1, maxComponents = 200; end
            maxComponents = max(1, round(double(maxComponents)));
            payload.maxFeaturesPerContext = maxFeatures;
            payload.maxComponentsPerContext = maxComponents;

            [payload,selection] = NMResultsViewerTools.modelFeatureInspectionResolveScientificSelection( ...
                NM,spec,payload,payloadScope,catalogueScope);
            if ~selection.ok
                return;
            end

            idx = round(double(payload.analysisIndex));
            resultTargetIndex = payload.resultTargetIndex;
            A = selection.analysis;
            catalogue = selection.catalogue;
            selectedCatalogueEntry = selection.selectedCatalogueEntry;
            selectedContexts = selection.selectedContexts;
            selectedComponent = selection.selectedComponent;
            catalogueDiagnostics = selection.catalogueDiagnostics;
            componentCatalogueDiagnostics = selection.componentCatalogueDiagnostics;

            if strcmp(payloadScope,'metadata')
                payload.payloadScope = 'metadata';
                [metadataContexts,metadataMeasures,metadataSpatialMaps,metadataSelectedMeasureId,metadataDiagnostics] = ...
                    NMResultsViewerTools.modelFeatureInspectionMetadataPayload( ...
                    NM,A,selectedContexts,resultTargetIndex,payload.classifierIndex, ...
                    payload.selectedMeasureId,selectedComponent, ...
                    [catalogueDiagnostics componentCatalogueDiagnostics]);
                payload.contexts = metadataContexts;
                payload.measures = metadataMeasures;
                payload.spatialMaps = metadataSpatialMaps;
                payload.selectedMeasureId = metadataSelectedMeasureId;
                [payload.scientificAnnotation,payload.resolvedSelection] = ...
                    NMResultsViewerTools.modelFeatureInspectionScientificAnnotation( ...
                        NM,payload,selection,requestedMeasureId);
                payload.measureAnnotations = NMResultsViewerTools.modelFeatureInspectionMeasureAnnotations( ...
                    payload.measures,payload.scientificAnnotation);

                % Modality/component summaries are compact report metadata rather
                % than feature-scale panel arrays. Resolve the authoritative
                % classifier-specific Report contract even in metadata-first mode
                % so imaging overlays can expose the same modality-related panels
                % as tabular Feature Inspection without materializing feature,
                % matrix, network, or direct component vectors.
                [metadataComponentAnalysis, metadataComponentDiagnostics] = ...
                    NMResultsViewerTools.modelFeatureInspectionNormalizeFusionReport( ...
                        A,catalogue(~[catalogue.isCombined]), ...
                        payload.classifierIndex,maxComponents);
                metadataComponentAnalysis.fractionatedDecisionAvailable = ...
                    NMResultsViewerTools.modelFeatureInspectionFractionatedAvailable( ...
                    A,selectedContexts,resultTargetIndex,payload.classifierIndex);
                payload.componentAnalysis = metadataComponentAnalysis;
                if isempty(metadataComponentDiagnostics)
                    payload.diagnostics = metadataDiagnostics;
                elseif isempty(metadataDiagnostics)
                    payload.diagnostics = metadataComponentDiagnostics;
                else
                    payload.diagnostics = [metadataDiagnostics metadataComponentDiagnostics];
                end
                payload.ok = ~isempty(payload.contexts) && ...
                    (~isempty(payload.measures) || any([payload.spatialMaps.enabled]) || ...
                    payload.componentAnalysis.ok);
                if payload.ok
                    payload.title = 'Model feature inspection';
                    if payload.backprojectionAvailable
                        payload.subtitle = sprintf('Analysis %d, target %d, feature source: %s, %s', ...
                            idx,payload.targetIndex,selectedCatalogueEntry.selectionLabel, ...
                            payload.selectedBackprojectionComponentLabel);
                    else
                        payload.subtitle = sprintf('Analysis %d, target %d, feature source: %s', ...
                            idx,payload.targetIndex,selectedCatalogueEntry.selectionLabel);
                    end
                    nReportRows = numel(payload.componentAnalysis.modalityShareTable) + ...
                        numel(payload.componentAnalysis.componentTable) + ...
                        numel(payload.componentAnalysis.componentModalityTable);
                    payload.message = sprintf(['Model feature inspection metadata resolved for "%s" ' ...
                        'with %d physical context(s), %d measure descriptor(s), %d compact modality/component summary row(s), and no eager feature-scale panel arrays.'], ...
                        selectedCatalogueEntry.selectionLabel,numel(payload.contexts), ...
                        numel(payload.measures),nReportRows);
                    payload.summaryRows = NMResultsViewerTools.modelFeatureInspectionSummaryRows(payload);
                else
                    payload.message = 'The selected feature context exposes no eligible feature measure metadata.';
                    payload.unsupportedPanels = {payload.message};
                end
                return;
            end

            contextCount = numel(selectedContexts);
            contextT = NMResultsViewerTools.modelFeatureInspectionContextTemplate();
            measureT = NMResultsViewerTools.modelFeatureInspectionMeasureTemplate();
            featureT = NMResultsViewerTools.modelFeatureInspectionFeatureRowTemplate();
            matrixT = NMResultsViewerTools.modelFeatureInspectionMatrixTemplate();
            networkT = NMResultsViewerTools.modelFeatureInspectionNetworkTemplate();
            spatialT = NMResultsViewerTools.modelFeatureInspectionSpatialTemplate();
            compRowT = NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate();
            diagT = NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate();

            payload.contexts = repmat(contextT, 1, contextCount);
            maxMeasures = contextCount * numel(NMResultsViewerTools.modelFeatureInspectionMeasureDefinitions());
            measures = repmat(measureT, 1, maxMeasures);
            featureRows = repmat(featureT, 1, contextCount * maxFeatures);
            matrixPayloads = repmat(matrixT, 1, contextCount + 1);
            networkPayloads = repmat(networkT, 1, contextCount + 1);
            % Spatial descriptors are measure-specific. Metric pages consume one
            % descriptor for every normalized measure in each spatial context rather
            % than only the currently selected feature-table measure.
            spatialMaps = repmat(spatialT, 1, maxMeasures);
            rawComponentRows = repmat(compRowT, 1, contextCount * maxComponents);
            diagnostics = repmat(diagT, 1, max(1, numel(catalogueDiagnostics) + numel(componentCatalogueDiagnostics) + contextCount * 32 + 8));

            baseDiagnostics=[catalogueDiagnostics componentCatalogueDiagnostics];
            dCount = numel(baseDiagnostics);
            if dCount > 0, diagnostics(1:dCount) = baseDiagnostics; end
            mCount = 0; fCount = 0; mxCount = 0; netCount = 0; spCount = 0; compCount = 0;
            measureSelectionResolved = false;
            for cc = 1:contextCount
                ctx = selectedContexts(cc);
                v = NMResultsViewerTools.modelFeatureInspectionVisEntry(A, ctx.visRowIndex, resultTargetIndex);
                if ~NMResultsViewerTools.modelFeatureInspectionIsVisStruct(v)
                    dCount = dCount + 1;
                    diagnostics(dCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', 'context_extraction', 'The selected catalogue context no longer resolves to an inspectable VIS struct.', '', ctx.contextId, '', '', '');
                    continue;
                end
                payload.contexts(cc) = ctx;
                [ctxMeasures, selectedMeasure, measureDiagnostics] = NMResultsViewerTools.modelFeatureInspectionMeasuresForVis(v, payload.classifierIndex, ctx.nFeatures, ctx.contextId, payload.selectedMeasureId, selectedComponent, false);
                if ~isempty(measureDiagnostics)
                    needed=dCount+numel(measureDiagnostics); if needed>numel(diagnostics), diagnostics(needed+4)=diagT; end
                    diagnostics(dCount+1:needed)=measureDiagnostics; dCount=needed;
                end
                if ~measureSelectionResolved && ~isempty(selectedMeasure.measureId)
                    payload.selectedMeasureId=selectedMeasure.measureId;
                    measureSelectionResolved=true;
                end
                if ~isempty(ctxMeasures)
                    nAdd = numel(ctxMeasures);
                    measures(mCount+1:mCount+nAdd) = ctxMeasures;
                    mCount = mCount + nAdd;
                else
                    dCount = dCount + 1;
                    diagnostics(dCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', 'measure_detection', 'No supported feature-inspection measure was found for this VIS context.', '', ctx.contextId, '', '', '');
                end
                [rows, rowDiag] = NMResultsViewerTools.modelFeatureInspectionFeatureRows(NM, v, ctx, selectedMeasure, payload.classifierIndex, maxFeatures, selectedComponent);
                if ~isempty(rows)
                    if selectedCatalogueEntry.isCombined
                        names = NMResultsViewerTools.modelFeatureInspectionQualifiedNames({rows.featureName},ctx.modalityLabel);
                        [rows.featureName] = names{:};
                        [rows.tooltipTitle] = names{:};
                    end
                    nRows = numel(rows);
                    featureRows(fCount+1:fCount+nRows) = rows;
                    fCount = fCount + nRows;
                end
                if ~isempty(rowDiag)
                    needed = dCount + numel(rowDiag);
                    if needed > numel(diagnostics), diagnostics(needed + 4) = diagT; end
                    diagnostics(dCount+1:needed) = rowDiag;
                    dCount = needed;
                end
                % Relation matrices are scoped by the authoritative Feature source
                % selector. A physical context exposes only its own modality matrix;
                % a combined context is resolved once after all member feature rows
                % have been assembled. Local matrices are never offered as alternate
                % relation sources inside a combined feature view.
                if ~selectedCatalogueEntry.isCombined
                    [mx, matrixDiagnostics] = NMResultsViewerTools.modelFeatureInspectionMatrixPayload(NM,v,ctx,payload.classifierIndex,selectedComponent);
                    if ~isempty(matrixDiagnostics)
                        needed = dCount + numel(matrixDiagnostics);
                        if needed > numel(diagnostics), diagnostics(needed + 4) = diagT; end
                        diagnostics(dCount+1:needed) = matrixDiagnostics;
                        dCount = needed;
                    end
                    if ~isempty(mx)
                        mxCount = mxCount + 1;
                        matrixPayloads(mxCount) = mx;
                        netCount = netCount + 1;
                        networkPayloads(netCount) = NMResultsViewerTools.modelFeatureInspectionNetworkPayload(mx, ctx);
                    end
                end
                if ~strcmp(ctx.featureKind,'tabular') && ~isempty(ctxMeasures)
                    for spatialMeasureIndex = 1:numel(ctxMeasures)
                        spCount = spCount + 1;
                        [spatialMaps(spCount), spatialDiagnostic] = ...
                            NMResultsViewerTools.modelFeatureInspectionSpatialPayload( ...
                            NM,v,ctx,ctxMeasures(spatialMeasureIndex),selectedComponent);
                        if ~isempty(spatialDiagnostic)
                            dCount=dCount+1;
                            if dCount>numel(diagnostics), diagnostics(dCount+4)=diagT; end
                            diagnostics(dCount)=spatialDiagnostic;
                        end
                    end
                end
                [nextCompRows, nextCompDiagnostics] = NMResultsViewerTools.modelFeatureInspectionComponentRows(v, ctx, maxComponents);
                if ~isempty(nextCompRows)
                    nComp = numel(nextCompRows);
                    rawComponentRows(compCount+1:compCount+nComp) = nextCompRows;
                    compCount = compCount + nComp;
                end
                if ~isempty(nextCompDiagnostics)
                    needed = dCount + numel(nextCompDiagnostics);
                    if needed > numel(diagnostics), diagnostics(needed + 4) = diagT; end
                    diagnostics(dCount+1:needed) = nextCompDiagnostics;
                    dCount = needed;
                end
            end

            if selectedCatalogueEntry.isCombined
                [combinedMatrix,combinedMatrixDiagnostics]=NMResultsViewerTools.modelFeatureInspectionCombinedRelationMatrixPayload( ...
                    A,catalogue,selectedCatalogueEntry,payload.classifierIndex,false,'');
                if ~isempty(combinedMatrix)
                    mxCount=mxCount+1;
                    matrixPayloads(mxCount)=combinedMatrix;
                    netCount=netCount+1;
                    networkPayloads(netCount)=NMResultsViewerTools.modelFeatureInspectionNetworkPayload( ...
                        combinedMatrix,struct('contextId',combinedMatrix.contextId));
                elseif isempty(combinedMatrixDiagnostics)
                    combinedMatrixDiagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', ...
                        'combined_relation_unavailable_for_feature_source', ...
                        'The selected combined Feature source has no available persisted CombinedRelation matrix.', ...
                        'CombinedRelation',selectedCatalogueEntry.contextId, ...
                        'getModelFeatureInspectionPayload','','');
                end
                if ~isempty(combinedMatrixDiagnostics)
                    needed=dCount+numel(combinedMatrixDiagnostics);
                    if needed>numel(diagnostics), diagnostics(needed+4)=diagT; end
                    diagnostics(dCount+1:needed)=combinedMatrixDiagnostics;
                    dCount=needed;
                end
            end

            measures = measures(1:mCount);
            featureRows = featureRows(1:fCount);
            matrixPayloads = matrixPayloads(1:mxCount);
            networkPayloads = networkPayloads(1:netCount);
            spatialMaps = spatialMaps(1:spCount);
            rawComponentRows = rawComponentRows(1:compCount);

            [componentAnalysis, componentDiagnostics] = NMResultsViewerTools.modelFeatureInspectionNormalizeFusionReport(A, catalogue(~[catalogue.isCombined]), payload.classifierIndex, maxComponents);
            fusionMode = NMResultsViewerTools.analysisFusionMode(A);
            if isempty(componentAnalysis.componentTable) && ~isempty(rawComponentRows) && ~ismember(fusionMode, {'early','intermediate'})
                % Preserve the pre-existing direct component summary only outside
                % early/intermediate fusion. Fusion statistics must come from the
                % authoritative Report contract and are never substituted after a
                % missing or malformed report.
                componentAnalysis.componentTable = rawComponentRows;
                componentAnalysis.ok = true;
                componentAnalysis.message = sprintf('Component-wise analysis contains %d context-scoped direct component row(s).', numel(rawComponentRows));
            end
            if ~isempty(componentDiagnostics)
                needed = dCount + numel(componentDiagnostics);
                if needed > numel(diagnostics), diagnostics(needed + 4) = diagT; end
                diagnostics(dCount+1:needed) = componentDiagnostics;
                dCount = needed;
            end
            diagnostics = diagnostics(1:dCount);

            payload.measures = measures;
            payload.featureTable = featureRows;
            payload.matrixPayloads = matrixPayloads;
            payload.networkPayloads = networkPayloads;
            payload.spatialMaps = spatialMaps;
            componentAnalysis.modalityComponentTable = rawComponentRows;
            componentAnalysis.ok = componentAnalysis.ok || ~isempty(rawComponentRows);
            if ~isempty(rawComponentRows)
                componentAnalysis.message = sprintf('%s Selected feature source contributes %d modality-specific component row(s).', ...
                    componentAnalysis.message, numel(rawComponentRows));
            end
            componentAnalysis.fractionatedDecisionAvailable = ...
                NMResultsViewerTools.modelFeatureInspectionFractionatedAvailable( ...
                A,selectedContexts,resultTargetIndex,payload.classifierIndex);
            payload.componentAnalysis = componentAnalysis;
            payload.diagnostics = diagnostics;
            [payload.scientificAnnotation,payload.resolvedSelection] = ...
                NMResultsViewerTools.modelFeatureInspectionScientificAnnotation( ...
                    NM,payload,selection,requestedMeasureId);
            payload.measureAnnotations = NMResultsViewerTools.modelFeatureInspectionMeasureAnnotations( ...
                payload.measures,payload.scientificAnnotation);
            payload.ok = ~isempty(payload.contexts) && (~isempty(payload.featureTable) || payload.componentAnalysis.ok || ~isempty(payload.matrixPayloads) || any([payload.spatialMaps.enabled]));
            if payload.ok
                if payload.backprojectionAvailable, componentPhrase=sprintf(', backprojected %s',payload.selectedBackprojectionComponentLabel); else, componentPhrase=''; end
                payload.message = sprintf('Model feature inspection payload built for "%s"%s with %d physical context(s), %d measure(s), and %d displayed feature row(s).', selectedCatalogueEntry.selectionLabel, componentPhrase, numel(payload.contexts), numel(payload.measures), numel(payload.featureTable));
                payload.title = 'Model feature inspection';
                if payload.backprojectionAvailable, payload.subtitle=sprintf('Analysis %d, target %d, feature source: %s, %s',idx,payload.targetIndex,selectedCatalogueEntry.selectionLabel,payload.selectedBackprojectionComponentLabel); else, payload.subtitle=sprintf('Analysis %d, target %d, feature source: %s',idx,payload.targetIndex,selectedCatalogueEntry.selectionLabel); end
                payload.summaryRows = NMResultsViewerTools.modelFeatureInspectionSummaryRows(payload);
            else
                payload.message = sprintf('Feature context "%s" is structurally available, but no supported feature, matrix, spatial or component rows could be extracted.', selectedCatalogueEntry.selectionLabel);
                payload.unsupportedPanels = {payload.message};
            end
        end

        function payload = getModelOptimizationPayload(NM, spec)
            if NMResultsViewerScientificCapability.isQuery(NM)
                P=@NMResultsViewerScientificCapability.provide;
                all=[P('optimization_payload','scientific_artefact','optimization','optimization_payload'), ...
                    P('optimization_selected_metric','scientific_artefact','optimization','selected_metric'), ...
                    P('optimization_cv_partitions','scientific_artefact','optimization','cv_partitions'), ...
                    P('optimization_metric_registry','scientific_artefact','optimization','metric_registry'), ...
                    P('optimization_parameter_grid','scientific_artefact','optimization','parameter_grid'), ...
                    P('optimization_metric_dashboard','visualization','',''), ...
                    P('optimization_sequence_diagnostics','visualization','',''), ...
                    P('optimization_parameter_surface','visualization','',''), ...
                    P('optimization_scatter_comparison','visualization','',''), ...
                    P('optimization_pareto_summary','visualization','','')];
                ids={all.id};
                % nm2-allow: ScientificCapability interrogation boundary omits context while availability passes the fixed payload context.
                if nargin == 2
                    q=spec.payload;
                    ids={};
                    if strcmp(q.kind,'model_optimization') && q.ok
                        ids={'optimization_payload'};
                        available=[q.metrics.available];
                        if any(available),ids{end+1}='optimization_metric_registry';end
                        hasPartition=q.partitions.cv1.ok || q.partitions.cv2.ok || q.partitions.complexity.ok || q.partitions.error.ok;
                        if hasPartition,ids{end+1}='optimization_cv_partitions';end
                        if isfield(q,'sequenceDiagnostics') && q.sequenceDiagnostics.available % nm2-allow: SEQOPT producer conditionally publishes sequenceDiagnostics only for trained eligible models.
                            ids{end+1}='optimization_sequence_diagnostics';
                        end
                        % Only a multi-row parameter grid can support comparisons across combinations.
                        if q.grid.nCombinations>1
                            if any(available),ids{end+1}='optimization_selected_metric';end
                            if sum(available)>1,ids{end+1}='optimization_metric_dashboard';end
                            if ~isempty(q.grid.parameterRows),ids{end+1}='optimization_parameter_grid';end
                            % nm2-allow: fixed optimization payload requires at least two writer-defined parameters for a surface plot.
                            if numel(q.grid.parameterNames)>=2 && ~isempty(q.grid.parameterRows),ids{end+1}='optimization_parameter_surface';end
                            if ~isempty(q.comparisons.compatibleMetricPairs) && any([q.comparisons.compatibleMetricPairs.enabled])
                                ids(end+1:end+2)={'optimization_scatter_comparison','optimization_pareto_summary'};
                            end
                        end
                    end
                end
                payload=NMResultsViewerScientificCapability.contract('model_optimization',{},NMResultsViewerScientificCapability.subset(all,ids));
                return;
            end
            % getModelOptimizationPayload  Build the read-only model-optimization registry payload.
            %
            % Completed analyses expose one canonical optimization representation:
            % analysis.GDdims is modality-indexed, GDdims{i}.Model owns parameter-grid
            % metadata, and GDdims{i}.grid owns persisted optimization measures. META is
            % a writer-conditioned late-fusion summary source. This method projects those
            % resident results into the fixed browser/API payload without re-discovering
            % their schema.
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            payload = NMResultsViewerTools.emptyPayload('model_optimization');
            payload.kind = 'model_optimization';
            payload.modelSources = NMResultsViewerTools.emptyModelOptimizationSources();
            payload.selectedModelSource = '';
            payload.context = NMResultsViewerTools.emptyModelOptimizationContext();
            payload.grid = NMResultsViewerTools.emptyModelOptimizationGrid();
            payload.metrics = NMResultsViewerTools.emptyModelOptimizationMetrics();
            payload.partitions = NMResultsViewerTools.emptyModelOptimizationPartitions();
            payload.comparisons = NMResultsViewerTools.emptyModelOptimizationComparisons();
            payload.optimizationCriterion = struct('key','','code',NaN,'label','','shortLabel','','metricId','', ...
                'scale',struct('mode','data','minimum',NaN,'maximum',NaN,'referenceValue',NaN,'referenceLabel',''));

            idx = spec.analysisIndex;
            payload.analysisIndex = idx;
            [available, availabilityMessage, availability] = NMResultsViewerTools.modelOptimizationAvailability(NM, idx, spec);
            payload.modelSources = availability.modelSources;
            payload.selectedModelSource = availability.selectedModelSource;
            payload.context = availability.context;
            payload.classifierIndex = availability.context.classifierIndex;
            payload.targetIndex = availability.context.targetIndex;
            % nm2-allow: public Results Viewer selector boundary may carry no valid analysis selection.
            if idx >= 1 && idx <= numel(NM.analysis)
                payload.optimizationCriterion = NMResultsViewerTools.modelOptimizationCriterionIdentity(NM,idx);
            end
            payload.grid = availability.grid;
            rawMetrics = availability.metrics;
            rawPartitions = availability.partitions;
            payload.metrics = NMResultsViewerTools.jsonSafeModelOptimizationMetrics(rawMetrics);
            payload.partitions = NMResultsViewerTools.jsonSafeModelOptimizationPartitions(rawPartitions);
            payload.comparisons = availability.comparisons;
            if available && strcmp(NM.analysis{idx}.params.TrainParam.SVM.prog,'SEQOPT') && ~availability.context.isMultiClass
                payload.sequenceDiagnostics = NMResultsViewerTools.sequenceDiagnosticView(NM,idx,availability.context);
                payload.sequenceDiagnostics.candidates = NMResultsViewerTools.sequenceCandidateChoices( ...
                    rawMetrics, payload.grid, NM.analysis{idx}.params.TrainParam.SVM.GridParam);
            end
            payload.title = availability.title;
            payload.subtitle = availability.subtitle;
            payload.summaryRows = NMResultsViewerTools.modelOptimizationSummaryRows(rawMetrics);
            payload.optimizationRows = NMResultsViewerTools.modelOptimizationParameterRows(availability.grid, rawMetrics);
            payload.scoreRows = [];
            payload.unsupportedPanels = {};
            payload.ok = logical(available);
            payload.message = availabilityMessage;
            if available
                payload.scientificAnnotation=NMResultsViewerTools.scientificResultAnnotation(NM,payload);
            else
                payload.unsupportedPanels = {availabilityMessage};
            end
        end

        function payload = getClassificationPayload(NM, spec)
            if NMResultsViewerScientificCapability.isQuery(NM)
                % nm2-allow: Scientific Capability registry query boundary permits an omitted context argument.
                if nargin<2, spec=struct(); end
                payload=NMResultsViewerTools.performanceScientificCapability('classification_payload','classification',spec); return;
            end
            % getClassificationPayload  Build binary-classification plot payloads.
            %
            % payload = NMResultsViewerTools.getClassificationPayload(NM, spec)
            % resolves the selected analysis/classifier/target/source, extracts
            % labels, predictions, decision/probability vectors and display
            % metadata, and returns the browser-ready classification payload.
            %
            % spec.resultType: supplies the result type value in the public API/import specification.
            doProfile = NMResultsViewerTools.profileEnabled(spec);
            tClassificationTotal = tic;
            payload = NMResultsViewerTools.emptyPayload('classification');

            if isstruct(spec)
                spec.resultType = 'classification';
            end
            [viewerOpts,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            idx = viewerOpts.analysisIndex;
            clsIdx = viewerOpts.classifierIndex;
            targetIdx = viewerOpts.targetIndex;
            source = viewerOpts.source;
            graphType = spec.graphType;
            payload = NMResultsViewerTools.attachPayloadSource(payload, source);

            [isOOCVSource, localOOCVIndex] = NMResultsViewerTools.parseOOCVSourceId(source);

            % nm2-allow: Results Viewer request boundary validates the browser-selected analysis index before internal materialization.
            if isnan(idx) || idx < 1 || idx > numel(NM.analysis)
                payload.message = 'Select a completed analysis to inspect classification results.';
                return;
            end

            viewerOpts.resultType = 'classification';
            tLegacyState = tic;
            if isOOCVSource
                [ok, handles, msg] = NMResultsViewerTools.buildLegacyOOCVViewerState(NM, idx, targetIdx, graphType, viewerOpts, localOOCVIndex);
            else
                [ok, handles, msg] = NMResultsViewerTools.buildLegacyViewerState(NM, idx, targetIdx, graphType, viewerOpts);
            end
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       classification legacy viewer materialization: %.3fs\n', toc(tLegacyState));
            if ~ok
                payload.message = msg;
                return;
            end
            % buildLegacyViewerState admits only result containers that satisfy the selected
            % Model Performance family and CV2-grid availability contract.

            nCls = numel(handles.BinClass);
            if isOOCVSource && round(double(clsIdx)) > nCls
                clsIdx = 1;
            end
            clsIdx = max(1, min(double(clsIdx), nCls));
            tDiscovery = tic;
            if isOOCVSource
                try
                    [payload, handles] = NMResultsViewerTools.discoveryClassOOCVPayloadFromHandles(payload, handles, clsIdx, graphType, NM, viewerOpts); %#ok<ASGLU>
                catch ME
                    payload.ok = false;
                    payload.message = sprintf('OOCV payload extraction failed in display_classplot_oocv-compatible branch (%s): %s', ME.identifier, ME.message);
                    payload.classPlot = struct('ok',false,'points',[],'message',payload.message);
                    payload.roc = struct('ok',false,'points',[],'auc',NaN,'message','OOCV payload extraction failed; ROC is unavailable.');
                    payload.confusion = struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{{}},'message','OOCV payload extraction failed; contingency matrix is unavailable.');
                    payload.pies = struct('ok',false,'charts',[],'message','OOCV payload extraction failed; pie charts are unavailable.');
                    payload.scoreRows = [];
                    payload.oocv = struct('ok',false,'message',payload.message);
                    payload = NMResultsViewerTools.enforceOOCVPayloadInvariant(payload, source);
                    return;
                end
            else
                [payload, handles] = NMResultsViewerTools.discoveryClassPayloadFromHandles(payload, handles, clsIdx, graphType); %#ok<ASGLU>
            end
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       classification browser payload extraction:     %.3fs\n', toc(tDiscovery));
            payload.ok = true;
            payload.analysisIndex = idx;
            payload.classifierIndex = clsIdx;
            payload.targetIndex = targetIdx;
            payload.selectedModelSource = handles.modelSource;
            payload.selectedModelSourceLabel = handles.modelSourceLabel;
            payload.title = NMResultsViewerTools.analysisTitle(NM.analysis{idx}, idx);
            payload.subtitle = handles.BinClass{clsIdx}.description;
            if isOOCVSource
                payload = NMResultsViewerTools.enforceOOCVPayloadInvariant(payload, source);
                payload.message = sprintf('Legacy-compatible binary OOCV classification payload extracted from display_classplot_oocv semantics for analysis %d, binary classifier %d.', idx, clsIdx);
            else
                payload.message = sprintf('Legacy-compatible classification payload extracted from load_GDdims/display_classplot semantics for analysis %d, binary classifier %d.', idx, clsIdx);
                tPermutation = tic;
                payload.modelPermutation = ...
                    NMResultsViewerTools.modelPerformancePermutationPayloadImpl( ...
                    NM, idx, targetIdx, clsIdx, handles.modelSource);
                
                payload.modelPermutationAvailability = ...
                    NMResultsViewerTools.modelPerformancePermutationAvailabilityImpl( ...
                    NM, idx, targetIdx, handles.modelSource);

                NMResultsViewerTools.profileLog(doProfile, ...
                    '[nm-prof]       classification permutation metadata:         %.3fs\n', toc(tPermutation));
            end
            tAnnotation = tic;
            payload.scientificAnnotation=NMResultsViewerTools.scientificResultAnnotation(NM,payload);
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       classification scientific annotation:          %.3fs\n', toc(tAnnotation));
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]     classification payload subphases TOTAL:       %.3fs\n', toc(tClassificationTotal));
        end

        function payload = getRegressionPayload(NM, spec)
            if NMResultsViewerScientificCapability.isQuery(NM)
                if nargin<2, spec=struct(); end
                payload=NMResultsViewerTools.performanceScientificCapability('regression_payload','regression',spec); return;
            end
            % GETREGRESSIONPAYLOAD  Build regression plot payloads.
            %
            %   payload = NMResultsViewerTools.getRegressionPayload(NM, spec)
            %   resolves the selected analysis/model/target/source, extracts
            %   observed and predicted continuous outcomes and display metadata,
            %   and returns the browser-ready regression payload.
            if nargin < 2 || isempty(spec), spec = struct(); end
            payload = NMResultsViewerTools.emptyPayload('regression');

            [viewerOpts,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            idx = viewerOpts.analysisIndex;
            targetIdx = viewerOpts.targetIndex;
            graphType = spec.graphType;
            graphType = max(1, min(3, round(double(graphType))));
            source = viewerOpts.source;
            [isOOCVSource, globalOOCVIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            viewerOpts.resultType = 'regression';
            payload = NMResultsViewerTools.attachPayloadSource(payload, source);

            if isnan(idx) || idx < 1 || ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || idx > numel(NM.analysis)
                payload.message = 'Select a completed regression analysis to inspect regression results.';
                return;
            end
            if isOOCVSource
                [ok, handles, msg] = NMResultsViewerTools.buildLegacyOOCVViewerState(NM, idx, targetIdx, graphType, viewerOpts, globalOOCVIndex);
            else
                [ok, handles, msg] = NMResultsViewerTools.buildLegacyViewerState(NM, idx, targetIdx, graphType, viewerOpts);
            end
            if ~ok
                payload.message = msg;
                return;
            end
            thresholdText = spec.binarizationThreshold;
            if isOOCVSource
                [payload, handles] = NMResultsViewerTools.discoveryRegressionOOCVPayloadFromHandles(payload, handles, graphType, thresholdText); %#ok<ASGLU>
            else
                [payload, handles] = NMResultsViewerTools.discoveryRegressionPayloadFromHandles(payload, handles, graphType, thresholdText); %#ok<ASGLU>
            end
            payload.analysisIndex = idx;
            payload.targetIndex = targetIdx;
            payload.selectedModelSource = handles.modelSource;
            payload.selectedModelSourceLabel = handles.modelSourceLabel;
            payload.title = NMResultsViewerTools.analysisTitle(NM.analysis{idx}, idx);
            payload.subtitle = 'Regression model';
            payload.ok = true;
            if isOOCVSource
                payload.message = sprintf('Legacy-compatible regression OOCV payload extracted from display_regrplot/display_regrplot_oocv_labels_unknown semantics for analysis %d, target %d.', idx, targetIdx);
                payload.unsupportedPanels = {'Model optimization, model visualization and model-comparison workspaces are intentionally deferred.'};
            else
                payload.message = sprintf('Legacy-compatible regression payload extracted from load_GDdims/display_regrplot semantics for analysis %d, target %d.', idx, targetIdx);
                payload.unsupportedPanels = {'Model optimization, model visualization and model-comparison workspaces are intentionally deferred.'};
                payload.modelPermutation = ...
                    NMResultsViewerTools.modelPerformancePermutationPayloadImpl( ...
                    NM, idx, targetIdx, 1, handles.modelSource);
                
                payload.modelPermutationAvailability = ...
                    NMResultsViewerTools.modelPerformancePermutationAvailabilityImpl( ...
                    NM, idx, targetIdx, handles.modelSource);
            end
            payload.scientificAnnotation=NMResultsViewerTools.scientificResultAnnotation(NM,payload);
        end

        function payload = getMultiClassPayload(NM, spec)
            if NMResultsViewerScientificCapability.isQuery(NM)
                % nm2-allow: Scientific Capability registry interrogation deliberately omits the context argument.
                if nargin < 2, spec = struct(); end
                payload = NMResultsViewerTools.performanceScientificCapability('multiclass_payload','multiclass',spec);
                return;
            end
            % GETMULTICLASSPAYLOAD  Build multi-class result payloads.
            payload = NMResultsViewerTools.emptyPayload('multiclass');

            [viewerOpts,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            idx = viewerOpts.analysisIndex;
            targetIdx = viewerOpts.targetIndex;
            source = viewerOpts.source;
            [isOOCVSource, globalOOCVIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            graphType = spec.graphType;
            viewerOpts.resultType = 'multiclass';

            payload = NMResultsViewerTools.attachPayloadSource(payload, source);
            % nm2-allow: public Results Viewer request boundary validates the browser-selected completed-analysis index.
            if isnan(idx) || idx < 1 || idx > numel(NM.analysis)
                payload.message = 'Select a completed multi-class analysis to inspect multi-class results.';
                return;
            end
            [gdOk, GD, ~, gdMsg] = NMResultsViewerTools.resultGDForSpec(NM, idx, 'multiclass', spec);
            if ~gdOk
                payload.message = gdMsg;
                return;
            end
            modes = NMResultsViewerTools.multiClassModeOptions(NM, idx, spec);
            payload.selectedMultiClassModeIndex = NMResultsViewerTools.selectedMultiClassModeIndex(modes, spec);
            payload.classifierIndex = NMResultsViewerTools.legacyPopupValue(GD, 'multiclass', 1);

            if isOOCVSource
                [ok, handles, msg] = NMResultsViewerTools.buildLegacyOOCVViewerState(NM, idx, targetIdx, graphType, viewerOpts, globalOOCVIndex);
                if ~ok
                    payload.message = msg;
                    return;
                end
                [payload, handles] = NMResultsViewerTools.oocvMultiClassPayloadFromHandles(payload, handles); %#ok<ASGLU>
                payload.analysisIndex = idx;
                payload.targetIndex = targetIdx;
                payload.title = NMResultsViewerTools.analysisTitle(NM.analysis{idx}, idx);
                payload.subtitle = 'Multi-group classifier OOCV/application results';
                payload.ok = true;
                payload.message = sprintf('Multi-class OOCV payload extracted from the transformed MultiResults/MultiClass state for analysis %d, target %d.', idx, targetIdx);
                payload.unsupportedPanels = {};
                payload.scientificAnnotation = NMResultsViewerTools.scientificResultAnnotation(NM,payload);
                return;
            end

            [ok, handles, msg] = NMResultsViewerTools.buildLegacyViewerState(NM, idx, targetIdx, graphType, viewerOpts);
            if ~ok
                payload.message = msg;
                return;
            end
            [payload, handles] = NMResultsViewerTools.discoveryMultiClassPayloadFromHandles(payload, handles, payload.selectedMultiClassModeIndex); %#ok<ASGLU>
            payload.analysisIndex = idx;
            payload.targetIndex = targetIdx;
            payload.selectedModelSource = handles.modelSource;
            payload.selectedModelSourceLabel = handles.modelSourceLabel;
            payload.title = NMResultsViewerTools.analysisTitle(NM.analysis{idx}, idx);
            payload.subtitle = 'Multi-group classifier';
            payload.ok = true;
            if payload.selectedMultiClassModeIndex <= 1
                payload.message = sprintf('Multi-class payload extracted from the transformed load_GDdims state for analysis %d, target %d.', idx, targetIdx);
            else
                payload.message = sprintf('Class-vs-REST payload extracted for %s.', payload.selectedMultiClassModeLabel);
            end
            payload.unsupportedPanels = {'Model optimization, model visualization, ML interpretation and model-comparison workspaces are intentionally deferred.'};
            payload.modelPermutation = ...
                NMResultsViewerTools.modelPerformancePermutationPayloadImpl( ...
                NM, idx, targetIdx, payload.selectedMultiClassModeIndex, handles.modelSource);
            
            payload.modelPermutationAvailability = ...
                NMResultsViewerTools.modelPerformancePermutationAvailabilityImpl( ...
                NM, idx, targetIdx, handles.modelSource);
            payload.scientificAnnotation = NMResultsViewerTools.scientificResultAnnotation(NM,payload);
        end

        function out = getSubjectFeatureQC(NM, spec, tmpDir)
            if nargin>=1 && NMResultsViewerScientificCapability.isQuery(NM)
                p=[NMResultsViewerScientificCapability.provide('subject_feature_qc','scientific_artefact','quality_control','subject_feature_qc'), ...
                    NMResultsViewerScientificCapability.provide('subject_feature_qc_view','visualization','','')];
                if nargin>=2&&isstruct(spec)&&isfield(spec,'payload')
                    q=spec.payload; available=isstruct(q)&&isfield(q,'subjectQCScalars')&&isstruct(q.subjectQCScalars)&& ...
                        isfield(q.subjectQCScalars,'featureLevelAvailable')&&logical(q.subjectQCScalars.featureLevelAvailable);
                    if ~available,p=p([]);end
                end
                out=NMResultsViewerScientificCapability.contract('subject_feature_qc',{{'subject_qc_scalars'}},p); return;
            end
            % getSubjectFeatureQC  Return on-demand subject feature-level QC data.
            %
            % out = NMResultsViewerTools.getSubjectFeatureQC(NM, spec, tmpDir)
            % resolves the selected subject/modality/QC metric and returns a lazy
            % browser payload for feature-level QC inspection, including image or
            % matrix/vector display metadata. Full feature-level QC remains loaded
            % on demand rather than in the startup payload.
            %
            % Authority and materialization:
            %   Feature-space QC and canonical provenance select the adapter. ROI spatial inspection
            %   consumes the resident QC sidecar and analysis-bound NM.Y only; this dispatcher must
            %   not rematerialize ROI sources or atlas geometry during subject navigation.
            %
            % The registered UI requestSpec producer supplies canonical QC
            % selection fields; the scientific capability query is independent.
            emptyStruct = struct();
            out = struct('ok',false, 'message','Subject feature-level QC was not retrieved.', ...
                'caseId','', 'modalityIndex',NaN, 'modalityLabel','', 'metricKey','subject_z', ...
                'featureSpace','', 'viewerKind','', 'rows',[], 'columns',[], ...
                'nReturned',0, 'source','', 'metricOptions',[], 'metricLabel','', ...
                'volume',emptyStruct, 'overlay',emptyStruct, 'mesh',emptyStruct, 'connectivity',emptyStruct, ...
                'referenceInfo',struct('subjectSource','', 'referenceSource','', 'referenceMode','', 'message','', 'warning',''));
            try
                requestCaseId = spec.caseId;
                if isempty(requestCaseId)
                    out.message = 'No subject ID was supplied for feature-level QC retrieval.';
                    return;
                end
                out.caseId = requestCaseId;
                metricKey = spec.metricKey;
                out.metricKey = metricKey;
                [modIdx, modMsg] = NMResultsViewerTools.singleAnalysisBoundModalityIndex(NM, spec);
                if isnan(modIdx)
                    out.message = modMsg;
                    return;
                end
                out.modalityIndex = double(modIdx);
                out.modalityLabel = NMResultsViewerTools.modalityLabel(NM, modIdx);
                if ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || modIdx < 1 || modIdx > numel(NM.datadescriptor)
                    out.message = 'Feature-level QC cannot be shown because the analysis-bound modality could not be resolved in the training dataset.';
                    return;
                end
                refDD = NM.datadescriptor{modIdx};
                qc = NMResultsViewerTools.qcPayloadFromDescriptor(refDD);
                if isempty(fieldnames(qc))
                    out.message = sprintf('Feature-level QC cannot be shown because the training/CV QC reference for modality %d has not been saved. Export QC for the training modality first.', modIdx);
                    return;
                end
                source = spec.source;
                [isOOCVSource, oocvIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
                subjectNM = NM;
                subjectDD = refDD;
                referenceMode = 'leave_one_out';
                if isOOCVSource
                    [subjectNM, subjectDD, rowIdx, oocvMsg] = NMResultsViewerTools.resolveOOCVSubjectFeatureQCTarget(NM, modIdx, oocvIndex, requestCaseId);
                    if isempty(rowIdx) || ~isfinite(double(rowIdx)) || rowIdx < 1
                        out.message = oocvMsg;
                        return;
                    end
                    referenceMode = 'fixed_reference';
                else
                    caseIds = NMResultsViewerTools.qcCaseIds(qc);
                    rowIdx = find(strcmp(caseIds(:), requestCaseId), 1, 'first');
                    if isempty(rowIdx)
                        out.message = 'The selected training/CV subject could not be matched to the persisted QC data. Matching uses the unique subject ID; no visual-order fallback was used.';
                        return;
                    end
                end
                referenceInfo = NMResultsViewerTools.featureQCReferenceInfo(referenceMode, isOOCVSource, oocvIndex, modIdx);
                [compatOK, compatMsg, compatWarn] = NMResultsViewerTools.featureQCReferenceCompatibility(qc, refDD, subjectDD, isOOCVSource);
                out.referenceInfo = referenceInfo;
                if ~compatOK
                    out.message = compatMsg;
                    out.referenceInfo = referenceInfo;
                    return;
                end
                if ~isempty(compatWarn)
                    out.referenceInfo.warning = compatWarn;
                end

                featureSpace = NMResultsViewerTools.featureQCFeatureSpace(qc, refDD);
                out.featureSpace = featureSpace;
                out.metricOptions = NMResultsViewerTools.featureQCMetricOptions(qc, featureSpace);

                % The feature-space authority selects one science adapter; the
                % browser-facing response envelope is common to all spatial paths.
                if strcmpi(featureSpace, 'roi_field')
                    spatialOut = NMResultsViewerTools.subjectROIFeatureQCOverlay(subjectNM, qc, modIdx, rowIdx, spec, tmpDir, referenceMode);
                    hasMetricOptions = true;
                elseif strcmpi(featureSpace, 'image_voxel')
                    spatialOut = NMResultsViewerTools.subjectImageFeatureQCOverlay(subjectNM, subjectDD, qc, modIdx, rowIdx, spec, tmpDir, referenceMode);
                    hasMetricOptions = true;
                elseif strcmpi(featureSpace, 'surface_vertex_registered') || strcmpi(featureSpace, 'surface_vertex') || contains(lower(featureSpace), 'surface')
                    spatialOut = NMResultsViewerTools.subjectSurfaceFeatureQCOverlay(subjectNM, subjectDD, qc, modIdx, rowIdx, spec, tmpDir, referenceMode);
                    hasMetricOptions = true;
                elseif strcmpi(featureSpace, 'connectivity_edges') || contains(lower(featureSpace), 'connectivity')
                    spatialOut = NMResultsViewerTools.subjectConnectivityFeatureQCMatrix(subjectNM, subjectDD, qc, modIdx, rowIdx, spec, referenceMode);
                    hasMetricOptions = false;
                elseif ~strcmpi(featureSpace, 'tabular_matrix')
                    if isempty(featureSpace), featureSpaceLabel = 'unresolved'; else, featureSpaceLabel = featureSpace; end
                    out.message = sprintf(['Feature-level QC domain %s is not an explicit tabular_matrix domain and has no successful spatial adapter. ' ...
                        'The Results Viewer will not reinterpret spatial or unknown feature provenance as a feature table.'], featureSpaceLabel);
                    return;
                end
                if ~strcmpi(featureSpace, 'tabular_matrix')
                    if spatialOut.ok
                        fns = fieldnames(spatialOut);
                        for ii = 1:numel(fns), out.(fns{ii}) = spatialOut.(fns{ii}); end
                        out.caseId = requestCaseId;
                        out.modalityIndex = double(modIdx);
                        out.modalityLabel = NMResultsViewerTools.modalityLabel(NM, modIdx);
                        out.referenceInfo = referenceInfo;
                        if hasMetricOptions && isempty(out.metricOptions)
                            out.metricOptions = NMResultsViewerTools.featureQCMetricOptions(qc, featureSpace);
                        end
                    else
                        out.message = spatialOut.message;
                        end
                    return;
                end

                maxFeatures = spec.maxFeatures;
                maxFeatures = max(20, min(2000, round(maxFeatures)));
                [rows, cols, msg, source] = NMResultsViewerTools.subjectFeatureQCRows(qc, rowIdx, maxFeatures, tmpDir, subjectNM, modIdx, referenceMode);
                out.rows = rows;
                out.columns = cols;
                out.nReturned = double(numel(rows));
                out.source = source;
                out.ok = ~isempty(rows);
                out.viewerKind = 'feature_qc_table';
                out.referenceInfo = referenceInfo;
                if out.ok
                    out.message = sprintf('Retrieved %d subject-specific feature-level QC row(s) for %s.', numel(rows), requestCaseId);
                else
                    out.message = msg;
                end
            catch ME
                out.ok = false;
                out.message = sprintf('Feature-level QC could not be prepared: %s', ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
            end
        end

        function [payload, NM, didPersist] = getClassificationActionPayload(NM, spec)
            if NMResultsViewerScientificCapability.isQuery(NM)
                P = @NMResultsViewerScientificCapability.provide;
                provides = [P('probability_analysis','scientific_artefact','performance','probability_analysis'), ...
                    P('calibration_analysis','scientific_artefact','performance','calibration_analysis'), ...
                    P('decision_curve_analysis','scientific_artefact','performance','decision_curve_analysis'), ...
                    P('probability_view','visualization','',''),P('calibration_curve','visualization','',''), ...
                    P('decision_curve','visualization','','')];
                % nm2-allow: Scientific State owns this fixed capability-context envelope; interrogation may omit it.
                if nargin == 2
                    q = spec.payload;
                    keep = any(strcmp(q.kind, {'classification','multiclass'}));
                    if strcmp(q.kind,'regression')
                        keep = isfield(spec.spec,'binarizationEnabled') && logical(spec.spec.binarizationEnabled); % nm2-allow: ScientificCapability.isQuery creates optional classifier capability metadata; absent regression flag means binarization disabled.
                    end
                    if keep && strcmp(q.sourceKind,'oocv') && ~logical(q.oocv.labelsKnown)
                        provides = NMResultsViewerScientificCapability.subset(provides,{'probability_analysis','probability_view'});
                    elseif ~keep
                        provides = provides([]);
                    end
                end
                payload = NMResultsViewerScientificCapability.contract('performance_actions',{{'performance_payload'}},provides);
                return;
            end
            % GETCLASSIFICATIONACTIONPAYLOAD  Build derived classification action views.
            [viewerOpts,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            didPersist = false;
            payload = struct('ok',false,'kind','classification_action','action','', ...
                'message','','title','','method','none','methodLabel','No Calibration', ...
                'didPersistProbability',false,'probability',struct(),'calibration',struct(),'dca',struct());

            idx = spec.analysisIndex;
            clsIdx = spec.classifierIndex;
            targetIdx = spec.targetIndex;
            resultKind = NMResultsViewerTools.normalizeResultType(spec.resultType);
            % nm2-allow: public action request boundary accepts documented action spelling/case variants.
            action = spec.action;
            switch action
                case {'model_permutation','modelperm','permutation'}
                    [payload, NM, didPersist] = NMResultsViewerTools.getModelPermutationActionPayload(NM, spec);
                    return;
                case 'calib'
                    action = 'calibration';
                case {'probability','calibration','dca'}
                otherwise
                    error('NMResultsViewerTools:UnknownClassificationAction', ...
                        'Unknown classification action: %s.', action);
            end
            if strcmp(resultKind, 'regression')
                [payload, NM, didPersist] = NMResultsViewerTools.getRegressionBinarizationActionPayload(NM, spec);
                return;
            end
            graphType = spec.graphType;
            source = spec.source;
            % nm2-allow: public calibration request boundary canonicalizes the documented method token.
            method = spec.calibrationMethod;
            forceRecomputeProbability = spec.forceRecomputeProbability;
            payload.action = action;
            payload.method = method;
            payload.methodLabel = NMResultsViewerTools.calibrationMethodLabel(method);

            [isOOCVActionSource, actionOOCVGlobalIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            % nm2-allow: public Results Viewer request boundary validates the browser-selected completed-analysis index.
            if isnan(idx) || idx < 1 || idx > numel(NM.analysis)
                payload.message = 'Select a completed analysis before opening a probability, calibration or DCA panel.';
                return;
            end

            viewerOpts.resultType = resultKind;
            viewerOpts.probMethod = method;
            if isOOCVActionSource
                [ok, handles, msg] = NMResultsViewerTools.buildLegacyOOCVViewerState(NM, idx, targetIdx, graphType, viewerOpts, actionOOCVGlobalIndex);
            else
                [ok, handles, msg] = NMResultsViewerTools.buildLegacyViewerState(NM, idx, targetIdx, graphType, viewerOpts);
            end
            if ~ok
                payload.message = msg;
                return;
            end

            if strcmp(resultKind,'multiclass')
                [payload, handled] = NMResultsViewerTools.multiClassOvRActionPayloadFromHandles(payload, handles, spec, action, method);
                if ~handled
                    error('NMResultsViewerTools:UnsupportedMultiClassAction', ...
                        'The requested multi-class action was not materialized.');
                end
                return;
            end

            nBin = numel(handles.BinClass);
            clsIdx = round(double(clsIdx));
            if clsIdx < 1 || clsIdx > nBin
                error('NMResultsViewerTools:InvalidClassifierIndex', ...
                    'Classifier index %g is outside the produced binary-classifier axis 1:%d.', clsIdx, nBin);
            end

            if isOOCVActionSource
                [labels01, probs, rawScores, labelsOOCV, probsOOCV, rawScoresOOCV, panelTitle, methodOut, probMsg, persistInfo] = ...
                    NMResultsViewerTools.classificationProbabilitiesFromOOCVHandles(handles, clsIdx, method, forceRecomputeProbability);
                activeLabels = labelsOOCV; activeProbs = probsOOCV; activeScores = rawScoresOOCV;
                referenceLabels = labels01; referenceProbs = probs; referenceScores = rawScores;
                activeLabel = 'OOCV'; referenceLabel = 'Discovery/CV';
            else
                [labels01, probs, rawScores, panelTitle, methodOut, probMsg, persistInfo] = ...
                    NMResultsViewerTools.classificationProbabilitiesFromHandles(handles, clsIdx, method, forceRecomputeProbability);
                activeLabels = labels01; activeProbs = probs; activeScores = rawScores;
                referenceLabels = []; referenceProbs = []; referenceScores = [];
                activeLabel = 'Discovery/CV'; referenceLabel = '';
            end
            payload.method = methodOut;
            payload.methodLabel = NMResultsViewerTools.calibrationMethodLabel(methodOut);
            payload.title = panelTitle;
            payload.probability = NMResultsViewerTools.probabilitySummaryPayload(activeLabels, activeProbs, activeScores, panelTitle, methodOut);
            payload.probability.activeLabel = activeLabel;
            payload.probability.activeVectors = NMResultsViewerTools.probabilityVectorPayload(activeLabels, activeProbs, activeScores, activeLabel);
            if isOOCVActionSource
                payload.probability.referenceLabel = referenceLabel;
                payload.probability.referenceVectors = NMResultsViewerTools.probabilityVectorPayload(referenceLabels, referenceProbs, referenceScores, referenceLabel);
            end

            switch action
                case 'calibration'
                    numBins = round(spec.numBins);
                    numBins = max(3, min(50, numBins));
                    smoothCurve = spec.smoothCurve;
                    metric = spec.calibrationMetric;
                    payload.calibration = NMResultsViewerTools.calibrationCurvePayload(activeLabels, activeProbs, numBins, smoothCurve, metric, panelTitle, methodOut);
                    payload.calibration.activeLabel = activeLabel;
                    if isOOCVActionSource
                        payload.calibration.referenceCurve = NMResultsViewerTools.calibrationCurvePayload(referenceLabels, referenceProbs, numBins, smoothCurve, metric, panelTitle, methodOut);
                        payload.calibration.referenceCurve.label = referenceLabel;
                        payload.calibration.referenceCurve.color = '#64748b';
                        payload.calibration.hasReferenceCurve = true;
                        payload.calibration.referenceLabel = referenceLabel;
                    end
                case 'dca'
                    maxProb = spec.maxProb;
                    stepSize = spec.stepSize;
                    if isnan(maxProb) || maxProb <= 0 || maxProb > 1
                        maxProb = NMResultsViewerTools.initialDcaMaxProbability(activeLabels, activeProbs);
                    end
                    maxProb = max(0.05, min(1, maxProb));
                    stepSize = max(0.005, min(0.2, stepSize));
                    payload.dca = NMResultsViewerTools.dcaPayload(activeLabels, activeProbs, referenceLabels, referenceProbs, maxProb, stepSize, panelTitle, methodOut);
                    payload.dca.activeLabel = activeLabel;
                    payload.dca.referenceLabel = referenceLabel;
                    payload.dca.activeVectors = NMResultsViewerTools.probabilityVectorPayload(activeLabels, activeProbs, activeScores, activeLabel);
                    if isOOCVActionSource
                        payload.dca.referenceVectors = NMResultsViewerTools.probabilityVectorPayload(referenceLabels, referenceProbs, referenceScores, referenceLabel);
                    end
            end

            [NM, didPersist] = NMResultsViewerTools.persistClassificationProbabilityArtifact(NM, idx, clsIdx, source, persistInfo, methodOut, forceRecomputeProbability);
            payload.didPersistProbability = logical(didPersist);
            payload.action = action;
            payload.ok = true;
            if didPersist
                payload.message = sprintf('%s Probability scores were persisted into the selected NeuroMiner result container.', probMsg);
            else
                payload.message = probMsg;
            end
            fprintf('[NMResultsViewer] %s\n', payload.message);
        end

        function [payload, NM, didPersist] = getModelPermutationActionPayload(NM, spec)
            % getModelPermutationActionPayload  Return model-level permutation histogram rows for the active performance context.
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            didPersist = false;
            payload = struct('ok',false,'kind','model_permutation_action','action','model_permutation', ...
                'message','No model-level permutation histogram payload is available for the selected context.', ...
                'modelPermutation',NMResultsViewerTools.modelPerformancePermutationPayloadTemplate(), ...
                'modelPermutationAvailability',struct('ok',false,'message','Not checked.','paths',{{}}, ...
                    'targetIndex',NaN,'resultTargetIndex',NaN));
            idx = spec.analysisIndex;
            targetIdx = spec.targetIndex;
            classIdx = spec.classifierIndex;
            resultKind = NMResultsViewerTools.normalizeResultType(spec.resultType);
            if strcmp(resultKind, 'multiclass')
                classIdx = spec.multiClassModeIndex;
            end
            % nm2-allow: browser action boundary validates the requested completed-analysis index
            if isnan(idx) || idx < 1 || idx > numel(NM.analysis)
                payload.message = 'Select a completed analysis before opening the model permutation panel.';
                return;
            end
            sources = NMResultsViewerTools.modelSourcesForAnalysis(NM, idx, resultKind, spec);
            selectedModelSource = NMResultsViewerTools.selectedModelSourceId(sources, spec);
            payload.modelPermutationAvailability = ...
                NMResultsViewerTools.modelPerformancePermutationAvailabilityImpl( ...
                NM, idx, targetIdx, selectedModelSource);
            
            payload.modelPermutation = ...
                NMResultsViewerTools.modelPerformancePermutationPayloadImpl( ...
                NM, idx, targetIdx, classIdx, selectedModelSource);

            rows = payload.modelPermutation.rows;
            payload.ok = ~isempty(rows);
            payload.message = payload.modelPermutation.message;
            if ~payload.ok && isempty(payload.message)
                payload.message = payload.modelPermutationAvailability.message;
            end
        end

        function [payload, handled] = multiClassOvRActionPayloadFromHandles(payload, handles, spec, action, method) %#ok<INUSD>
            % MULTICLASSOVRACTIONPAYLOADFROMHANDLES  Materialize actions from the K-class probability writer.
            handled = true;
            source = spec.source;
            [isOOCVSource, ~] = NMResultsViewerTools.parseOOCVSourceId(source);
            labelsKnown = true;
            if isOOCVSource
                [~, probabilities, labels, ~, ~, groupNames, colors, labelsKnown, K, oocvind] = ...
                    NMResultsViewerTools.oocvMultiClassVectorsFromHandles(handles);
                N = size(probabilities,1);
                [~, subgroupMask] = NMResultsViewerTools.multiClassOOCVSubgroupSelection(handles, oocvind, N);
                if ~any(subgroupMask)
                    payload.message = 'The selected OOCV subgroup contains no cases for the requested multi-class action.';
                    return;
                end
                probabilities = probabilities(subgroupMask,:);
                labels = labels(subgroupMask);
                sourceLabel = 'OOCV';
            else
                MC = handles.MultiClass;
                probabilities = double(MC.probabilities);
                labels = double(MC.labels(:));
                K = size(probabilities,2);
                % nm2-allow: load_GDdims fixes transformed probabilities and labels on one case axis
                if size(probabilities,1) ~= numel(labels)
                    error('NMResultsViewerTools:MultiClassProbabilityAxisMismatch', ...
                        'Transformed multi-class probabilities and labels must share one case axis.');
                end
                groupNames = NMResultsViewerTools.multiClassGroupNames(handles, K);
                colors = NMResultsViewerTools.multiClassColors(handles, K);
                sourceLabel = 'Discovery/CV';
            end
            modeIdx = round(double(spec.multiClassModeIndex));
            if modeIdx < 1 || modeIdx > K + 1
                error('NMResultsViewerTools:InvalidMultiClassModeIndex', ...
                    'Multi-class mode index %g is outside the produced selector axis 1:%d.', modeIdx, K+1);
            end
            selectedClass = modeIdx - 1;
            classList = 1:K;
            if selectedClass >= 1, classList = selectedClass; end

            % nk_MultiPerfComp/nk_ConvProbabilities already own the K-class probability mapping.
            % Binary Platt/isotonic/BBQ calibration belongs to BinClass, not to the multiclass class axis.
            method = 'none';
            payload.kind = 'classification_action';
            payload.action = action;
            payload.method = method;
            payload.methodLabel = NMResultsViewerTools.calibrationMethodLabel(method);
            payload.title = sprintf('One-vs-REST %s overlays — %s', upper(action), sourceLabel);
            payload.probability = NMResultsViewerTools.multiClassOvRProbabilityVectors(probabilities, labels, classList, groupNames, colors, sourceLabel);
            if ~labelsKnown && ~strcmp(action,'probability')
                payload.message = 'Calibration and decision-curve analysis require the effective OOCV target labels.';
                return;
            end
            switch action
                case 'calibration'
                    numBins = round(spec.numBins);
                    numBins = max(3, min(50, numBins));
                    smoothCurve = spec.smoothCurve;
                    metric = spec.calibrationMetric;
                    payload.calibration = NMResultsViewerTools.multiClassOvRCalibrationPayload(probabilities, labels, classList, groupNames, colors, numBins, smoothCurve, metric, sourceLabel, method);
                case 'dca'
                    maxProb = spec.maxProb;
                    stepSize = spec.stepSize;
                    if isnan(maxProb) || maxProb <= 0 || maxProb > 1, maxProb = 1; end
                    maxProb = max(0.05, min(1, maxProb));
                    stepSize = max(0.005, min(0.2, stepSize));
                    payload.dca = NMResultsViewerTools.multiClassOvRDcaPayload(probabilities, labels, classList, groupNames, colors, maxProb, stepSize, sourceLabel, method);
                case 'probability'
                otherwise
                    error('NMResultsViewerTools:UnsupportedMultiClassAction', ...
                        'Unsupported canonical multi-class action: %s.', action);
            end
            payload.message = sprintf('Multi-class %s payload generated directly from the writer-produced K-class probability matrix (%s).', action, sourceLabel);
            payload.ok = logical(payload.probability.ok || ~strcmp(action,'probability'));
            if ~strcmp(action,'probability')
                payload.ok = logical(payload.(action).ok);
            end
        end

        function P = multiClassOvRProbabilityVectors(probabilities, labels, classList, groupNames, colors, sourceLabel)
            % MULTICLASSOVRPROBABILITYVECTORS  Project writer-produced class probabilities without recalibration.
            vecTmpl = struct('label','','color','#2563eb','labels',[],'probabilities',[],'scores',[]);
            vectors = repmat(vecTmpl, 1, 0);
            labels = double(labels(:));
            labelsAvailable = any(isfinite(labels));
            for ii = 1:numel(classList)
                jj = classList(ii);
                p = double(probabilities(:,jj));
                good = isfinite(p) & p >= 0 & p <= 1;
                if ~any(good), continue; end
                if labelsAvailable
                    y = double(labels == jj);
                    good = good & isfinite(labels);
                    yOut = double(y(good));
                else
                    yOut = [];
                end
                vectors(end+1) = struct('label',sprintf('%s vs REST', groupNames{jj}), 'color',colors{jj}, ...
                    'labels',yOut, 'probabilities',double(p(good)), 'scores',double(p(good))); %#ok<AGROW>
            end
            P = struct('ok',~isempty(vectors),'multi',numel(vectors) > 1,'sourceLabel',sourceLabel,'vectors',vectors, ...
                'activeVectors',struct(),'message','');
            if ~isempty(vectors)
                P.activeVectors = vectors(1);
            else
                P.message = 'No finite writer-produced class-probability vector is available.';
            end
        end

        function C = multiClassOvRCalibrationPayload(probabilities, labels, classList, groupNames, colors, numBins, smoothCurve, metric, sourceLabel, method)
            curveTmpl = struct('ok',false,'label','','color','#2563eb','metric','','metricValue',NaN,'points',[],'smoothPoints',[],'message','');
            curves = repmat(curveTmpl, 1, numel(classList));
            for ii = 1:numel(classList)
                jj = classList(ii);
                y = double(labels == jj);
                p = double(probabilities(:,jj));
                cal = NMResultsViewerTools.calibrationCurvePayload(y, p, numBins, smoothCurve, metric, sprintf('%s vs REST', groupNames{jj}), method);
                curves(ii) = struct('ok',logical(cal.ok),'label',sprintf('%s vs REST', groupNames{jj}),'color',colors{jj}, ...
                    'metric',cal.metric,'metricValue',double(cal.metricValue),'points',cal.points,'smoothPoints',cal.smoothPoints,'message',cal.message);
            end
            okVec = [curves.ok];
            C = struct('ok',any(okVec),'multi',numel(classList) > 1,'sourceLabel',sourceLabel, ...
                'title',sprintf('One-vs-REST calibration — %s', sourceLabel),'method',method,'methodLabel',NMResultsViewerTools.calibrationMethodLabel(method), ...
                'hasReferenceCurve',false,'referenceCurve',struct('ok',false,'label','','color','#64748b','points',[],'smoothPoints',[]), ...
                'numBins',numBins,'smoothCurve',logical(smoothCurve),'metric',metric,'metricValue',NaN, ...
                'points',[],'smoothPoints',[],'curves',curves,'message','');
            if ~C.ok
                C.message = 'No one-vs-rest calibration curve has enough occupied bins and class support.';
            elseif numel(classList) == 1
                hit = find(okVec,1,'first');
                C.points = curves(hit).points;
                C.smoothPoints = curves(hit).smoothPoints;
                C.metric = curves(hit).metric;
                C.metricValue = curves(hit).metricValue;
                C.activeLabel = curves(hit).label;
            end
        end

        function D = multiClassOvRDcaPayload(probabilities, labels, classList, groupNames, colors, maxProb, stepSize, sourceLabel, method)
            % MULTICLASSOVRDCAPAYLOAD  Build OvR decision-curve-analysis payloads.
            %
            %   D = NMResultsViewerTools.multiClassOvRDcaPayload(...) returns one
            %   decision-curve descriptor per class, using binary one-vs-rest labels
            %   and that class probability vector over the requested threshold grid.
            curveTmpl = struct('ok',false,'label','','color','#2563eb','points',[],'message','');
            curves = repmat(curveTmpl, 1, 0);
            for ii = 1:numel(classList)
                jj = classList(ii);
                y = double(labels == jj);
                p = double(probabilities(:,jj));
                dca = NMResultsViewerTools.dcaPayload(y, p, [], [], maxProb, stepSize, sprintf('%s vs REST', groupNames{jj}), method);
                curve = curveTmpl;
                curve.ok = logical(dca.ok);
                curve.label = sprintf('%s vs REST', groupNames{jj});
                curve.color = colors{jj};
                curve.points = dca.active.points;
                curve.message = dca.message;
                curves(end+1) = curve; %#ok<AGROW>
            end
            okVec = false(1,numel(curves));
            for ii=1:numel(curves), okVec(ii) = logical(curves(ii).ok); end
            D = struct('ok',any(okVec),'multi',numel(classList) > 1,'sourceLabel',sourceLabel, ...
                'title',sprintf('One-vs-REST decision curves — %s', sourceLabel),'method',method,'methodLabel',NMResultsViewerTools.calibrationMethodLabel(method), ...
                'maxProb',maxProb,'stepSize',stepSize,'train',struct('label','Active','points',[]), ...
                'active',struct('label','Active','points',[]),'reference',struct('label','Discovery/CV','points',[]), ...
                'oocv',struct('label','Active','points',[]),'curves',curves,'message','');
            if ~D.ok
                D.message = 'No one-vs-rest DCA curve has finite binary labels from both classes and bounded probabilities.';
            elseif numel(classList) == 1
                hit = find(okVec,1,'first');
                D.active = struct('label',curves(hit).label,'points',curves(hit).points);
                D.train = D.active;
                D.activeLabel = curves(hit).label;
            end
        end

        function [payload, NM, didPersist] = getRegressionBinarizationActionPayload(NM, spec)
            % GETREGRESSIONBINARIZATIONACTIONPAYLOAD  Build binary views from regression.
            %
            %   [payload, NM, didPersist] = NMResultsViewerTools.getRegressionBinarizationActionPayload(NM, spec)
            %   thresholds a regression target as requested by spec and returns
            %   probability/calibration/decision-curve style payloads when supported.
            %   The current implementation reports didPersist=false.
            if nargin < 2 || isempty(spec), spec = struct(); end
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            didPersist = false;
            payload = struct('ok',false,'kind','regression_action','action','', ...
                'message','','title','','method','none','methodLabel','No Calibration', ...
                'didPersistProbability',false,'probability',struct(),'calibration',struct(),'dca',struct());

            idx = spec.analysisIndex;
            targetIdx = spec.targetIndex;
            source = spec.source;
            action = spec.action;
            method = spec.calibrationMethod;
            forceRecomputeProbability = spec.forceRecomputeProbability;
            payload.action = action;
            payload.method = method;
            payload.methodLabel = NMResultsViewerTools.calibrationMethodLabel(method);

            if ~logical(spec.binarizationEnabled)
                payload.message = 'Enable regression binarization and supply a valid threshold before opening calibration or DCA.';
                return;
            end
            if isnan(idx) || idx < 1 || ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || idx > numel(NM.analysis)
                payload.message = 'Select a completed regression analysis before opening a probability, calibration or DCA panel.';
                return;
            end

            regPayload = NMResultsViewerTools.getRegressionPayload(NM, spec);
            if ~regPayload.regressionPlot.ok
                payload.message = regPayload.message;
                if isempty(payload.message)
                    payload.message = 'Regression payload is unavailable for binarized-regression probability analysis.';
                end
                return;
            end
            if ~isfinite(double(regPayload.binarization.value))
                payload.message = 'Calibration and DCA for regression require an active finite binarization threshold.';
                return;
            end
            threshold = double(regPayload.binarization.value);
            [isOOCVActionSource, actionOOCVGlobalIndex] = NMResultsViewerTools.parseOOCVSourceId(source); %#ok<ASGLU>

            [activeLabels, activeScores] = NMResultsViewerTools.regressionBinaryVectorsFromPoints(regPayload.regressionPlot.points);
            if isOOCVActionSource
                if isfield(regPayload.regressionPlot,'referencePoints')
                    [referenceLabels, referenceScores] = NMResultsViewerTools.regressionBinaryVectorsFromPoints(regPayload.regressionPlot.referencePoints);
                else
                    referenceLabels = []; referenceScores = [];
                end
                activeLabel = 'OOCV'; referenceLabel = 'Discovery/CV';
            else
                referenceLabels = []; referenceScores = [];
                activeLabel = 'Discovery/CV'; referenceLabel = '';
            end
            if numel(unique(activeLabels(isfinite(activeLabels)))) < 2
                payload.message = 'Binarized-regression calibration and DCA require known binary labels from both classes.';
                return;
            end
            if isOOCVActionSource && numel(unique(referenceLabels(isfinite(referenceLabels)))) < 2
                payload.message = 'OOCV binarized-regression calibration/DCA require Discovery/CV reference labels from both classes to fit the probability conversion.';
                return;
            end

            try
                [activeProbs, referenceProbs, methodOut, probMsg, persistInfo] = ...
                    NMResultsViewerTools.regressionBinarizedProbabilities(NM, idx, targetIdx, source, threshold, ...
                    activeLabels, activeScores, referenceLabels, referenceScores, method, forceRecomputeProbability);
                payload.method = methodOut;
                payload.methodLabel = NMResultsViewerTools.calibrationMethodLabel(methodOut);
                payload.title = sprintf('Derived binary risk from regression threshold %.4g | %s', threshold, payload.methodLabel);
                payload.probability = NMResultsViewerTools.probabilitySummaryPayload(activeLabels, activeProbs, activeScores, payload.title, methodOut);
                payload.probability.activeLabel = activeLabel;
                payload.probability.activeVectors = NMResultsViewerTools.probabilityVectorPayload(activeLabels, activeProbs, activeScores, activeLabel);
                payload.probability.regressionBinarized = struct('ok',true,'threshold',double(threshold), ...
                    'message','Probabilities are derived from regression predictions using the selected binarization threshold.');
                if isOOCVActionSource
                    payload.probability.referenceLabel = referenceLabel;
                    payload.probability.referenceVectors = NMResultsViewerTools.probabilityVectorPayload(referenceLabels, referenceProbs, referenceScores, referenceLabel);
                end

                switch action
                    case {'calibration','calib'}
                        numBins = round(spec.numBins);
                        numBins = max(3, min(50, numBins));
                        smoothCurve = spec.smoothCurve;
                        metric = spec.calibrationMetric;
                        payload.calibration = NMResultsViewerTools.calibrationCurvePayload(activeLabels, activeProbs, numBins, smoothCurve, metric, payload.title, methodOut);
                        payload.calibration.activeLabel = activeLabel;
                        payload.calibration.regressionBinarized = payload.probability.regressionBinarized;
                        if isOOCVActionSource
                            payload.calibration.referenceCurve = NMResultsViewerTools.calibrationCurvePayload(referenceLabels, referenceProbs, numBins, smoothCurve, metric, payload.title, methodOut);
                            payload.calibration.referenceCurve.label = referenceLabel;
                            payload.calibration.referenceCurve.color = '#64748b';
                            payload.calibration.hasReferenceCurve = true;
                            payload.calibration.referenceLabel = referenceLabel;
                        end
                    case 'dca'
                        maxProb = spec.maxProb;
                        stepSize = spec.stepSize;
                        if isnan(maxProb) || maxProb <= 0 || maxProb > 1
                            maxProb = NMResultsViewerTools.initialDcaMaxProbability(activeLabels, activeProbs);
                        end
                        maxProb = max(0.05, min(1, maxProb));
                        stepSize = max(0.005, min(0.2, stepSize));
                        payload.dca = NMResultsViewerTools.dcaPayload(activeLabels, activeProbs, referenceLabels, referenceProbs, maxProb, stepSize, payload.title, methodOut);
                        payload.dca.activeLabel = activeLabel;
                        payload.dca.referenceLabel = referenceLabel;
                        payload.dca.activeVectors = NMResultsViewerTools.probabilityVectorPayload(activeLabels, activeProbs, activeScores, activeLabel);
                        payload.dca.regressionBinarized = payload.probability.regressionBinarized;
                        if isOOCVActionSource
                            payload.dca.referenceVectors = NMResultsViewerTools.probabilityVectorPayload(referenceLabels, referenceProbs, referenceScores, referenceLabel);
                        end
                    otherwise
                        action = 'probability';
                end

                [NM, didPersist] = NMResultsViewerTools.persistRegressionBinarizedProbabilityArtifact(NM, idx, targetIdx, source, persistInfo, methodOut, forceRecomputeProbability);
                payload.didPersistProbability = logical(didPersist);
                payload.action = action;
                payload.ok = true;
                if didPersist
                    payload.message = sprintf('%s Binarized-regression probability scores were persisted into the selected NeuroMiner result container.', probMsg);
                else
                    payload.message = probMsg;
                end
                fprintf('[NMResultsViewer] %s\n', payload.message);
            catch ME
                payload.message = ['Binarized-regression action extraction failed: ' ME.message];
            end
        end


        function out = plotVectorOptions(NM, req)
            % plotVectorOptions  Discover case-aligned vectors for Model Performance controls.
            %
            % Browser requests carry the fixed service envelope req.role/req.spec.
            % Canonical NM/DataIO fields own training and OOCV vectors; only the
            % MATLAB workspace catalogue remains an external discovery boundary.
            % nm2-allow: public browser-service boundary validates the fixed vector-options request envelope
            if ~isstruct(req) || ~isscalar(req) || ~isfield(req,'spec') || ~isstruct(req.spec) || ~isscalar(req.spec) || ~isfield(req,'role')
                error('NMResultsViewerTools:InvalidPlotVectorRequest', ...
                    'Vector-option requests require scalar req.spec and req.role fields.');
            end
            spec = req.spec;
            role = req.role;
            if ~any(strcmp(role,{'bundle','xaxis','subgroup','plot'}))
                error('NMResultsViewerTools:InvalidPlotVectorRole', ...
                    'Unsupported vector-option role "%s".',role);
            end
            doProfile = NMResultsViewerTools.profileEnabled(req);
            tTotal = tic;
            source = spec.source;
            [nCases, sourceLabel] = NMResultsViewerTools.plotVectorCaseCount(NM, spec);
            if nCases < 1
                single = struct('ok',true,'message','No cases are available for the selected result source.', ...
                    'role',role,'nCases',0,'source',source,'sourceLabel',sourceLabel,'enabled',false, ...
                    'options',NMResultsViewerTools.emptyPlotVectorOptions());
                if strcmp(role,'bundle')
                    out = struct('ok',true,'message',single.message,'role','bundle','nCases',0, ...
                        'source',source,'sourceLabel',sourceLabel,'enabled',false,'xaxis',single,'subgroup',single);
                else
                    out = single;
                end
                NMResultsViewerTools.profileLog(doProfile, ...
                    '[nm-prof]     results vector options role=%s TOTAL: %.3fs (cases=0)\n', role, toc(tTotal));
                return;
            end

            workspaceCatalogue = NMResultsViewerTools.plotVectorWorkspaceCatalogue();
            if strcmp(role,'bundle')
                xaxis = NMResultsViewerTools.plotVectorOptionsForRole(NM, nCases, source, sourceLabel, 'xaxis', spec, workspaceCatalogue);
                subgroup = NMResultsViewerTools.plotVectorOptionsForRole(NM, nCases, source, sourceLabel, 'subgroup', spec, workspaceCatalogue);
                out = struct('ok',true,'message',sprintf('Vector options listed for %d cases.', nCases), ...
                    'role','bundle','nCases',double(nCases),'source',source,'sourceLabel',sourceLabel,'enabled',true, ...
                    'xaxis',xaxis,'subgroup',subgroup);
                NMResultsViewerTools.profileLog(doProfile, ...
                    '[nm-prof]     results vector options bundle TOTAL: %.3fs (x=%d, subgroup=%d, cases=%d)\n', ...
                    toc(tTotal), double(numel(xaxis.options)), double(numel(subgroup.options)), double(nCases));
            else
                out = NMResultsViewerTools.plotVectorOptionsForRole(NM, nCases, source, sourceLabel, role, spec, workspaceCatalogue);
                NMResultsViewerTools.profileLog(doProfile, ...
                    '[nm-prof]     results vector options role=%s TOTAL: %.3fs (options=%d, cases=%d)\n', ...
                    role, toc(tTotal), double(numel(out.options)), double(nCases));
            end
        end

        function out = plotVectorOptionsForRole(NM, nCases, source, sourceLabel, role, spec, workspaceCatalogue)
            % plotVectorOptionsForRole  Build one fixed-schema vector-selector option list from a shared workspace catalogue.
            opts = NMResultsViewerTools.plotVectorCandidateOptions(NM, nCases, role, spec, workspaceCatalogue);
            out = struct('ok',true,'message','Usable MATLAB vectors were listed.', ...
                'role',role,'nCases',double(nCases),'source',source,'sourceLabel',sourceLabel, ...
                'enabled',true,'options',opts);
            if isempty(opts)
                out.message = sprintf('No numeric/logical MATLAB workspace vector with %d entries was detected. You can still enter a direct reference such as NM.covars(:,1).', nCases);
            else
                out.message = sprintf('%d usable MATLAB vector(s) with %d entries were detected.', numel(opts), nCases);
            end
        end
        function avail = modelPerformancePermutationAvailability(NM, analysisIndex, targetIndex, modelSource)
            % modelPerformancePermutationAvailability  Public probe for persisted VIS model-permutation material.
            if nargin < 4, modelSource = ''; end
            avail = NMResultsViewerTools.modelPerformancePermutationAvailabilityImpl( ...
                NM, analysisIndex, targetIndex, modelSource);
        end
        function payload = modelPerformancePermutationPayload(NM, analysisIndex, targetIndex, classIndex, modelSource)
            if nargin < 4, modelSource = ''; end
            % modelPerformancePermutationPayload  Public extractor for persisted VIS model-permutation histograms.
            payload = NMResultsViewerTools.modelPerformancePermutationPayloadImpl(NM, analysisIndex, targetIndex, classIndex, modelSource);
        end

        function payload = getModelFeatureRelationPayload(NM, spec)
            if nargin>=1 && NMResultsViewerScientificCapability.isQuery(NM) % nm2-allow: Scientific Capability registry invokes this public service with a query object instead of NM.
                p=[NMResultsViewerScientificCapability.provide('feature_relation_graph','scientific_artefact','feature_inspection','feature_relation_graph'), ...
                    NMResultsViewerScientificCapability.provide('feature_graph_robustness','scientific_artefact','feature_inspection','feature_graph_robustness'), ...
                    NMResultsViewerScientificCapability.provide('feature_relation_matrix_view','visualization','',''), ...
                    NMResultsViewerScientificCapability.provide('feature_network','visualization','',''), ...
                    NMResultsViewerScientificCapability.provide('feature_relation_pattern_gallery','visualization','','')];
                payload=NMResultsViewerScientificCapability.contract('feature_relation_service',{{'feature_relation_matrix'}},p); return;
            end
            % getModelFeatureRelationPayload  Build one bounded matrix/graph service payload.
            %
            % Syntax:
            %   payload = NMResultsViewerTools.getModelFeatureRelationPayload(NM,spec)
            %
            % Inputs:
            %   NM    Authoritative NeuroMiner analysis structure; read only.
            %   spec  Results Viewer selectors plus optional relationState. The header
            %         featureContextId determines the sole relation source; matrixId, sourceScope,
            %         and relationId are optional internal replay assertions. graphRobustnessRequested
            %         triggers the automated fixed-density
            %         sparsification assessment for the already filtered stable feature universe.
            %
            % Outputs:
            %   payload  Fixed-schema service response containing matrix options, one bounded
            %            relation view, optional graphRobustness result, diagnostics, and message.
            %
            % Scientific contract:
            %   The method resolves one exact Model Feature Inspection context, normalizes stored
            %   correlation/P/q layers, applies stable subset and secondary feature filtering,
            %   builds the canonical pruned graph and its graph statistics, derives relation
            %   patterns from that same final edge set, and only then projects matrix/graph state
            %   onto the requested page. Robustness holds the matrix, selected layer, and filtered
            %   feature universe fixed and assesses graph sparsification sensitivity only.
            %
            % Invariants and mutability:
            %   Raw NM/VIS data are never returned or mutated. No modality fallback is allowed for
            %   ambiguous combined contexts. Browser and report consumers receive the same canonical
            %   backend contracts; presentation state cannot redefine graph topology or patterns.
            %
            % Errors and diagnostics:
            %   Missing or multiply resolved Feature-source matrices, source-scope or
            %   relation-identity assertion mismatches, unavailable layers or secondary metrics,
            %   and graph/
            %   robustness failures return explicit diagnostics with source and stack context.
            %
            % Dependencies:
            %   NMResultsViewerFeatureRelationTools and NMResultsViewerFeatureGraphTools; graph and
            %   robustness computations require Base MATLAB only.
            %
            % Side effects:
            %   None beyond local read-only extraction and temporary value allocation.
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            viewTemplate=NMResultsViewerFeatureRelationTools.relationViewTemplate();
            descriptorTemplate=NMResultsViewerFeatureRelationTools.matrixServiceDescriptor( ...
                NMResultsViewerFeatureRelationTools.matrixTemplate());
            payload=struct('ok',false,'kind','model_feature_relation', ...
                'schemaVersion',1,'relationServiceContractVersion','C17b.1', ...
                'relationReportScopeContractVersion','C17j5a.1', ...
                'analysisIndex',spec.analysisIndex, ...
                'targetIndex',spec.targetIndex, ...
                'classifierIndex',spec.classifierIndex, ...
                'selectedFeatureContextId','','selectedMatrixId','', ...
                'selectedSourceScope','','selectedRelationId','', ...
                'matrixOptions',descriptorTemplate([]),'view',viewTemplate, ...
                'graphRobustness',NMResultsViewerFeatureGraphTools.robustnessTemplate(), ...
                'diagnostics',repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0), ...
                'message','');

            inspectionSpec=spec;
            inspectionSpec.resultType='model_feature_inspection';
            inspectionSpec.maxFeatures=1;
            inspection=NMResultsViewerTools.getModelFeatureInspectionPayload(NM,inspectionSpec);
            payload.selectedFeatureContextId=inspection.selectedFeatureContextId;
            if isempty(inspection.matrixPayloads)
                payload.message='The selected Feature source contains no feature-relation descriptor.';
                payload.diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', ...
                    'feature_relation_service',payload.message,'','', ...
                    'getModelFeatureRelationPayload','','');
                return;
            end
            options=repmat(descriptorTemplate,1,numel(inspection.matrixPayloads));
            for ii=1:numel(inspection.matrixPayloads)
                options(ii)=NMResultsViewerFeatureRelationTools.matrixServiceDescriptor(inspection.matrixPayloads(ii));
            end
            payload.matrixOptions=options;

            relationState=spec;
            % nm2-allow: public feature-relation service boundary accepts an optional nested relationState request envelope.
            if isfield(spec,'relationState')
                % nm2-allow: public feature-relation service boundary validates the nested request envelope type and cardinality.
                if ~isstruct(spec.relationState) || ~isscalar(spec.relationState)
                    error('NMResultsViewerTools:FeatureRelationStateInvalid', ...
                        'relationState must be one scalar request struct.');
                end
                relationState=spec.relationState;
            end
            requestedMatrixId='';
            % nm2-allow: public feature-relation service boundary normalizes caller-supplied matrix identity text.
            if isfield(relationState,'matrixId') && ~isempty(relationState.matrixId)
                requestedMatrixId=strtrim(char(string(relationState.matrixId))); % nm2-allow: public relationState browser request provides optional external matrix ID text.
            end
            selectable=find([options.serviceAvailable] & [options.available]);
            if isempty(requestedMatrixId)
                if numel(selectable)==1
                    selectedOptionIndex=selectable(1);
                    requestedMatrixId=options(selectedOptionIndex).matrixId;
                elseif numel(selectable)>1
                    payload.message=['The selected Feature source resolved to multiple relation matrices, ' ...
                        'which violates the single authoritative Feature-source contract.'];
                    payload.diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                        'feature_relation_feature_source_ambiguity',payload.message,'',inspection.selectedFeatureContextId, ...
                        'getModelFeatureRelationPayload','','');
                    return;
                else
                    payload.message='No authoritative relation matrix is available for the selected Feature source.';
                    payload.diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', ...
                        'feature_relation_matrix_selection',payload.message,'',inspection.selectedFeatureContextId, ...
                        'getModelFeatureRelationPayload','','');
                    return;
                end
            else
                selectedOptionIndex=find(strcmp({options.matrixId},requestedMatrixId),1,'first');
                if isempty(selectedOptionIndex)
                    payload.message=sprintf('Relation matrix "%s" is not part of the selected feature context.',requestedMatrixId);
                    payload.diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                        'feature_relation_matrix_selection',payload.message,'',inspection.selectedFeatureContextId, ...
                        'getModelFeatureRelationPayload','','');
                    return;
                end
            end
            payload.selectedMatrixId=requestedMatrixId;
            selectedDescriptor=options(selectedOptionIndex);
            contextId=selectedDescriptor.contextId;
            sourceScope=selectedDescriptor.sourceScope;
            relationId=selectedDescriptor.relationId;
            requestedSourceScope='';
            requestedRelationId='';
            % nm2-allow: public feature-relation service boundary normalizes optional source-scope replay identity.
            if isfield(relationState,'sourceScope') && ~isempty(relationState.sourceScope)
                requestedSourceScope=lower(strtrim(char(string(relationState.sourceScope)))); % nm2-allow: public relationState browser request normalizes external source-scope text.
            end
            % nm2-allow: public feature-relation service boundary normalizes optional relation replay identity.
            if isfield(relationState,'relationId') && ~isempty(relationState.relationId)
                requestedRelationId=strtrim(char(string(relationState.relationId))); % nm2-allow: public relationState browser request normalizes optional relation identity text.
            end
            if ~isempty(requestedSourceScope) && ~strcmp(requestedSourceScope,sourceScope)
                payload.message=sprintf('Relation source scope "%s" does not match matrix %s scope "%s".', ...
                    requestedSourceScope,requestedMatrixId,sourceScope);
                payload.diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                    'feature_relation_source_scope_mismatch',payload.message,'',contextId, ...
                    'getModelFeatureRelationPayload','','');
                return;
            end
            if ~isempty(requestedRelationId) && ~strcmp(requestedRelationId,relationId)
                payload.message=sprintf('Relation identity "%s" does not match matrix %s identity "%s".', ...
                    requestedRelationId,requestedMatrixId,relationId);
                payload.diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                    'feature_relation_identity_assertion_mismatch',payload.message,'',contextId, ...
                    'getModelFeatureRelationPayload','','');
                return;
            end
            payload.selectedSourceScope=sourceScope;
            payload.selectedRelationId=relationId;
            analysisIndex=round(double(payload.analysisIndex));
            A=NM.analysis{analysisIndex};
            if strcmp(sourceScope,'combined')
                [matrix,matrixDiagnostics]=NMResultsViewerTools.modelFeatureInspectionCombinedRelationMatrixPayload( ...
                    A,inspection.featureContexts,inspection.selectedFeatureContext, ...
                    payload.classifierIndex,true,selectedDescriptor.relationId);
                diagnostics=matrixDiagnostics;
                if isempty(matrix)
                    payload.message='The requested combined relation no longer resolves to a valid persisted CombinedRelation contract.';
                    payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                        'feature_relation_combined_resolution',payload.message,'CombinedRelation',contextId, ...
                        'getModelFeatureRelationPayload','','')];
                    return;
                end
                ctx=struct('contextId',matrix.contextId,'nFeatures',matrix.nRows, ...
                    'analysisIndex',matrix.analysisIndex,'targetIndex',matrix.targetIndex, ...
                    'resultTargetIndex',matrix.resultTargetIndex,'modalityIndex',0, ...
                    'modalityLabel',matrix.modalityLabel,'varind',0);
            else
                contextIndex=find(strcmp({inspection.contexts.contextId},contextId),1,'first');
                if isempty(contextIndex)
                    payload.message=sprintf('Relation matrix %s does not resolve to an authoritative physical feature context.',requestedMatrixId);
                    payload.diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                        'feature_relation_context_resolution',payload.message,'',contextId, ...
                        'getModelFeatureRelationPayload','','');
                    return;
                end
                ctx=inspection.contexts(contextIndex);
                v=NMResultsViewerTools.modelFeatureInspectionVisEntry(A,ctx.visRowIndex,ctx.resultTargetIndex);
                if ~NMResultsViewerTools.modelFeatureInspectionIsVisStruct(v)
                    payload.message='The selected relation context no longer resolves to a valid VIS entry.';
                    payload.diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                        'feature_relation_vis_resolution',payload.message,'',contextId, ...
                        'getModelFeatureRelationPayload','','');
                    return;
                end
                [matrix,matrixDiagnostics]=NMResultsViewerFeatureRelationTools.buildMatrixPayload( ...
                    v,ctx,payload.classifierIndex,struct('includeFullValues',true));
                if matrix.available
                    [names,hasNames]=NMResultsViewerTools.modelFeatureInspectionFeatureNames(NM,ctx.varind,ctx.nFeatures,1:ctx.nFeatures,ctx);
                    if hasNames, matrix.labels=names; end
                end
                diagnostics=matrixDiagnostics;
            end
            if ~strcmp(matrix.matrixId,requestedMatrixId)
                payload.message=sprintf('Resolved relation matrix identity %s does not match the requested identity %s.', ...
                    matrix.matrixId,requestedMatrixId);
                payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                    'feature_relation_identity_mismatch',payload.message,'',contextId, ...
                    'getModelFeatureRelationPayload','','')];
                return;
            end

            requestState=relationState;
            requestState.matrixId=requestedMatrixId;
            requestState.sourceScope=sourceScope;
            requestState.relationId=relationId;
            secondaryMetric=NMResultsViewerFeatureRelationTools.secondaryFeatureMetricTemplate();
            secondaryId='';
            % nm2-allow: public feature-relation service boundary normalizes the optional secondary-metric request token.
            if isfield(requestState,'secondaryFeatureMetricId') && ~isempty(requestState.secondaryFeatureMetricId)
                secondaryId=lower(strtrim(char(string(requestState.secondaryFeatureMetricId)))); % nm2-allow: public Feature Relation secondary metric selector is browser-originated text.
            end
            if ~isempty(secondaryId)
                emptyComponent=NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate();
                selectedMeasure=NMResultsViewerTools.modelFeatureInspectionMeasureTemplate();
                metricValues=[];
                if strcmp(sourceScope,'combined')
                    memberIds=matrix.memberContextIds;
                    memberCounts=double(matrix.memberFeatureCounts(:)');
                    memberVarind=double(matrix.memberVarind(:)');
                    combinedValues=nan(sum(memberCounts),1);
                    offset=0;
                    for memberIndex=1:numel(memberIds)
                        memberId=memberIds{memberIndex};
                        contextIndex=find(strcmp({inspection.contexts.contextId},memberId),1,'first');
                        if isempty(contextIndex)
                            payload.message=sprintf('Combined relation member context "%s" is unavailable for secondary metric "%s".',memberId,secondaryId);
                            payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                                'feature_relation_combined_secondary_metric_context',payload.message,'',ctx.contextId, ...
                                'getModelFeatureRelationPayload','','')];
                            return;
                        end
                        memberCtx=inspection.contexts(contextIndex);
                        if round(double(memberCtx.nFeatures))~=round(memberCounts(memberIndex)) || ...
                                round(double(memberCtx.varind))~=round(memberVarind(memberIndex))
                            payload.message=sprintf('Combined relation member context "%s" does not match the persisted feature-axis contract.',memberId);
                            payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                                'feature_relation_combined_secondary_metric_context',payload.message,'',memberId, ...
                                'getModelFeatureRelationPayload','','')];
                            return;
                        end
                        memberVis=NMResultsViewerTools.modelFeatureInspectionVisEntry(A,memberCtx.visRowIndex,memberCtx.resultTargetIndex);
                        if ~NMResultsViewerTools.modelFeatureInspectionIsVisStruct(memberVis)
                            payload.message=sprintf('Combined relation member context "%s" no longer resolves to a valid VIS entry.',memberId);
                            payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                                'feature_relation_combined_secondary_metric_context',payload.message,'',memberId, ...
                                'getModelFeatureRelationPayload','','')];
                            return;
                        end
                        [memberMeasures,memberMeasure,measureDiagnostics]=NMResultsViewerTools.modelFeatureInspectionMeasuresForVis( ...
                            memberVis,payload.classifierIndex,memberCtx.nFeatures,memberCtx.contextId,secondaryId,emptyComponent,false);
                        diagnostics=[diagnostics measureDiagnostics];
                        exactMeasureIndex=find(strcmp({memberMeasures.measureId},secondaryId),1,'first');
                        if isempty(exactMeasureIndex) || isempty(memberMeasure.measureId) || ~strcmp(memberMeasure.measureId,secondaryId)
                            payload.message=sprintf('Secondary feature metric "%s" is unavailable for combined relation member %s.',secondaryId,memberId);
                            payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', ...
                                'feature_relation_combined_secondary_metric',payload.message,'',memberId, ...
                                'getModelFeatureRelationPayload','','')];
                            return;
                        end
                        memberMeasure=memberMeasures(exactMeasureIndex);
                        if memberIndex==1
                            selectedMeasure=memberMeasure;
                        elseif ~strcmp(selectedMeasure.measureId,memberMeasure.measureId) || ...
                                ~strcmp(selectedMeasure.valuePolarity,memberMeasure.valuePolarity) || ...
                                ~strcmp(selectedMeasure.thresholdMode,memberMeasure.thresholdMode) || ...
                                ~isequaln(selectedMeasure.thresholdLow,memberMeasure.thresholdLow) || ...
                                ~isequaln(selectedMeasure.thresholdHigh,memberMeasure.thresholdHigh) || ...
                                ~isequaln(selectedMeasure.thresholdValue,memberMeasure.thresholdValue)
                            payload.message=sprintf('Secondary feature metric "%s" has inconsistent scientific semantics across combined relation members.',secondaryId);
                            payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                                'feature_relation_combined_secondary_metric_contract',payload.message,memberMeasure.sourceField,memberId, ...
                                'getModelFeatureRelationPayload','','')];
                            return;
                        end
                        [memberValues,metricDiagnostic]=NMResultsViewerTools.modelFeatureInspectionReadFeatureVector( ...
                            memberVis,memberMeasure.sourceField,payload.classifierIndex,memberCtx.nFeatures,emptyComponent,memberCtx.contextId,[]);
                        if ~isempty(metricDiagnostic), diagnostics=[diagnostics metricDiagnostic]; end
                        if isempty(memberValues) || numel(memberValues)~=memberCounts(memberIndex)
                            payload.message=sprintf('Secondary feature metric "%s" could not be resolved on the complete native axis of combined relation member %s.',secondaryId,memberId);
                            payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', ...
                                'feature_relation_combined_secondary_metric',payload.message,memberMeasure.sourceField,memberId, ...
                                'getModelFeatureRelationPayload','','')];
                            return;
                        end
                        target=offset+(1:memberCounts(memberIndex));
                        combinedValues(target)=double(memberValues(:));
                        offset=offset+memberCounts(memberIndex);
                    end
                    metricValues=combinedValues;
                else
                    [measures,selectedMeasure,measureDiagnostics]=NMResultsViewerTools.modelFeatureInspectionMeasuresForVis( ...
                        v,payload.classifierIndex,ctx.nFeatures,ctx.contextId,secondaryId,emptyComponent,false);
                    diagnostics=[diagnostics measureDiagnostics];
                    exactMeasureIndex=find(strcmp({measures.measureId},secondaryId),1,'first');
                    if isempty(exactMeasureIndex) || isempty(selectedMeasure.measureId) || ~strcmp(selectedMeasure.measureId,secondaryId)
                        payload.message=sprintf('Secondary feature metric "%s" is unavailable for relation context %s.',secondaryId,ctx.contextId);
                        payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', ...
                            'feature_relation_secondary_metric',payload.message,'',ctx.contextId, ...
                            'getModelFeatureRelationPayload','','')];
                        return;
                    end
                    selectedMeasure=measures(exactMeasureIndex);
                    [metricValues,metricDiagnostic]=NMResultsViewerTools.modelFeatureInspectionReadFeatureVector( ...
                        v,selectedMeasure.sourceField,payload.classifierIndex,ctx.nFeatures,emptyComponent,ctx.contextId,[]);
                    if ~isempty(metricDiagnostic), diagnostics=[diagnostics metricDiagnostic]; end
                    if isempty(metricValues)
                        payload.message=sprintf('Secondary feature metric "%s" could not be read from %s.', ...
                            secondaryId,selectedMeasure.sourceField);
                        payload.diagnostics=[diagnostics NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', ...
                            'feature_relation_secondary_metric',payload.message,selectedMeasure.sourceField,ctx.contextId, ...
                            'getModelFeatureRelationPayload','','')];
                        return;
                    end
                end
                secondaryMetric.metricId=selectedMeasure.measureId;
                secondaryMetric.label=selectedMeasure.label;
                secondaryMetric.sourceField=selectedMeasure.sourceField;
                secondaryMetric.valuePolarity=selectedMeasure.valuePolarity;
                secondaryMetric.values=double(metricValues(:));
                secondaryMetric.validityMask=isfinite(secondaryMetric.values);
                secondaryMetric.defaultThresholdMode=selectedMeasure.thresholdMode;
                secondaryMetric.defaultThresholdLow=selectedMeasure.thresholdLow;
                secondaryMetric.defaultThresholdHigh=selectedMeasure.thresholdHigh;
                secondaryMetric.defaultThresholdValue=selectedMeasure.thresholdValue;
                secondaryMetric.defaultThresholdLabel=selectedMeasure.thresholdLabel;
                secondaryMetric.available=true;
                secondaryMetric.disabledReason='';
                % nm2-allow: public feature-relation request boundary fills omitted secondary-threshold mode from the selected metric.
                if ~isfield(requestState,'secondaryThresholdMode') || isempty(requestState.secondaryThresholdMode)
                    requestState.secondaryThresholdMode=selectedMeasure.thresholdMode;
                end
                % nm2-allow: public feature-relation request boundary fills an omitted/invalid lower threshold from the selected metric.
                if ~isfield(requestState,'secondaryThresholdLow') || isempty(requestState.secondaryThresholdLow) || ...
                        ~isnumeric(requestState.secondaryThresholdLow) || numel(requestState.secondaryThresholdLow)~=1 || ...
                        ~isfinite(double(requestState.secondaryThresholdLow(1)))
                    requestState.secondaryThresholdLow=selectedMeasure.thresholdLow;
                end
                % nm2-allow: public feature-relation request boundary fills an omitted/invalid upper threshold from the selected metric.
                if ~isfield(requestState,'secondaryThresholdHigh') || isempty(requestState.secondaryThresholdHigh) || ...
                        ~isnumeric(requestState.secondaryThresholdHigh) || numel(requestState.secondaryThresholdHigh)~=1 || ...
                        ~isfinite(double(requestState.secondaryThresholdHigh(1)))
                    requestState.secondaryThresholdHigh=selectedMeasure.thresholdHigh;
                end
                % nm2-allow: public feature-relation request boundary fills an omitted/invalid scalar threshold from the selected metric.
                if ~isfield(requestState,'secondaryThresholdValue') || isempty(requestState.secondaryThresholdValue) || ...
                        ~isnumeric(requestState.secondaryThresholdValue) || numel(requestState.secondaryThresholdValue)~=1 || ...
                        ~isfinite(double(requestState.secondaryThresholdValue(1)))
                    requestState.secondaryThresholdValue=selectedMeasure.thresholdValue;
                end
            end
            [view,viewDiagnostics]=NMResultsViewerFeatureRelationTools.buildRelationView(matrix,requestState,secondaryMetric);
            diagnostics=[diagnostics viewDiagnostics];
            payload.view=view;
            robustnessRequested=false;
            % nm2-allow: public feature-relation request boundary accepts optional graph-robustness boolean state.
            if isfield(requestState,'graphRobustnessRequested') && ~isempty(requestState.graphRobustnessRequested)
                rawRobustness=requestState.graphRobustnessRequested;
                if isnumeric(rawRobustness) || islogical(rawRobustness)
                    robustnessRequested=logical(rawRobustness(1));
                else
                    % nm2-allow: public feature-relation request boundary normalizes browser boolean text tokens.
                    robustnessRequested=ismember(lower(strtrim(char(string(rawRobustness)))),{'1','true','yes','on'});
                end
            end
            if robustnessRequested && view.available && ~isempty(view.selectedFeatureIndices)
                graphRequest=NMResultsViewerFeatureGraphTools.graphRequestTemplate();
                graphRequest.sourceLayerId=view.graph.sourceLayerId;
                graphRequest.kPerNode=view.graph.kPerNode;
                graphRequest.maxGlobal=view.graph.maxGlobal;
                graphRequest.targetDensity=view.graph.targetDensity;
                graphRequest.absoluteThreshold=view.graph.absoluteThreshold;
                graphRequest.relationPatternEnabled=false;
                densityGrid=[];
                % nm2-allow: public feature-relation request boundary validates optional numeric robustness-density input.
                if isfield(requestState,'graphRobustnessDensityGrid') && isnumeric(requestState.graphRobustnessDensityGrid)
                    densityGrid=double(requestState.graphRobustnessDensityGrid(:)');
                end
                [payload.graphRobustness,robustnessDiagnostics]= ...
                    NMResultsViewerFeatureGraphTools.identifyRobustStructure( ...
                    matrix,view.selectedFeatureIndices,graphRequest,densityGrid);
                diagnostics=[diagnostics robustnessDiagnostics];
            end
            payload.diagnostics=diagnostics;
            payload.ok=logical(view.available);
            if view.enabled
                clusteringText='';
                if view.clusteringApplied
                    clusteringText=sprintf(' Hierarchical ordering: %s.',view.clusteringLabel);
                elseif view.clusteringRequested
                    clusteringText=sprintf(' Clustering was not applied: %s',view.clusteringDisabledReason);
                end
                payload.message=sprintf('Feature-relation view %s contains %d displayed feature(s) on page %d of %d.%s', ...
                    view.viewId,view.displayedFeatureCount,view.currentPage,view.pageCount,clusteringText);
            elseif view.available
                payload.message=view.disabledReason;
            else
                payload.message=view.disabledReason;
            end
        end

        function [out, dispersion] = getModelFeatureInspectionMeasureVector(NM, spec, measureId, inspection)
            % getModelFeatureInspectionMeasureVector  Return one exact full feature vector.
            %
            % This public adapter reuses the authoritative Feature Inspection context,
            % classifier, target, component, and measure contracts. It does not truncate,
            % reorder, pad, or infer incompatible component axes. Representation adapters
            % use this method rather than reading persisted VIS fields independently.
            % Optional second output returns mean-weight dispersion from persisted SE.
            dispersion = struct('metricId','','values',[]);
            out = struct('ok',false,'message','', ...
                'scientificContractVersion',NMResultsViewerTools.modelFeatureInspectionScientificContractVersion(), ...
                'scientificAnnotation',NMResultsViewerScientificAnnotation.template(), ...
                'resolvedSelection',NMResultsViewerScientificAnnotation.legacyResolvedSelectionTemplate(), ...
                'analysisIndex',0,'targetIndex',0,'resultTargetIndex',NaN, ...
                'classifierIndex',0,'context',NMResultsViewerTools.modelFeatureInspectionContextTemplate(), ...
                'measure',NMResultsViewerTools.modelFeatureInspectionMeasureTemplate(), ...
                'spatialMap',NMResultsViewerTools.modelFeatureInspectionSpatialTemplate(), ...
                'component',NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate(), ...
                'values',[],'badcoords',[],'featureNames',{{}}, ...
                'diagnostic',repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0));
            spec.resultType = 'model_feature_inspection';
            if ~isempty(measureId), spec.measureId = measureId; end
            if isempty(inspection)
                metadataSpec = spec;
                metadataSpec.featureInspectionPayloadScope = 'metadata';
                inspection = NMResultsViewerTools.getModelFeatureInspectionPayload(NM,metadataSpec);
            end
            out.analysisIndex = inspection.analysisIndex;
            out.targetIndex = inspection.targetIndex;
            out.resultTargetIndex = inspection.resultTargetIndex;
            out.classifierIndex = inspection.classifierIndex;
            if ~inspection.ok || isempty(inspection.contexts)
                out.message = inspection.message;
                return;
            end
            NMResultsViewerTools.modelFeatureInspectionValidateCachedPayload(spec,inspection);
            out.scientificContractVersion = inspection.scientificContractVersion;
            out.scientificAnnotation = inspection.scientificAnnotation;
            out.resolvedSelection = inspection.resolvedSelection;
            physicalContextIds = inspection.resolvedSelection.physicalContextIds;
            if numel(physicalContextIds) ~= 1
                out.message = sprintf(['Exact feature-vector resolution requires one physical feature context; ' ...
                    'the canonical selection contains %d physical contexts.'],numel(physicalContextIds));
                return;
            end
            physicalContextId = physicalContextIds{1};
            contexts = inspection.contexts;
            hits = find(strcmp({contexts.contextId},physicalContextId));
            if numel(hits) ~= 1
                error('NMResultsViewerTools:InvalidFeatureInspectionPhysicalContext', ...
                    'Canonical physical context %s resolves to %d payload contexts.', ...
                    physicalContextId,numel(hits));
            end
            ctx = contexts(hits);
            measures = inspection.measures;
            requestedMeasureId = measureId;
            if isempty(requestedMeasureId)
                requestedMeasureId = inspection.selectedMeasureId;
            end
            measureHits = find(strcmp({measures.contextId},ctx.contextId) & ...
                strcmp({measures.measureId},requestedMeasureId));
            if isempty(measureHits)
                out.message = sprintf('Measure %s is unavailable for feature context %s.', ...
                    requestedMeasureId,ctx.contextId);
                return;
            end
            if numel(measureHits) ~= 1
                error('NMResultsViewerTools:DuplicateFeatureInspectionMeasure', ...
                    'Measure %s resolves to %d catalogue entries for physical feature context %s.', ...
                    requestedMeasureId,numel(measureHits),ctx.contextId);
            end
            measure = measures(measureHits);
            if ~measure.enabled
                out.message = measure.disabledReason;
                if isempty(out.message)
                    out.message = sprintf('Measure %s is disabled for feature context %s.',requestedMeasureId,ctx.contextId);
                end
                out.measure = measure;
                out.diagnostic = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'error','unavailable_feature_measure',out.message,measure.sourceField,ctx.contextId, ...
                    'getModelFeatureInspectionMeasureVector','','');
                return;
            end
            out.scientificAnnotation = NMResultsViewerScientificAnnotation.updateFeatureMeasure( ...
                out.scientificAnnotation,measure.measureId,measureId,true,'measureId', ...
                measure.sourceField,measure.seSourceField);
            out.resolvedSelection = ...
                NMResultsViewerScientificAnnotation.legacyResolvedSelection(out.scientificAnnotation);
            spatialMap = NMResultsViewerTools.modelFeatureInspectionSpatialTemplate();
            spatialHits = find(strcmp({inspection.spatialMaps.contextId},ctx.contextId) & ...
                strcmp({inspection.spatialMaps.measureId},measure.measureId));
            if numel(spatialHits) > 1
                error('NMResultsViewerTools:DuplicateFeatureRepresentationDescriptor', ...
                    'Feature context %s exposes more than one representation descriptor for measure %s.', ...
                    ctx.contextId,measure.measureId);
            end
            if numel(spatialHits) == 1
                spatialMap = inspection.spatialMaps(spatialHits);
            end
            component = NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate();
            if inspection.backprojectionAvailable
                compHit = find(strcmp({inspection.backprojectionComponents.componentId},inspection.selectedBackprojectionComponentId),1,'first');
                if isempty(compHit)
                    out.message = 'The selected backprojected component no longer resolves to the retained component catalogue.';
                    return;
                end
                component = inspection.backprojectionComponents(compHit);
            end
            A = NM.analysis{out.analysisIndex};
            v = NMResultsViewerTools.modelFeatureInspectionVisEntry(A,ctx.visRowIndex,out.resultTargetIndex);
            if ~NMResultsViewerTools.modelFeatureInspectionIsVisStruct(v)
                out.message = 'The selected feature context no longer resolves to an inspectable VIS struct.';
                return;
            end
            [values,diagnostic] = NMResultsViewerTools.modelFeatureInspectionReadFeatureVector( ...
                v,measure.sourceField,out.classifierIndex,ctx.nFeatures,component,ctx.contextId,[]);
            if isempty(values)
                out.message = sprintf('Measure %s could not be extracted as an exact %d-feature vector.',measure.measureId,ctx.nFeatures);
                out.diagnostic = diagnostic;
                return;
            end
            badcoords = v.params.badcoords;
            out.ok = true;
            out.message = sprintf('Exact feature vector %s contains %d value(s).',measure.measureId,numel(values));
            out.context = ctx;
            out.measure = measure;
            out.spatialMap = spatialMap;
            out.component = component;
            out.values = double(values(:));
            [out.featureNames,~,~] = NMResultsViewerTools.modelFeatureInspectionFeatureNames( ...
                NM,ctx.varind,ctx.nFeatures,(1:ctx.nFeatures)',ctx);
            out.badcoords = badcoords;
            out.diagnostic = diagnostic;
            if nargout > 1 && strcmp(measure.measureId,'feature_weight_mean')
                [se,~] = NMResultsViewerTools.modelFeatureInspectionReadFeatureVector( ...
                    v,measure.seSourceField,out.classifierIndex,ctx.nFeatures,component,ctx.contextId,[]);
                assert(numel(se)==numel(values),'Mean feature-weight dispersion has a mismatched feature axis.');
                dispersion.values = double(se(:));
                assert(ismember(v.CVRnorm,[1 2]),'Unsupported persisted CVR normalization.');
                labels = {'feature_weight_sd','feature_weight_ci95_halfwidth'};
                dispersion.metricId = labels{v.CVRnorm};
            end
        end


        function selection = getModelFeatureInspectionAdapterSelection(spec, inspection)
            % getModelFeatureInspectionAdapterSelection  Bind one canonical payload to a representation request.
            %
            % Cached Feature Inspection material is already canonical. Only the
            % representation request is validated here before binding one physical
            % context and one or more requested display measures.
            NMResultsViewerTools.modelFeatureInspectionValidateCachedPayload(spec,inspection);
            if ~strcmp(inspection.kind,'model_feature_inspection')
                error('NMResultsViewerTools:InvalidFeatureInspectionMetadataPayload', ...
                    'Adapter selection requires one model_feature_inspection payload.');
            end
            if ~inspection.ok
                error('NMResultsViewerTools:UnavailableFeatureInspectionPayload','%s',inspection.message);
            end

            physicalContextIds = inspection.resolvedSelection.physicalContextIds;
            if numel(physicalContextIds) ~= 1
                error('NMResultsViewerTools:AdapterRequiresOnePhysicalContext', ...
                    ['Representation adapters require one physical feature context; ' ...
                    'the canonical selection contains %d physical contexts.'], ...
                    numel(physicalContextIds));
            end
            physicalContextId = physicalContextIds{1};
            contextHits = find(strcmp({inspection.contexts.contextId},physicalContextId));
            if numel(contextHits) ~= 1
                error('NMResultsViewerTools:InvalidFeatureInspectionPhysicalContext', ...
                    'Canonical physical context %s resolves to %d payload contexts.', ...
                    physicalContextId,numel(contextHits));
            end
            context = inspection.contexts(contextHits);

            % nm2-allow: measureIds is a public representation-request boundary and accepts MATLAB/JSON text container forms.
            if isfield(spec,'measureIds') && ~isempty(spec.measureIds)
                rawMeasureIds = spec.measureIds;
                % nm2-allow: public representation requests may arrive as cell text, string arrays, or character arrays.
                if iscell(rawMeasureIds)
                    requestedMeasureIds = cell(1,numel(rawMeasureIds));
                    for measureIndex = 1:numel(rawMeasureIds)
                        value = rawMeasureIds{measureIndex};
                        % nm2-allow: validate each external measure identifier before it enters the canonical catalogue lookup.
                        if ~(ischar(value) || (isstring(value) && isscalar(value)))
                            error('NMResultsViewerTools:InvalidFeatureInspectionMeasureIds', ...
                                'measureIds{%d} must be one character vector or scalar string.',measureIndex);
                        end
                        requestedMeasureIds{measureIndex} = strtrim(char(string(value))); % nm2-allow: public measure identifier normalization at representation-request boundary
                    end
                elseif isstring(rawMeasureIds) % nm2-allow: public measureIds accepts MATLAB string-array transport
                    requestedMeasureIds = cellstr(strtrim(rawMeasureIds(:)'));
                elseif ischar(rawMeasureIds) % nm2-allow: public measureIds accepts MATLAB character-array transport
                    requestedMeasureIds = cellstr(strtrim(rawMeasureIds));
                    requestedMeasureIds = requestedMeasureIds(:)';
                else
                    error('NMResultsViewerTools:InvalidFeatureInspectionMeasureIds', ...
                        'measureIds must be a cell array of text, a string array, or a character array.');
                end
            else
                requestedMeasureId = spec.measureId;
                requestedMeasureIds = {strtrim(requestedMeasureId)};
            end
            if isempty(requestedMeasureIds) || any(cellfun(@isempty,requestedMeasureIds))
                error('NMResultsViewerTools:MissingFeatureInspectionMeasureId', ...
                    'Representation adapter selection requires at least one non-empty measure ID.');
            end
            requestedMeasureIds = unique(requestedMeasureIds,'stable');

            if isempty(inspection.measures)
                error('NMResultsViewerTools:UnavailableFeatureInspectionMeasure', ...
                    'The canonical Feature Inspection catalogue contains no measures.');
            end
            selectedMeasures = repmat(inspection.measures(1),1,numel(requestedMeasureIds));
            for measureIndex = 1:numel(requestedMeasureIds)
                measureId = requestedMeasureIds{measureIndex};
                hits = find(strcmp({inspection.measures.contextId},physicalContextId) & ...
                    strcmp({inspection.measures.measureId},measureId));
                if isempty(hits)
                    error('NMResultsViewerTools:UnavailableFeatureInspectionMeasure', ...
                        'Measure %s is unavailable for physical feature context %s.', ...
                        measureId,physicalContextId);
                end
                if numel(hits) ~= 1
                    error('NMResultsViewerTools:DuplicateFeatureInspectionMeasure', ...
                        'Measure %s resolves to %d catalogue entries for physical feature context %s.', ...
                        measureId,numel(hits),physicalContextId);
                end
                selectedMeasures(measureIndex) = inspection.measures(hits);
                if ~selectedMeasures(measureIndex).enabled
                    reason=selectedMeasures(measureIndex).disabledReason;
                    if isempty(reason), reason=sprintf('Measure %s is disabled.',measureId); end
                    error('NMResultsViewerTools:UnavailableFeatureInspectionMeasure','%s',reason);
                end
            end

            selection = struct( ...
                'scientificContractVersion',inspection.scientificContractVersion, ...
                'scientificAnnotation',inspection.scientificAnnotation, ...
                'resolvedSelection',inspection.resolvedSelection, ...
                'context',context, ...
                'measureIds',{requestedMeasureIds}, ...
                'measures',selectedMeasures);
        end

        function annotation = scientificResultAnnotation(NM,payload)
            % Purpose: Serialize an already-materialized performance/optimization payload into canonical Scientific Annotation.
            % Syntax: annotation = NMResultsViewerTools.scientificResultAnnotation(NM,payload)
            % Inputs: NM provides canonical analysis label/fusion metadata; payload is the resolved model-performance or optimization materialization.
            % Outputs: annotation is a validated NM-SCIENTIFIC-ANNOTATION-V7 record.
            % Authority and flow: Consumes resolved payload selectors/result containers; for multiclass performance, selectedOneVsRestClass plus resolved multiClassGroupNames determines material.classContrast/classIndex/className before Scientific Annotation mapping.
            % Scientific/state contract: Aggregate multi-class is all_classes; class-vs-REST is one_vs_rest with canonical class index/name. Downstream Scientific State/Directory consumers do not infer this from multiClassModeIndex.
            % Invariants: A one-vs-REST annotation requires the corresponding resolved group name; result target/native target identities must remain consistent with the payload authority.
            % Materialization and performance: Compact metadata projection only after payload materialization; no additional result loads, file/XML/atlas/annotation/mesh reads, voxel/vertex scans, or feature-scale allocations.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond the compact in-memory result/metric data described above; safe on the documented interactive Model Performance/selector path.
            % Failure semantics: Missing/inconsistent multiclass class identity raises InvalidScientificAnnotationPayload; Scientific Annotation validation errors propagate.
            % Side effects: None.
            % Consumers and dependencies: Model Performance/Optimization payload attachment, Scientific State/Directory, Report Builder and Cross-analysis.
            if ~isstruct(payload)||~isscalar(payload)||~isfield(payload,'analysisIndex') % nm2-allow: direct scientific annotation API admits partial caller payloads; require one resolved analysis coordinate.
                error('NMResultsViewerTools:InvalidScientificAnnotationPayload','Scientific result annotation requires one resolved payload.');
            end
            idx=round(double(payload.analysisIndex));
            if idx<1||~isstruct(NM)||~isfield(NM,'analysis')||~iscell(NM.analysis)||idx>numel(NM.analysis) % nm2-allow: direct scientific annotation API validates the caller-supplied NM analysis coordinate.
                error('NMResultsViewerTools:InvalidScientificAnnotationPayload','Scientific result annotation requires a valid analysis index.');
            end
            A=NM.analysis{idx};[label,modeflag,labelInfo]=NMResultsViewerTools.analysisLabelAndMode(NM,A);
            targetIdx=max(1,round(double(payload.targetIndex))); nTargets=1;
            if ~isempty(labelInfo.selectedColumns)
                nTargets = numel(labelInfo.selectedColumns);
            elseif isnumeric(label)&&~isempty(label) % nm2-allow: analysisLabelAndMode supports partial direct-API snapshots with a numeric target axis.
                nTargets=max(1,size(label,2));
            end
            [names,nativeIdx]=NMResultsViewerTools.analysisTargetLabelNames(NM,A,nTargets,labelInfo.selectedColumns);
            if targetIdx>nTargets,error('NMResultsViewerTools:InvalidScientificAnnotationPayload','Resolved target position exceeds the effective analysis label count.');end
            kind=payload.kind;
            if strcmp(kind,'model_optimization')
                material=NMResultsViewerScientificAnnotation.optimizationMaterialTemplate();
                material.modelSource=char(string(NMResultsViewerTools.structAnyField(payload,'selectedModelSource',''))); % nm2-allow: directly called annotation adapter accepts optional caller model-source text.
                material.resultContainer='GDdims.grid';
                if strcmp(material.modelSource,'meta'),material.resultContainer='META';elseif startsWith(material.modelSource,'modality:'),material.resultContainer=sprintf('GDdims{%s}.grid',strrep(material.modelSource,'modality:',''));end
            else
                material=NMResultsViewerScientificAnnotation.performanceMaterialTemplate();
                material.payloadType=kind; material.modelSource=char(string(NMResultsViewerTools.structAnyField(payload,'selectedModelSource',''))); % nm2-allow: directly called annotation adapter accepts optional caller model-source text.
                prefix='GDdims'; if strcmp(material.modelSource,'meta'),prefix='META';elseif startsWith(material.modelSource,'modality:'),prefix=sprintf('GDdims{%s}',strrep(material.modelSource,'modality:',''));end
                switch kind
                    case 'classification'
                        material.resultContainer=[prefix '.BinClass'];
                    case 'regression'
                        material.resultContainer=[prefix '.Regr'];
                    case 'multiclass'
                        material.resultContainer=[prefix '.MultiClass'];
                        selectedClass=double(NMResultsViewerTools.structAnyField(payload,'selectedOneVsRestClass',0));
                        if isscalar(selectedClass)&&isfinite(selectedClass)&&selectedClass>=1&&selectedClass==round(selectedClass)
                            groupNames=NMResultsViewerTools.structAnyField(payload,'multiClassGroupNames',{});
                            if ~iscell(groupNames)||numel(groupNames)<selectedClass % nm2-allow: selected class must lie on the group-name axis; direct annotations can supply an incomplete group list.
                                error('NMResultsViewerTools:InvalidScientificAnnotationPayload', ...
                                    'Class-vs-REST performance annotation requires the resolved multiClassGroupNames entry.');
                            end
                            material.classContrast='one_vs_rest';
                            material.classIndex=selectedClass;
                            material.className=char(string(groupNames{selectedClass}));
                        else
                            material.classContrast='all_classes';
                            material.classIndex=NaN;
                            material.className='';
                        end
                    otherwise
                        material.resultContainer=prefix;
                end
            end
            material.analysisIndex=idx;material.analysisMode=modeflag;material.targetIndex=targetIdx;
            material.targetNativeIndex=nativeIdx(targetIdx); material.targetSource=labelInfo.source;
            material.targetLabelName=names{targetIdx};
            material.sourceId=char(string(NMResultsViewerTools.structAnyField(payload,'selectedSource',NMResultsViewerTools.structAnyField(payload,'source','cv')))); % nm2-allow: direct annotation API permits optional caller-supplied source identity text.
            oocv = NMResultsViewerTools.structAnyField(payload, 'oocv', struct());
            material.subgroupIndex=NaN;
            subgroupIndex=NaN;
            if isfield(oocv,'selectedSubgroupIndex'), subgroupIndex=oocv.selectedSubgroupIndex; end % nm2-allow: OOCV scientific annotation can receive a payload without subgroup context.
            if isfinite(subgroupIndex)&&subgroupIndex>=1&&subgroupIndex==round(subgroupIndex), material.subgroupIndex=subgroupIndex; end
            [isOOCVMaterial,oocvIndex]=NMResultsViewerTools.parseOOCVSourceId(material.sourceId);
            if isOOCVMaterial
                resultField='';
                if isfield(oocv,'resultField'), resultField=oocv.resultField; end % nm2-allow: OOCV scientific annotation rejects unavailable resolved resultField below.
                if isempty(resultField)
                    error('NMResultsViewerTools:InvalidScientificAnnotationPayload','OOCV performance annotation requires the resolved resultField material coordinate.');
                end
                material.resultContainer=sprintf('OOCV{%d}.%s',oocvIndex,resultField);
            end
            material.classifierIndex=max(1,round(double(payload.classifierIndex))); material.fusionMode=NMResultsViewerTools.analysisFusionMode(A);
            if strcmp(kind,'model_optimization'),annotation=NMResultsViewerScientificAnnotation.fromOptimization(material);else,annotation=NMResultsViewerScientificAnnotation.fromPerformance(material);end
        end

        function c = performanceScientificCapability(id,expectedKind,context)
            P=@NMResultsViewerScientificCapability.provide;
            all=[P('performance_payload','scientific_artefact','performance','performance_payload'), ...
                P('performance_summary','scientific_artefact','performance','performance_summary'), ...
                P('performance_primary_plot_data','scientific_artefact','performance','primary_plot_data'), ...
                P('confusion_analysis','scientific_artefact','performance','confusion_analysis'), ...
                P('roc_analysis','scientific_artefact','performance','roc_analysis'), ...
                P('score_distribution','scientific_artefact','performance','score_distribution'), ...
                P('model_permutation','scientific_artefact','performance','model_permutation'), ...
                P('extra_label_permutation','scientific_artefact','performance','extra_label_permutation'), ...
                P('subject_qc_scalars','scientific_artefact','quality_control','subject_qc_scalars'), ...
                P('performance_summary_view','visualization','',''),P('primary_performance_plot','visualization','',''), ...
                P('confusion_matrix','visualization','',''),P('roc_curve','visualization','',''), ...
                P('probability_distribution','visualization','',''),P('model_permutation_histogram','visualization','',''), ...
                P('extra_label_permutation_gallery','visualization','',''),P('subject_qc_scalar_view','visualization','','')];
            ids={all.id};
            if isstruct(context)&&isfield(context,'payload')
                q=context.payload;ids={};
                if isstruct(q)&&isfield(q,'kind')&&strcmp(char(string(q.kind)),expectedKind)&&isfield(q,'ok')&&logical(q.ok)
                    ids={'performance_payload'};
                    if ~isempty(q.summaryRows)||(isfield(q,'multiClassTables')&&~isempty(q.multiClassTables)),ids(end+1:end+2)={'performance_summary','performance_summary_view'};end % nm2-allow: multiclass table material is optionally added by the multiclass payload producer.
                    if ~isempty(q.classPlot)||~isempty(q.regressionPlot)||~isempty(q.multiClassPlot),ids(end+1:end+2)={'performance_primary_plot_data','primary_performance_plot'};end
                    if logical(q.confusion.ok)||~isempty(q.confusion.matrix),ids(end+1:end+2)={'confusion_analysis','confusion_matrix'};end
                    if logical(q.roc.ok)||~isempty(q.roc.points),ids(end+1:end+2)={'roc_analysis','roc_curve'};end
                    if ~isempty(q.pies)||~isempty(q.scoreRows)||(isfield(q,'multiClassSummaryVisuals')&&~isempty(q.multiClassSummaryVisuals)),ids(end+1:end+2)={'score_distribution','probability_distribution'};end % nm2-allow: multiclass summary visuals exist only when their payload producer emits this optional family.
                    if ~isempty(q.modelPermutation.rows)
                        modes={q.modelPermutation.rows.mode};if any(~strcmp(modes,'extra_label')),ids(end+1:end+2)={'model_permutation','model_permutation_histogram'};end;if any(strcmp(modes,'extra_label')),ids(end+1:end+2)={'extra_label_permutation','extra_label_permutation_gallery'};end
                    end
                    if logical(q.subjectQCScalars.ok),ids(end+1:end+2)={'subject_qc_scalars','subject_qc_scalar_view'};end
                end
            end
            c=NMResultsViewerScientificCapability.contract(id,{},NMResultsViewerScientificCapability.subset(all,unique(ids,'stable')));
        end

        function [types, scientificState, seedPayloads] = resultTypesForAnalysis(NM, idx, spec, analysisCatalogue)
            % Purpose: Determine Results Viewer result-type availability without materializing unselected scientific payloads.
            % Syntax: [types,scientificState,seedPayloads] = NMResultsViewerTools.resultTypesForAnalysis(NM,idx,spec[,analysisCatalogue])
            % Authority: Completed-analysis task identity comes from analysis.params.label; result-family admission reuses performance/model/feature/MLI authorities.
            tmpl = struct('id','classification','label','Model performance','enabled',false,'reason','Scientific State contains no model-performance payload.');
            types = repmat(tmpl,1,6);
            types(2)=struct('id','regression','label','Model performance','enabled',false,'reason','Scientific State contains no regression model-performance payload.');
            types(3)=struct('id','model_optimization','label','Model optimization','enabled',false,'reason','Scientific State contains no model-optimization payload.');
            types(4)=struct('id','model_feature_inspection','label','Model feature inspection','enabled',false,'reason','Scientific State contains no model-feature-inspection payload.');
            types(5)=struct('id','mli','label','Model interpretation','enabled',false,'reason','Scientific State contains no MLI payload.');
            types(6)=struct('id','comparison','label','Cross-analysis','enabled',false,'reason','Cross-analysis requires at least two completed analyses.');
            seedPayloads=struct('performance',struct(),'optimization',struct(),'feature',struct(),'mli',struct());
            scientificState=struct();
            % nm2-allow: public result-type inventory selector permits the no-analysis state and validates the requested analysis index.
            if idx<1||idx>numel(NM.analysis),return;end

            % nm2-allow: public inventory API supports the documented optional compact analysis-catalogue argument.
            compactInventory=nargin>=4&&~isempty(analysisCatalogue);
            if compactInventory
                row=analysisCatalogue([analysisCatalogue.index]==idx);
                if isempty(row),return;end
                A=NM.analysis{idx};
                [~,modeflag]=NMResultsViewerTools.analysisLabelAndMode(NM,A);
                isRegression=strcmp(modeflag,'regression');
                if strcmp(NMResultsViewerTools.analysisFusionMode(A),'late')
                    q=NMResultsViewerTools.modelSourcesForAnalysis(NM,idx,'regression',spec); hasRegression=~isempty(q)&&any([q.enabled]);
                    q=NMResultsViewerTools.modelSourcesForAnalysis(NM,idx,'classification',spec); hasBinary=~isempty(q)&&any([q.enabled]);
                    q=NMResultsViewerTools.modelSourcesForAnalysis(NM,idx,'multiclass',spec); hasMulticlass=~isempty(q)&&any([q.enabled]);
                else
                    GD=NMResultsViewerTools.primaryGDdims(A);
                    [hasRegression,~]=NMResultsViewerTools.performanceModelSourceAvailable(GD,'regression');
                    [hasBinary,~]=NMResultsViewerTools.performanceModelSourceAvailable(GD,'classification');
                    [hasMulticlass,~]=NMResultsViewerTools.performanceModelSourceAvailable(GD,'multiclass');
                end
                if isRegression
                    if hasRegression,types(2).enabled=true;types(2).reason='';end
                elseif hasBinary
                    types(1).enabled=true;types(1).reason='';
                elseif hasMulticlass
                    types(1).id='multiclass';types(1).enabled=true;types(1).reason='';
                elseif hasRegression
                    types(2).enabled=true;types(2).reason='';
                end
                q=NMResultsViewerTools.modelSourcesForAnalysis(NM,idx,'model_optimization',spec);
                if ~isempty(q)&&any([q.enabled]),types(3).enabled=true;types(3).reason='';end
                [featureAvailable,featureReason]=NMResultsViewerTools.modelFeatureInspectionAvailability(NM,idx);
                if featureAvailable,types(4).enabled=true;types(4).reason='';else,types(4).reason=featureReason;end
                if NMResultsViewerMLITools.hasAnyStoredResult(NM,idx)
                    types(5).enabled=true;types(5).reason='';
                else
                    types(5).reason='No persisted MLI result is stored for this analysis.';
                end
                if sum([analysisCatalogue.completed])>=2,types(6).enabled=true;types(6).reason='';end
                return;
            end

            doProfile=NMResultsViewerTools.profileEnabled(spec);
            [scientificState,seedPayloads]=NMResultsViewerTools.scientificStateForAnalysis(NM,idx,spec);
            tAdmission=tic;
            regressionCriterion=struct('path','schema.modelResult.type','op','eq','value','regression');
            binaryCriterion=struct('path','schema.modelResult.type','op','eq','value','binary_classification');
            multiclassCriterion=struct('path','schema.modelResult.type','op','eq','value','multiclass_classification');
            if NMResultsViewerScientificState.hasArtefact(scientificState,'performance_payload',regressionCriterion)
                types(2).enabled=true;types(2).reason='';
            elseif NMResultsViewerScientificState.hasArtefact(scientificState,'performance_payload',binaryCriterion)
                types(1).enabled=true;types(1).reason='';
            elseif NMResultsViewerScientificState.hasArtefact(scientificState,'performance_payload',multiclassCriterion)
                types(1).id='multiclass';types(1).enabled=true;types(1).reason='';
            end
            if NMResultsViewerScientificState.hasArtefact(scientificState,'optimization_payload'),types(3).enabled=true;types(3).reason='';end
            if NMResultsViewerScientificState.hasArtefact(scientificState,'feature_inspection_payload'),types(4).enabled=true;types(4).reason='';end
            if NMResultsViewerMLITools.hasAnyStoredResult(NM,idx),types(5).enabled=true;types(5).reason='';else,types(5).reason='No persisted MLI result is stored for this analysis.';end
            completedCatalogue=NMResultsViewerTools.listAnalyses(NM);
            if sum([completedCatalogue.completed])>=2,types(6).enabled=true;types(6).reason='';end
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]       results result-type admission after State:      %.3fs\n',toc(tAdmission));
        end

        function resultType = defaultPerformanceResultType(NM, analysisIndex, varargin)
            % Purpose: Resolve the default Model Performance payload type using the established Results Viewer selector semantics.
            % Syntax: resultType = NMResultsViewerTools.defaultPerformanceResultType(NM,analysisIndex,types)
            % Inputs: NM/analysisIndex identify the analysis; optional types is an already-materialized resultTypesForAnalysis catalogue for that same analysis.
            % Outputs: Canonical classification, regression, or multiclass payload type selected exactly as the existing Results Viewer Performance default.
            % Authority and flow: resultTypesForAnalysis owns Performance availability; this resolver selects only enabled classification/regression rows, defaults to classification when neither exists, then delegates classifier-1/source-cv promotion to effectiveResultTypeFromSpec. Supplying types reuses resident Scientific State output without changing selection semantics.
            % Scientific/state contract: A stored multiclass row is not selected directly; multiclass is reached only through the established effectiveResultTypeFromSpec classifier authority, preserving legacy/default selector behavior.
            % Invariants: The optional catalogue is consumed, never reinterpreted into a new result family; classifierIndex=1 and source=cv remain the established default Performance coordinates.
            % Materialization and performance: With supplied types this is compact O(number of result-type rows) metadata work. Without types it queries the same result-type authority in compact inventory mode and never constructs full single-analysis Scientific State merely to choose the default Performance family.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays beyond delegated resultTypesForAnalysis work when types is omitted.
            % Failure semantics: Delegated Results Viewer authority errors propagate explicitly; no alternate fallback chain is introduced.
            % Side effects: None.
            % Consumers and dependencies: Scientific State analysis-set inventory and Report Builder consumers needing the established default Performance result type.
            if isempty(varargin)
                analysisCatalogue=NMResultsViewerTools.listAnalyses(NM);
                types=NMResultsViewerTools.resultTypesForAnalysis(NM,analysisIndex,struct(),analysisCatalogue);
            else
                types=varargin{1};
            end
            resultType='classification';
            selected='';
            for ii=1:numel(types)
                id=types(ii).id;
                if logical(types(ii).enabled)&&any(strcmp(id,{'classification','regression'}))
                    selected=id;break;
                end
            end
            if isempty(selected),return;end
            selectorSpec=struct('analysisIndex',analysisIndex,'classifierIndex',1,'source','cv');
            resultType=NMResultsViewerTools.effectiveResultTypeFromSpec(NM,analysisIndex,selected,selectorSpec);
        end

        function criterion = modelOptimizationCriterionIdentity(NM, analysisIndex)
            % Existing selector delegates exact criterion identity to the shared ML authority.
            criterion=NMPerformanceMetricTools.optimizationCriterion(NM.analysis{analysisIndex});
        end

        function reference = modelOptimizationRandomReference(criterion,classifier)
            % Purpose: Resolve the scientifically defined random-classifier reference for one Model Optimization criterion and classifier context.
            % Syntax: reference = NMResultsViewerTools.modelOptimizationRandomReference(criterion,classifier)
            % Inputs: Canonical criterion identity plus one modelOptimizationClassifierOptions row carrying resultType and classCount.
            % Outputs: Fixed-schema available/value/label/resultType/classCount/reason reference metadata.
            % Authority and flow: Criterion code owns metric semantics; the canonical classifier option owns classification kind and class count. Cross-analysis consumes this result without parsing labels or reopening NM.
            % Scientific/state contract: References are emitted only for classification criteria whose uninformed uniform-classifier expectation is defined without class-prevalence assumptions. Regression and prevalence-dependent criteria remain unavailable.
            % Invariants: K-class accuracy/sensitivity/FPR/G-mean/BAC use 1/K; specificity uses (K-1)/K; AUC uses 0.5; MCC/SCC use zero; likelihood ratios use one. Percentage criteria remain on their native 0-100 scale.
            % Materialization and performance: O(1) compact metadata work; no files, result arrays, XML, atlas/mesh resources, voxel/vertex scans, or feature-scale arrays. Safe on explicit and retained selector paths.
            % Failure semantics: Missing/invalid criterion or classifier identity returns available=false with a diagnostic reason; it never guesses from display text.
            % Side effects: None.
            % Consumers and dependencies: Cross-analysis statistical plot payload construction.
            reference=struct('available',false,'value',NaN,'label','','resultType','','classCount',NaN,'reason','Random performance is not defined for this context.');
            if ~isstruct(criterion)||~isfield(criterion,'code')||~isstruct(classifier),reference.reason='Criterion or classifier identity is missing.';return;end
            resultType='';if isfield(classifier,'resultType'),resultType=NMResultsViewerTools.normalizeResultType(classifier.resultType);end
            reference.resultType=resultType;
            if ~ismember(resultType,{'classification','multiclass'}),reference.reason='Random-performance references apply only to classification.';return;end
            K=NaN;if isfield(classifier,'classCount')&&isfinite(double(classifier.classCount)),K=round(double(classifier.classCount));end
            if K<2,reference.reason='The canonical classification class count is unavailable.';return;end
            reference.classCount=double(K);code=round(double(criterion.code));value=NaN;
            switch code
                case {1,2,4}
                    value=100/K;
                case 3
                    value=100*(K-1)/K;
                case {6,10}
                    value=0;
                case 7
                    value=0.5;
                case 13
                    value=1/K;
                case {14,17}
                    value=100/K;
                case {22,23}
                    value=1;
                otherwise
                    reference.reason='This criterion has no prevalence-independent random-performance reference.';return;
            end
            reference.available=true;reference.value=double(value);reference.label=sprintf('Random performance (%d classes)',K);reference.reason='';
        end

        function density = violinDensity(values)
            % Purpose: Produce the single Gaussian-KDE violin-density primitive shared by OOCV and Cross-analysis.
            % Syntax: density = NMResultsViewerTools.violinDensity(values)
            % Inputs: One numeric vector of canonical values.
            % Outputs: Ordered y/normalized-half-width rows with explicit zero-width tapered tails.
            % Authority and flow: Presentation density uses the established Silverman-bandwidth implementation; callers retain ownership of scientific values and summaries.
            % Scientific/state contract: KDE geometry is non-inferential and never replaces, filters or transforms the supplied values used for statistics.
            % Invariants: Finite values only affect presentation density; output width is normalized to 0.32 and both tails close at zero width.
            % Materialization and performance: O(N*80) compact presentation geometry over resident vectors; no files/resources or feature-scale arrays. Safe for explicit plot materialization, not a retained high-frequency loop.
            % Failure semantics: Empty finite input returns an empty fixed-schema array; a singleton produces a deterministic tapered marker.
            % Side effects: None.
            % Consumers and dependencies: OOCV violin payloads and Cross-analysis statistical plot payloads; silvermanBandwidth.
            tmpl = struct('y',NaN,'width',NaN);
            values = double(values(:));
            values = values(isfinite(values));
            if isempty(values), density = repmat(tmpl, 1, 0); return; end
            if numel(values) == 1
                y = values(1) + [-0.001 0 0.001]';
                w = [0 0.32 0]';
            else
                yr = max(values) - min(values);
                if yr == 0, yr = max(0.002, abs(values(1))*0.01); end
                y = linspace(min(values)-0.08*yr, max(values)+0.08*yr, 80)';
                bw = NMResultsViewerTools.silvermanBandwidth(values);
                d = zeros(size(y));
                for jj = 1:numel(values)
                    z = (y - values(jj)) ./ bw;
                    d = d + exp(-0.5*z.^2);
                end
                d = d ./ (numel(values) * bw * sqrt(2*pi));
                if max(d) > 0, w = d ./ max(d) * 0.32; else, w = zeros(size(d)); end
                tailPad = max(0.025*yr, 0.35*bw);
                y = [y(1)-tailPad; y; y(end)+tailPad];
                w = [0; w; 0];
            end
            density = repmat(tmpl, 1, numel(y));
            for ii = 1:numel(y), density(ii) = struct('y',double(y(ii)),'width',double(w(ii))); end
        end

        function opts = classifierOptions(NM, idx, resultType, spec)
            tmpl = struct('index',1,'label','Classifier 1','enabled',false,'reason','');
            opts = tmpl([]);
            % nm2-allow: public classifier selector permits the no-analysis state and validates the requested analysis index.
            if idx<1||idx>numel(NM.analysis),return;end
            A=NM.analysis{idx};
            kind=NMResultsViewerTools.normalizeResultType(resultType);
            if strcmp(kind,'model_optimization')
                opts=NMResultsViewerTools.modelOptimizationClassifierOptions(NM,idx,spec);
                return;
            end

            if ismember(kind,{'mli','model_feature_inspection'})
                [~,analysisMode]=NMResultsViewerTools.analysisLabelAndMode(NM,A);
                if strcmp(analysisMode,'regression')
                    opts=tmpl;opts(1).label='Regression model';opts(1).enabled=true;return;
                end
                resultKind='classification';
            else
                resultKind=kind;
            end
            [ok,GD]=NMResultsViewerTools.resultGDForSpec(NM,idx,resultKind,spec);
            if ~ok,return;end
            switch kind
                case 'regression'
                    opts=tmpl;opts(1).label='Regression model';opts(1).enabled=true;
                case {'mli','model_feature_inspection'}
                    n=numel(GD.BinClass);
                    opts=repmat(tmpl,1,n);
                    for i=1:n,opts(i).index=i;opts(i).label=NMResultsViewerTools.classifierLabel(A,i);opts(i).enabled=true;end
                case 'multiclass'
                    nBin=numel(GD.BinClass);
                    opts=tmpl;opts(1).index=nBin+1;opts(1).label='Multi-group classifier';opts(1).enabled=true;
                otherwise
                    n=numel(GD.BinClass);
                    % nm2-allow: nk_MultiPerfComp conditionally writes GD.MultiClass only for multi-group classification output.
                    hasMulti=isfield(GD,'MultiClass')&&~isempty(GD.MultiClass);
                    opts=repmat(tmpl,1,n+double(hasMulti));
                    for i=1:n,opts(i).index=i;opts(i).label=NMResultsViewerTools.classifierLabel(A,i);opts(i).enabled=true;end
                    if hasMulti
                        opts(n+1).index=n+1;opts(n+1).label='Multi-group classifier';opts(n+1).enabled=true;
                        opts(n+1).reason='';
                    end
            end
        end

        function resultType = effectiveResultTypeFromSpec(NM, idx, resultType, spec)
            % Purpose: Resolve the effective canonical result type after source/classifier context normalization.
            % Syntax: resultType = NMResultsViewerTools.effectiveResultTypeFromSpec(NM,idx,resultType,spec)
            % Inputs: NM/idx identify the analysis; resultType is requested type; spec contains source/classifier selectors.
            % Outputs: resultType is the normalized canonical type.
            % Authority and flow: normalizeResultType owns aliases; classification may resolve to multiclass through the existing classifier authority. model_optimization and comparison are terminal top-level types and are returned unchanged.
            % Scientific/state contract: comparison cannot be rewritten to classification by OOCV/source normalization.
            % Invariants: Cross-analysis retains a distinct result-type identity independent of single-analysis source state.
            % Materialization and performance: Metadata-only O(1) normalization; no files/resources or scientific payload materialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond the compact in-memory result/metric data described above; safe on the documented interactive Model Performance/selector path.
            % Failure semantics: Established invalid/OOCV normalization rules apply; no new fallback is introduced for comparison.
            % Side effects: None.
            % Consumers and dependencies: buildInitialState/getPayload selector flow.
            resultType = NMResultsViewerTools.normalizeResultType(resultType);
            [isOOCVSource, ~] = NMResultsViewerTools.parseOOCVSourceId(spec.source);
            if strcmp(resultType, 'classification') && NMResultsViewerTools.isMultiGroupClassifierRequest(NM, spec, idx)
                resultType = 'multiclass';
            end
            if ismember(resultType, {'model_optimization','comparison'})
                return;
            end
            if isOOCVSource
                if ~ismember(resultType, {'classification','regression','multiclass','mli'})
                    resultType = 'classification';
                end
                return;
            end
        end

        function targetIdx = analysisLocalTargetIndex(NM, idx, targets, spec)
            % analysisLocalTargetIndex  Resolve target identity from analysis-local Scientific State.
            targetState=NMResultsViewerScientificState.targetStateForAnalysis(NM,idx);
            if targetState.cardinality==1
                targetIdx=targetState.soleNativeIndex;
                return;
            end
            targetIdx=NMResultsViewerTools.selectedTargetIndex(targets,spec);
        end

        function opts = targetOptions(NM, idx)
            % targetOptions  List effective targets while preserving native and compact result identities.
            tmpl=struct('index',1,'nativeIndex',1,'name','Target 1','label','Target 1', ...
                'enabled',true,'reason','','resultIndex',1,'analyzed',true);
            opts=tmpl;
            % nm2-allow: public target selector permits the no-analysis state and validates the requested analysis index.
            if idx<1||idx>numel(NM.analysis),return;end
            A=NM.analysis{idx};
            [label,modeflag,labelInfo]=NMResultsViewerTools.analysisLabelAndMode(NM,A);
            effectiveLabel=label;
            if ~isempty(labelInfo.selectedColumns),effectiveLabel=label(:,labelInfo.selectedColumns);end
            n=size(effectiveLabel,2);
            GD=NMResultsViewerTools.primaryGDdims(A);
            [analyzedIdx,resultIdx,disabledReason]=NMResultsViewerTools.analysisTargetIndexMap(A,GD,effectiveLabel,modeflag);
            [names,nativeIdx]=NMResultsViewerTools.analysisTargetLabelNames(NM,A,n,labelInfo.selectedColumns);
            opts=repmat(tmpl,1,n);
            for ii=1:n
                opts(ii).index=nativeIdx(ii);opts(ii).nativeIndex=nativeIdx(ii);opts(ii).name=names{ii};opts(ii).label=names{ii};
                hit=find(analyzedIdx==ii,1,'first');
                if isempty(hit)
                    opts(ii).enabled=false;opts(ii).analyzed=false;opts(ii).resultIndex=NaN;
                    if isempty(disabledReason),opts(ii).reason='This label was not analyzed by the selected model.';else,opts(ii).reason=disabledReason;end
                else
                    opts(ii).enabled=true;opts(ii).analyzed=true;opts(ii).resultIndex=resultIdx(hit);opts(ii).reason='';
                end
            end
        end

        function out = modelInterpretationSubjectScores(NM, spec)
            % modelInterpretationSubjectScores  Project canonical model scores onto subject identity for MLI ordering.
            %
            % Purpose:
            %   Provide the Model Interpretability viewspace with one compact score record per subject so the browser can
            %   reorder the subject catalogue by the active classifier/regressor score without redefining scientific state.
            %
            % Syntax:
            %   out = NMResultsViewerTools.modelInterpretationSubjectScores(NM,spec)
            %
            % Inputs/outputs:
            %   NM/spec identify the same analysis, source, target and classifier coordinates used by the active MLI
            %   Scientific State. out.rows contains caseId, score, full-precision numeric observed target (for regression),
            %   and expected/predicted display labels.
            %
            % Authority and flow:
            %   The existing Model Performance extraction remains the score authority. This method requests graph type 1,
            %   disables plot sorting/alternative x-axis/subgroup filtering, and projects only its subject-level score rows
            %   or points. It never derives scores from MLI relevance values and never uses visual point order as identity.
            %
            % Scientific/state contract:
            %   Subject ordering is presentation state only. Classification uses the active binary classifier's mean model
            %   score with expected/predicted class labels. Regression uses the model prediction and preserves
            %   the original numeric observed target (separately from its rounded display label)
            %   where available. OOCV labels may legitimately be unavailable.
            %
            % Materialization and performance:
            %   Called only when an MLI subject catalogue is requested. Cost is O(S) model-performance projection for S
            %   subjects plus the existing load_GDdims/OOCV result normalization; no feature-scale MLI arrays, atlas,
            %   annotation, mesh, voxel or vertex resources are read or copied. Retained subject switches do not call it.
            %
            % Failure semantics:
            %   Missing model-performance materialization returns ok=false and leaves canonical MLI subject order usable.
            %   Duplicate or incomplete score identities are not repaired by row order; unmatched subjects simply have no
            %   score metadata and remain selectable.
            %
            % Side effects: none.
            % Consumers/dependencies: NMResultsViewerMLITools subject catalogue construction.
            tmpl = struct('caseId','','score',NaN,'observedNumeric',NaN,'expected','','predicted','');
            out = struct('ok',false,'message','Subject model scores are unavailable.', ...
                'modelKind','','scoreLabel','Model score','expectedLabel','Expected class', ...
                'predictedLabel','Predicted class','rows',tmpl([]));
            [~,spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            idx = spec.analysisIndex;
            if ~isfinite(idx) || idx < 1 || ~isstruct(NM) || ~isfield(NM,'analysis') || ...
                    ~iscell(NM.analysis) || idx > numel(NM.analysis)
                out.message = 'Subject model scores require one valid completed analysis.';
                return;
            end
            A = NM.analysis{round(idx)};
            [~, modeflag] = NMResultsViewerTools.analysisLabelAndMode(NM,A);
            isRegression = strcmp(modeflag,'regression');
            % Build a minimal Model Performance request. MLI feature-context,
            % subject, relevance-measure and display-state fields are not valid
            % coordinates of the score authority and must not leak into it.
            scoreSpec = struct();
            scoreSpec.analysisIndex = idx;
            scoreSpec.source = spec.source;
            scoreSpec.modelSource = spec.modelSource;
            scoreSpec.classifierIndex = spec.classifierIndex;
            scoreSpec.targetIndex = spec.targetIndex;
            targetNativeIndex = spec.targetNativeIndex;
            if isfinite(targetNativeIndex), scoreSpec.targetNativeIndex = targetNativeIndex; end
            scoreSpec.graphType = 1;
            scoreSpec.plotSort = false;
            scoreSpec.colorSwap = false;
            scoreSpec.percentRank = false;
            scoreSpec.probTransform = false;
            scoreSpec.xAxisExpression = '';
            scoreSpec.xAxisLabel = '';
            scoreSpec.subgroupExpression = '';
            scoreSpec.oocvSubgroupIndex = 1;
            source = scoreSpec.source;
            [isOOCVSource,~] = NMResultsViewerTools.parseOOCVSourceId(source);
            try
                if isRegression
                    scoreSpec.resultType = 'regression';
                    P = NMResultsViewerTools.getRegressionPayload(NM,scoreSpec);
                    out.modelKind = 'regression';
                    out.scoreLabel = 'Prediction';
                    out.expectedLabel = 'Observed target';
                    out.predictedLabel = '';
                    if ~logical(P.ok)
                        out.message = NMResultsViewerTools.scalarTextField(P,'message','Regression score materialization is unavailable.');
                        return;
                    end
                    raw = P.scoreRows;
                    raw = raw(:)';
                    rows = repmat(tmpl,1,numel(raw));
                    for ii=1:numel(raw)
                        r=raw(ii);caseId=r.case;
                        score=r.score;
                        observed=r.observed;
                        expected='';if isfinite(observed),expected=sprintf('%.6g',observed);end
                        rows(ii)=struct('caseId',caseId,'score',score,'observedNumeric',observed, ...
                            'expected',expected,'predicted','');
                    end
                    out.rows=rows;
                else
                    scoreSpec.resultType = 'classification';
                    P = NMResultsViewerTools.getClassificationPayload(NM,scoreSpec);
                    out.modelKind = 'classification';
                    out.expectedLabel = 'Expected class';
                    out.predictedLabel = 'Predicted class';
                    if ~logical(P.ok)
                        out.message = NMResultsViewerTools.scalarTextField(P,'message','Classification score materialization is unavailable.');
                        return;
                    end
                    out.scoreLabel = NMResultsViewerTools.scalarTextField(P.classPlot,'yLabel','Model score');
                    % scoreRows is the canonical Model Performance subject table
                    % for both CV and OOCV. Do not project from rendered plot
                    % geometry: plot points are presentation material and may be
                    % sorted, filtered or represented by another graph family.
                    raw = P.scoreRows;
                    raw = raw(:)';
                    rows = repmat(tmpl,1,numel(raw));
                    for ii=1:numel(raw)
                        r=raw(ii);
                        rows(ii)=struct('caseId',r.case, ...
                            'score',r.score, ...
                            'observedNumeric',NaN, ...
                            'expected',r.expected, ...
                            'predicted',r.predicted);
                    end
                    out.rows=rows;
                end
            catch ME
                out.message = sprintf('Subject model-score projection failed: %s',ME.message);
                return;
            end
            validIds = ~cellfun(@isempty,{out.rows.caseId});
            finiteScores = isfinite([out.rows.score]);
            scoreRowsAvailable = validIds & finiteScores;
            out.ok = any(scoreRowsAvailable);
            if out.ok
                out.message = sprintf('Resolved finite model scores for %d subject(s) in the active scientific context.',sum(scoreRowsAvailable));
            elseif any(validIds)
                out.message = 'The active model result exposes subject identities but no finite scores for ordering.';
            else
                out.message = 'The active model result exposes no subject identities for score ordering.';
            end
        end


        function analyses = listAnalyses(NM)
            % Purpose: Return the canonical Results Viewer analysis catalogue.
            % Syntax: analyses = NMResultsViewerTools.listAnalyses(NM)
            % Inputs: NM is the read-only workspace.
            % Outputs: analyses contains stable index/id/title/status/completion/task and high-level stored-result availability fields for each analysis.
            % Authority and flow: This public method is the Results Viewer owner of analysis catalogue projection. Peer consumers, including Cross-analysis and Report Builder, call it instead of traversing NM.analysis independently.
            % Scientific/state contract: Catalogue fields describe analysis identity/availability only; they do not constitute Scientific Annotation or materialize model results.
            % Invariants: One row per NM.analysis entry in native order; completion follows the existing analysis status contract; consumers must not duplicate this traversal.
            % Materialization and performance: O(number of analyses) compact metadata inspection; may inspect primary GDdims field presence but reads no files/XML/atlas/annotation/mesh resources, scans no voxels/vertices, and creates no feature-scale arrays. Safe for interactive catalogue refresh.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond the compact in-memory result/metric data described above; safe on the documented interactive Model Performance/selector path.
            % Failure semantics: Missing/invalid NM.analysis yields an empty catalogue; individual optional availability fields default false/unknown without inventing scientific results.
            % Side effects: None.
            % Consumers and dependencies: Results Viewer selectors, Cross-analysis, Report Builder and analysis-selection UI.
            tmpl = struct('index',0, 'id','', 'title','', 'status',NaN, 'statusLabel','unknown', ...
                'completed',false, 'rootdir','', 'mode','unknown', 'hasClassification',false, ...
                'hasRegression',false, 'hasOOCV',false, 'hasVisualization',false, 'hasMLI',false, ...
                'summary','');
            n = 0;
            if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) % nm2-allow: public catalogue accepts empty/uninitialized NM before nk_InitAnalysisPrep writes analysis cells.
                n = numel(NM.analysis);
            end
            analyses = repmat(tmpl, 1, n);
            for i = 1:n
                A = NM.analysis{i};
                analyses(i).index = i;
                analyses(i).id = NMResultsViewerTools.analysisId(A, i);
                analyses(i).title = NMResultsViewerTools.analysisTitle(A, i);
                analyses(i).status = NMResultsViewerTools.statusValue(A);
                analyses(i).statusLabel = NMResultsViewerTools.statusLabel(analyses(i).status);
                analyses(i).completed = ~isnan(analyses(i).status) && analyses(i).status >= 1;
                GD = NMResultsViewerTools.primaryGDdims(A);
                if ~isempty(GD)
                    analyses(i).hasClassification = isfield(GD,'BinClass') || isfield(GD,'MultiClass'); % nm2-allow: nk_MLOptimizerPrep writes classification result families conditionally; catalogue admission must detect either family.
                    analyses(i).hasRegression = isfield(GD,'Regr'); % nm2-allow: nk_MLOptimizerPrep writes Regr only for regression; this public catalogue reports family presence.
                end
                if analyses(i).hasClassification, analyses(i).mode = 'classification'; elseif analyses(i).hasRegression, analyses(i).mode = 'regression'; end
                if isstruct(A) % nm2-allow: public Results Viewer catalogue accepts incomplete NM.analysis rows before nk_InitAnalysisPrep writes completed records.
                    if isfield(A,'rootdir') && ~isempty(A.rootdir), analyses(i).rootdir = A.rootdir; end % nm2-allow: public catalogue may receive partially created analysis entries without nk_InitAnalysisPrep rootdir.
                    analyses(i).hasOOCV = isfield(A,'OOCV') && ~isempty(A.OOCV); % nm2-allow: nk_OOCVPrep only writes analysis.OOCV after application execution.
                    analyses(i).hasVisualization = isfield(A,'visdata') && ~isempty(A.visdata); % nm2-allow: nk_VisModelsPrep conditionally writes analysis.visdata only when visualization executes.
                    analyses(i).hasMLI = isfield(A,'MLI') && ~isempty(A.MLI); % nm2-allow: nk_MLInterpreterPrep conditionally persists analysis.MLI; unexecuted analyses lack the family.
                end
                analyses(i).summary = NMResultsViewerTools.analysisSummary(A, GD);
            end
        end


        function sources = sourcesForAnalysis(NM, idx, resultType)
            % Purpose: Resolve available CV/OOCV application-result sources for one analysis/result family.
            % Syntax: sources = NMResultsViewerTools.sourcesForAnalysis(NM,idx,resultType)
            % Inputs: NM is read-only; idx is analysis index; resultType is the normalized/requested result family.
            % Outputs: sources is the fixed id/label/enabled/reason catalogue beginning with CV and followed by explicit OOCV/application descriptors where applicable.
            % Authority and flow: Reuses existing OOCV descriptor and MLI stored-result authorities. This public method is shared by single-analysis selectors and Cross-analysis source intersection.
            % Scientific/state contract: Application source is distinct from modelSource/fusion source; Cross-analysis may intersect these catalogues but does not rediscover OOCV containers itself.
            % Invariants: model_optimization/model_feature_inspection remain CV-only; unavailable OOCV is represented explicitly with a disabled reason.
            % Materialization and performance: Compact metadata/result-descriptor inspection; no atlas/annotation/mesh loads, voxel/vertex scans, feature-scale arrays, or arbitrary directory scans. No new file I/O is introduced by Cross-analysis.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond the compact in-memory result/metric data described above; safe on the documented interactive Model Performance/selector path.
            % Failure semantics: Invalid analysis returns disabled/default source catalogue; missing application results remain explicitly disabled.
            % Side effects: None.
            % Consumers and dependencies: buildInitialState, Cross-analysis workspace/table source eligibility, MLI and OOCV descriptor helpers.
            tmpl = struct('id','cv', 'label','Cross-validation', 'enabled',false, 'reason','No completed analysis selected.');
            sources = tmpl;
            % nm2-allow: public Results Viewer selector permits no-analysis state
            if idx < 1 || idx > numel(NM.analysis), return; end
            kind = NMResultsViewerTools.normalizeResultType(resultType);
            if strcmp(kind,'mli')
                sources(1).enabled = NMResultsViewerMLITools.hasStoredResult(NM,idx,'cv');
                if sources(1).enabled
                    sources(1).reason = '';
                else
                    sources(1).reason = 'No CV MLI result is stored for this analysis.';
                end
            else
                sources(1).enabled = true;
                sources(1).reason = '';
            end
            if ismember(kind,{'model_optimization','model_feature_inspection'}), return; end
            oocv = NMResultsViewerTools.oocvSourceDescriptors(NM,idx,kind);
            if isempty(oocv)
                sources(2) = struct('id','oocv:1', 'label','OOCV/application', 'enabled',false, ...
                    'reason',sprintf('No applied %s OOCV/application result container detected for this analysis.',kind));
                return;
            end
            out = repmat(tmpl,1,numel(oocv)+1);
            out(1) = sources(1);
            for ii = 1:numel(oocv)
                out(ii+1) = struct('id',sprintf('oocv:%d',oocv(ii).globalIndex), ...
                    'label',oocv(ii).descriptor,'enabled',true,'reason','');
            end
            sources = out;
        end
        function modes = multiClassModeOptions(NM, idx, spec)
            % multiClassModeOptions  Enumerate aggregate and class-vs-REST modes from the completed multiclass result.
            tmpl=struct('index',1,'id','1','label','Multi-group classification','enabled',false,'reason','No multi-class result payload detected.');
            modes=tmpl;
            % nm2-allow: public multi-class mode selector permits the no-analysis state and validates the requested analysis index.
            if idx<1||idx>numel(NM.analysis),return;end
            [~,analysisMode]=NMResultsViewerTools.analysisLabelAndMode(NM,NM.analysis{idx});
            if strcmp(analysisMode,'regression'),modes(1).reason='Multi-class modes do not apply to regression analyses.';return;end
            [ok,~]=NMResultsViewerTools.resultGDForSpec(NM,idx,'multiclass',spec);
            if ~ok,return;end
            groupNames=NMResultsViewerTools.groupNamesForAnalysis(NM,idx);
            modes=repmat(tmpl,1,numel(groupNames)+1);
            modes(1)=struct('index',1,'id','1','label','Multi-group classification','enabled',true,'reason','');
            for ii=1:numel(groupNames)
                modes(ii+1).index=ii+1;
                modes(ii+1).id=num2str(ii+1);
                modes(ii+1).label=sprintf('%s vs REST',groupNames{ii});
                modes(ii+1).enabled=true;modes(ii+1).reason='';
            end
        end

        function sources = modelSourcesForAnalysis(NM, idx, resultType, ~)
            % modelSourcesForAnalysis  Resolve modality/META result sources from the completed-analysis writer contract.
            tmpl = struct('id','','label','','enabled',false,'reason','','kind','modality','index',NaN);
            sources = tmpl([]);
            % nm2-allow: public model-source selector boundary validates the requested analysis index.
            if idx < 1 || idx > numel(NM.analysis), return; end
            A=NM.analysis{idx};
            kind=NMResultsViewerTools.normalizeResultType(resultType);
            isOptimization=strcmp(kind,'model_optimization');
            isPerformance=ismember(kind,{'classification','regression','multiclass'});
            if isPerformance && ~strcmp(NMResultsViewerTools.analysisFusionMode(A),'late'), return; end
            if ~isOptimization && ~isPerformance, return; end
            nGD=numel(A.GDdims);
            % nm2-allow: nk_MLOptimizerPrep conditionally writes analysis.META only when nk_MLOptimizerMeta returns a result.
            hasMeta=isfield(A,'META');
            if nGD+double(hasMeta)<1,return;end
            sources=repmat(tmpl,1,nGD+double(hasMeta));
            for ii=1:nGD
                GD=A.GDdims{ii};
                sources(ii).id=sprintf('modality:%d',ii);
                sources(ii).label=NMResultsViewerTools.modelSourceModalityLabel(NM,A,ii);
                sources(ii).kind='modality';
                sources(ii).index=ii;
                if isOptimization
                    [ok,reason]=NMResultsViewerTools.modelOptimizationSourceBaseAvailable(GD);
                else
                    [ok,reason]=NMResultsViewerTools.performanceModelSourceAvailable(GD,kind);
                end
                sources(ii).enabled=logical(ok);
                sources(ii).reason=reason;
                if ok,sources(ii).reason='';end
            end
            if hasMeta
                jj=nGD+1;
                sources(jj).id='meta';
                sources(jj).label='Bagged/META predictor';
                sources(jj).kind='meta';
                sources(jj).index=NaN;
                if isOptimization
                    [ok,reason]=NMResultsViewerTools.modelOptimizationMetaSourceAvailable(A.META);
                else
                    [ok,reason]=NMResultsViewerTools.performanceModelSourceAvailable(A.META,kind);
                end
                sources(jj).enabled=logical(ok);
                sources(jj).reason=reason;
                if ok,sources(jj).reason='';end
            end
        end

        function [opts, selected] = oocvSubgroupsForAnalysis(NM, idx, spec)
            % oocvSubgroupsForAnalysis  Resolve the selected OOCV grouping catalogue.
            tmpl = struct('index',1,'label','Show entire OOCV sample','enabled',true);
            opts = tmpl([]);
            selected = 1;
            source = spec.source;
            [isOOCVSource, globalIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            candidate = spec.oocvSubgroupIndex;
            if ~isscalar(candidate) || ~isfinite(candidate) || candidate < 1 || candidate ~= round(candidate)
                error('NMResultsViewerTools:InvalidOOCVSubgroup','oocvSubgroupIndex must be one finite positive integer.');
            end
            if ~isOOCVSource
                if candidate ~= 1
                    error('NMResultsViewerTools:InvalidOOCVSubgroup','OOCV subgroup selection is not applicable to the selected source.');
                end
                return;
            end
            kind = NMResultsViewerTools.normalizeResultType(spec.resultType);
            descriptors = NMResultsViewerTools.oocvSourceDescriptors(NM,idx,kind);
            sourceHit = find([descriptors.globalIndex] == globalIndex,1,'first');
            if isempty(sourceHit)
                error('NMResultsViewerTools:InvalidOOCVSubgroupContext', ...
                    'OOCV subgroup state cannot resolve source %s in analysis %d.',source,idx);
            end
            if strcmp(kind,'multiclass')
                [opts, ~] = NMResultsViewerTools.multiClassOOCVSubgroupCatalogue(NM.OOCV{globalIndex});
                hit = find([opts.index] == candidate & [opts.enabled],1,'first');
                if isempty(hit)
                    % nm2-allow: NMResultsViewerUI_main.stateRequestSpecForChange marks transitions retaining source-local subgroup identity.
                    if isfield(spec,'selectionTransition') && ~isempty(spec.selectionTransition)
                        selected = double(opts(1).index);
                        return;
                    end
                    error('NMResultsViewerTools:InvalidOOCVSubgroup', ...
                        'OOCV subgroup %d is not available for the selected multiclass OOCV source.',candidate);
                end
                selected = double(opts(hit).index);
                return;
            end
            A = NM.analysis{idx};
            data = A.OOCV{globalIndex};
            if strcmp(kind,'regression')
                resultField = 'RegrResults';
            else
                [sourceOK,sourceGD] = NMResultsViewerTools.resultGDForSpec(NM,idx,'classification',spec);
                if ~sourceOK
                    error('NMResultsViewerTools:InvalidOOCVSubgroupContext', ...
                        'OOCV subgroup state cannot resolve the selected classification model source.');
                end
                % nm2-allow: nk_MLOptimizer writer condition selects binary versus multi-group training result family
                if isfield(sourceGD,'MultiClass') && ~isempty(sourceGD.MultiClass)
                    resultField = 'MultiResults';
                else
                    resultField = 'BinResults';
                end
            end
            % nm2-allow: nk_OOCVPrep writer condition selects BinResults or RegrResults for these accepted H20 consumers
            if ~isfield(data,resultField) || isempty(data.(resultField))
                error('NMResultsViewerTools:InvalidOOCVSubgroupContext', ...
                    'OOCV source %s lacks the producer-selected subgroup result container %s.',source,resultField);
            end
            raw = data.(resultField);
            resultTargetIndex = spec.targetIndex;
            % nm2-allow: public compact OOCV target selector validates the requested result coordinate against the writer-produced target-cell axis
            if ~isscalar(resultTargetIndex) || ~isfinite(resultTargetIndex) || resultTargetIndex < 1 || resultTargetIndex ~= round(resultTargetIndex) || resultTargetIndex > numel(raw)
                error('NMResultsViewerTools:InvalidOOCVSubgroupContext', ...
                    'Target result index %g is outside the OOCV result axis.',resultTargetIndex);
            end
            result = raw{resultTargetIndex};
            opts = tmpl;
            % nm2-allow: nk_OOCV writes Group only when subgroup analysis material is produced
            if isfield(result,'Group') && ~isempty(result.Group)
                groups = result.Group;
                opts = repmat(tmpl,1,numel(groups)+1);
                for gg = 1:numel(groups)
                    label = sprintf('OOCV subgroup %d',gg);
                    % nm2-allow: nk_OOCV writes GroupName only when subgroup names are available
                    if isfield(groups{gg},'GroupName') && ~isempty(groups{gg}.GroupName)
                        label = groups{gg}.GroupName;
                    end
                    opts(gg+1) = struct('index',gg+1,'label',label,'enabled',true);
                end
            end
            hit = find([opts.index] == candidate & [opts.enabled],1,'first');
            if isempty(hit)
                % nm2-allow: NMResultsViewerUI_main.stateRequestSpecForChange marks transitions retaining source-local subgroup identity.
                if isfield(spec,'selectionTransition') && ~isempty(spec.selectionTransition)
                    selected = double(opts(1).index);
                    return;
                end
                error('NMResultsViewerTools:InvalidOOCVSubgroup', ...
                    'OOCV subgroup %d is not available for the selected OOCV source.',candidate);
            end
            selected = double(opts(hit).index);
        end

        function [tf, globalIndex] = parseOOCVSourceId(source)
            tf = false;
            globalIndex = NaN;
            token = regexp(source,'^oocv:(\d+)$','tokens','once');
            if isempty(token), return; end
            tf = true;
            globalIndex = str2double(token{1});
        end


        function tf = profileEnabled(req)
            % profileEnabled  The one Results Viewer profiling switch: NM_UI_PROFILE, overridden by a per-request
            % flag. The three flag names have different writers: profile (NMAppUI child contexts), profileEnabled
            % (NMResultsViewerUI_main.js report and export requests) and nmProfile (matlabService transport).
            env = getenv('NM_UI_PROFILE');
            tf = any(strcmpi(strtrim(env), {'1','true','on','yes'}));
            % nm2-allow: profile is written only by NMAppUI child contexts.
            if isfield(req,'profile')
                tf = logical(req.profile);
            % nm2-allow: profileEnabled is written only by NMResultsViewerUI_main.js report and export requests.
            elseif isfield(req,'profileEnabled')
                tf = logical(req.profileEnabled);
            % nm2-allow: nmProfile is written only by matlabService in NMResultsViewerUI_main.js.
            elseif isfield(req,'nmProfile')
                tf = logical(req.nmProfile);
            end
        end
    end

    methods (Static, Access = private)
        function [payload, handles] = discoveryClassPayloadFromHandles(payload, handles, h, graphType)
            % load_GDdims owns the admitted binary-classification handle schema.
            B = handles.BinClass{h};
            [predh, plotInfo, contingency] = NMResultsViewerTools.legacyPredictionVector(handles, h, graphType);
            predh = double(predh(:));
            labelh = double(B.labelh(:));
            cases = B.cases(:);
            n = numel(predh);
            if numel(labelh) ~= n
                error('NMResultsViewerTools:ClassificationLabelAxisMismatch', ...
                    'load_GDdims produced %d displayed scores but %d binary labels.',n,numel(labelh));
            end
            if numel(cases) ~= n
                error('NMResultsViewerTools:ClassificationCaseAxisMismatch', ...
                    'load_GDdims produced %d displayed scores but %d case identifiers.',n,numel(cases));
            end

            rawXaxis = [];
            % nm2-allow: applyPlotVectorXAxisOverride conditionally writes BinClass.Xaxis at the public presentation boundary
            if isfield(B,'Xaxis')
                rawXaxis = double(B.Xaxis(:));
                if numel(rawXaxis) ~= n
                    error('NMResultsViewerTools:ClassificationXAxisMismatch', ...
                        'The selected classification x-axis has %d values for %d materialized cases.',numel(rawXaxis),n);
                end
            end

            if B.CoxMode
                offs = double(B.mean_cutoff_probabilities(:));
                if numel(offs) ~= n
                    error('NMResultsViewerTools:ClassificationCutoffAxisMismatch', ...
                        'load_GDdims produced %d Cox cutoffs for %d materialized cases.',numel(offs),n);
                end
            else
                offs = zeros(n,1);
            end

            if graphType > 3 || plotInfo.percentRank || plotInfo.probTransform
                if plotInfo.percentRank || plotInfo.probTransform
                    signpred = sign(predh - plotInfo.decisionLineValue);
                    storedPredh = predh - plotInfo.decisionLineValue;
                else
                    signpred = sign(predh - 0.5);
                    storedPredh = predh - 0.5;
                end
            else
                signpred = sign(predh - offs);
                storedPredh = predh;
            end
            err = signpred ~= labelh;

            id1 = logical(B.ind1(:));
            id2 = logical(B.ind2(:));
            if numel(id1) ~= n
                error('NMResultsViewerTools:ClassificationGroupAxisMismatch', ...
                    'load_GDdims produced %d group-1 flags for %d materialized cases.',numel(id1),n);
            end
            if numel(id2) ~= n
                error('NMResultsViewerTools:ClassificationGroupAxisMismatch', ...
                    'load_GDdims produced %d group-2 flags for %d materialized cases.',numel(id2),n);
            end
            subMask = NMResultsViewerTools.viewerSubIndexMask(handles, n);
            if any(~subMask)
                predh = predh(subMask);
                labelh = labelh(subMask);
                cases = cases(subMask);
                offs = offs(subMask);
                id1 = id1(subMask);
                id2 = id2(subMask);
                signpred = signpred(subMask);
                err = err(subMask);
                storedPredh = storedPredh(subMask);
                if ~isempty(rawXaxis), rawXaxis = rawXaxis(subMask); end
                n = numel(predh);
            end
            if n == 0
                payload.classPlot = struct('ok',false,'points',[],'message','The selected subgroup vector excludes all training/CV cases.');
                payload.message = payload.classPlot.message;
                return;
            end

            if ~isempty(rawXaxis)
                x = rawXaxis(:);
                altAx = true;
                xLabel = handles.XaxisName;
            else
                x = (1:n)';
                altAx = false;
                if handles.tglSort.Value
                    xLabel = 'Sorted Subject No.';
                else
                    xLabel = 'Subject No.';
                end
            end

            colors = NMResultsViewerTools.classColors(handles, B);
            [xPlot, xDiag] = NMResultsViewerTools.xAxisDiagnostics(x, predh, labelh, B.groupnames, colors, altAx, true);
            points = NMResultsViewerTools.classPlotPoints(xPlot, predh, cases, labelh, id1, id2, err, B.groupnames, colors, offs);
            [xLim, yLim] = NMResultsViewerTools.legacyLimits(xPlot, predh);
            if xDiag.isCategorical && ~isempty(xDiag.categories)
                xLim = [0.5 numel(xDiag.categories)+0.5];
            end
            patches = NMResultsViewerTools.classBackgroundPatches(xPlot, id1, id2, altAx || xDiag.isCategorical, handles.tglSort.Value, xLim, yLim, plotInfo.zeroLineY, colors);
            zeroLine = NMResultsViewerTools.zeroLinePayload(xLim, xPlot, plotInfo.zeroLineY, B.CoxMode);
            errorBars = NMResultsViewerTools.errorBarsPayload(xPlot, predh, plotInfo, handles.tglSort.Value);

            payload.classPlot = struct();
            payload.classPlot.ok = true;
            payload.classPlot.mode = 'cv_scatter';
            payload.classPlot.title = 'Classification plot';
            payload.classPlot.xLabel = xLabel;
            payload.classPlot.yLabel = NMResultsViewerTools.legacyYAxisLabel(handles, graphType, plotInfo);
            payload.classPlot.xLim = double(xLim);
            payload.classPlot.yLim = double(yLim);
            payload.classPlot.points = points;
            payload.classPlot.backgroundPatches = patches;
            payload.classPlot.zeroLine = zeroLine;
            payload.classPlot.errorBars = errorBars;
            payload.classPlot.legend = NMResultsViewerTools.classLegend(B.groupnames, graphType, plotInfo);
            payload.classPlot.colorGroup1 = colors.group1;
            payload.classPlot.colorGroup2 = colors.group2;
            payload.classPlot.xAxisMode = xDiag.mode;
            payload.classPlot.categories = xDiag.categories;
            payload.classPlot.boxGroups = xDiag.boxGroups;
            payload.classPlot.associations = xDiag.associations;
            payload.classPlot.associationSummary = xDiag.summary;
            payload.classPlot.groupNames = NMResultsViewerTools.asStringCell(B.groupnames);
            payload.classPlot.sorted = logical(handles.tglSort.Value);
            payload.classPlot.colorSwapped = logical(handles.tglClrSwp.Value);
            payload.classPlot.percentRank = logical(handles.tglPercRank.Value);
            payload.classPlot.probTransform = logical(handles.tglP.Value);
            payload.classPlot.alternativeXAxis = altAx;
            payload.classPlot.displayedScore = double(storedPredh(:));
            if ~isempty(handles.alphaVectorWarning)
                payload.classPlot.message = handles.alphaVectorWarning;
                payload.message = handles.alphaVectorWarning;
            end

            payload.summaryRows = NMResultsViewerTools.metricRowsFromContingency(contingency, handles.calibflag, handles);
            payload.performanceTabulationRows = NMPerformanceMetricTools.classificationRows(contingency);
            probabilityColumn = NMResultsViewerTools.cvProbabilityColumn(B, n);
            [payload.scoreRows, payload.scoreColumns] = NMResultsViewerTools.scoreRowsFromLegacyTable(B, predh, signpred, err, plotInfo, probabilityColumn);
            payload.roc = NMResultsViewerTools.rocPayloadFromLegacy(labelh, predh, contingency);
            payload.confusion = NMResultsViewerTools.confusionPayloadFromContingency(contingency, B.groupnames);
            payload.pies = NMResultsViewerTools.pieChartsPayloadFromContingency(contingency, labelh, B.groupnames, colors);
        end

        function [payload, handles] = discoveryClassOOCVPayloadFromHandles(payload, handles, h, graphType, NM, viewerOpts)
            % buildLegacyOOCVViewerState/load_OOCV own the admitted OOCV handle schema.
            B = handles.BinClass{h};
            oocvind = double(handles.oocvind);
            if ~handles.OOCV(oocvind).flag
                error('NMResultsViewerTools:InvalidOOCVSource', ...
                    'Selected binary OOCV result source was not accepted by load_OOCV.');
            end
            [OOCVres, resultField] = NMResultsViewerTools.oocvResultContainer(handles, oocvind);
            labelsKnown = NMResultsViewerTools.oocvLabelsKnown(handles, oocvind);
            resultN = numel(OOCVres.MeanCV2PredictedValues{h});
            cases = NMResultsViewerTools.oocvCaseList(handles, oocvind, resultN);
            [P_h, P_oocv_h, zeroLine, plotInfo] = NMResultsViewerTools.oocvPredictionVectors(handles, OOCVres, h, graphType, resultField);
            P_h = double(P_h(:));
            P_oocv_h = double(P_oocv_h(:));
            n = numel(P_oocv_h);
            if n ~= resultN
                error('NMResultsViewerTools:OOCVPredictionAxisMismatch', ...
                    'OOCV display material has %d values for a %d-case result axis.',n,resultN);
            end

            label_oocv_h = zeros(n,1);
            if labelsKnown
                label_oocv_h = double(OOCVres.BinLabels{h}(:));
                if numel(label_oocv_h) ~= n
                    error('NMResultsViewerTools:OOCVLabelAxisMismatch', ...
                        'OOCV BinLabels{%d} has %d values for %d result cases.',h,numel(label_oocv_h),n);
                end
            end

            colors = NMResultsViewerTools.classColors(handles, B);
            id1 = logical(B.ind1(:));
            id2 = logical(B.ind2(:));
            if numel(id1) ~= numel(P_h)
                error('NMResultsViewerTools:OOCVReferenceAxisMismatch', ...
                    'Discovery group-1 mask has %d values for %d reference scores.',numel(id1),numel(P_h));
            end
            if numel(id2) ~= numel(P_h)
                error('NMResultsViewerTools:OOCVReferenceAxisMismatch', ...
                    'Discovery group-2 mask has %d values for %d reference scores.',numel(id2),numel(P_h));
            end
            groupNames = NMResultsViewerTools.asStringCell(B.groupnames);

            [handles, subgroupIndex, subgroupMask] = NMResultsViewerTools.applyOOCVSubgroupSelection(handles, OOCVres, h, oocvind, n);
            if numel(subgroupMask) ~= n
                error('NMResultsViewerTools:OOCVSubgroupAxisMismatch', ...
                    'OOCV subgroup mask has %d values for %d result cases.',numel(subgroupMask),n);
            end
            plotMask = logical(subgroupMask(:)) & isfinite(P_oocv_h);
            if labelsKnown
                metricMask = label_oocv_h ~= 0 & isfinite(P_oocv_h) & logical(subgroupMask(:));
                useStoredContingency = subgroupIndex <= 1;
                contigmat = NMResultsViewerTools.oocvContingency(OOCVres, h, resultField, label_oocv_h, P_oocv_h, zeroLine, metricMask, useStoredContingency);
                payload.summaryRows = NMResultsViewerTools.metricRowsFromContingency(contigmat, handles.calibflag, handles);
                payload.performanceTabulationRows = NMPerformanceMetricTools.classificationRows(contigmat);
                payload.roc = struct('ok',false,'points',[],'auc',NaN,'message','OOCV ROC is unavailable for this result source.');
                payload.pies = struct('ok',false,'charts',[],'message','OOCV pie charts are unavailable for this result source.');
                if sum(metricMask) > 2
                    payload.roc = NMResultsViewerTools.rocPayloadFromLegacy(label_oocv_h(metricMask), P_oocv_h(metricMask), contigmat, B.labelh, P_h);
                    payload.pies = NMResultsViewerTools.pieChartsPayloadFromContingency(contigmat, label_oocv_h(metricMask), groupNames, colors);
                end
                payload.confusion = NMResultsViewerTools.confusionPayloadFromContingency(contigmat, groupNames);
            else
                payload.summaryRows = struct('metric','OOCV labels:', 'value','Unavailable; performance metrics, ROC, contingency matrix and pie charts are suppressed.', 'source','display_classplot_oocv labels_known=false');
                payload.roc = struct('ok',false,'points',[],'auc',NaN,'message','OOCV labels are unavailable; ROC/AUC is suppressed.');
                payload.confusion = struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{groupNames},'message','OOCV labels are unavailable; contingency metrics are suppressed.');
                payload.pies = struct('ok',false,'charts',[],'message','OOCV labels are unavailable; pre-/post-test probability pies are suppressed.');
            end

            probabilityColumn = NMResultsViewerTools.oocvProbabilityColumn(OOCVres, h, P_oocv_h, plotInfo, n);
            [payload.scoreRows, payload.scoreColumns] = NMResultsViewerTools.oocvScoreRows(OOCVres, h, B, cases(plotMask), label_oocv_h(plotMask), labelsKnown, P_oocv_h(plotMask), zeroLine, probabilityColumn(plotMask), plotInfo);
            xExpr = viewerOpts.xAxisExpression;
            if ~isempty(xExpr)
                [xO, xOK, xMsg] = NMResultsViewerTools.resolvePlotVectorReference(NM, xExpr, n, 'xaxis', viewerOpts);
                if xOK
                    xO = double(xO(:));
                    xO = xO(plotMask);
                    yO = P_oocv_h(plotMask);
                    labO = label_oocv_h(plotMask);
                    caseO = cases(plotMask);
                    if labelsKnown
                        id1o = labO > 0; id2o = labO < 0;
                        errO = sign(yO - zeroLine) ~= labO;
                    else
                        id1o = false(size(yO)); id2o = false(size(yO)); errO = false(size(yO));
                    end
                    [xPlot, xDiag] = NMResultsViewerTools.xAxisDiagnostics(xO, yO, labO, B.groupnames, colors, true, labelsKnown);
                    points = NMResultsViewerTools.classPlotPoints(xPlot, yO, caseO, labO, id1o, id2o, errO, B.groupnames, colors, zeros(size(yO))+zeroLine);
                    [xLim, yLim] = NMResultsViewerTools.legacyLimits(xPlot, yO);
                    if xDiag.isCategorical && ~isempty(xDiag.categories)
                        xLim = [0.5 numel(xDiag.categories)+0.5];
                    end
                    axisName = viewerOpts.xAxisLabel;
                    if isempty(axisName)
                        axisName = NMResultsViewerTools.plotVectorAxisLabel(NM, xExpr, n, viewerOpts);
                    end
                    payload.classPlot = struct('ok',true,'mode','oocv_alt_scatter','title','OOCV classification plot','xLabel',axisName, ...
                        'yLabel',NMResultsViewerTools.legacyYAxisLabel(handles, graphType, plotInfo), 'xLim',double(xLim),'yLim',double(yLim), ...
                        'points',points,'backgroundPatches',[],'zeroLine',NMResultsViewerTools.zeroLinePayload(xLim, xPlot, zeroLine, false), ...
                        'errorBars',struct('ok',false,'mode','none','kind','','bars',[],'band',[]), ...
                        'legend',NMResultsViewerTools.classLegend(B.groupnames, graphType, plotInfo), 'colorGroup1',colors.group1,'colorGroup2',colors.group2, ...
                        'xAxisMode',xDiag.mode,'categories',xDiag.categories,'boxGroups',xDiag.boxGroups,'associations',xDiag.associations,'associationSummary',xDiag.summary, ...
                        'message','OOCV predictions plotted against the selected external vector.');
                else
                    payload.classPlot = NMResultsViewerTools.oocvViolinPlotPayload(handles, B, h, P_h, P_oocv_h(plotMask), label_oocv_h(plotMask), labelsKnown, cases(plotMask), id1, id2, colors, zeroLine, graphType, plotInfo);
                    payload.classPlot.message = sprintf('%s Alternative x-axis was ignored: %s', payload.classPlot.message, xMsg);
                end
            else
                payload.classPlot = NMResultsViewerTools.oocvViolinPlotPayload(handles, B, h, P_h, P_oocv_h(plotMask), label_oocv_h(plotMask), labelsKnown, cases(plotMask), id1, id2, colors, zeroLine, graphType, plotInfo);
            end
            payload.oocv = struct('ok',true,'localIndex',oocvind,'globalIndex',handles.OOCV(oocvind).num, ...
                'labelsKnown',logical(labelsKnown),'resultField',resultField, ...
                'descriptor',handles.OOCVinfo.Analyses{handles.curranal}.descriptor{oocvind}, ...
                'selectedSubgroupIndex',subgroupIndex);
        end

        function [OOCVres, resultField] = oocvResultContainer(handles, oocvind)
            resultField = handles.oocvResultField;
            raw = handles.OOCV(oocvind).data.(resultField);
            labelIdx = double(handles.curlabel);
            % nm2-allow: public target selector owns compact OOCV result coordinate
            if labelIdx < 1 || labelIdx ~= round(labelIdx) || labelIdx > numel(raw)
                error('NMResultsViewerTools:InvalidOOCVTargetIndex', ...
                    'OOCV target result index %g is outside %s.',labelIdx,resultField);
            end
            OOCVres = raw{labelIdx};
        end
        function tf = oocvLabelsKnown(handles, oocvind)
            entry = handles.OOCVinfo.Analyses{handles.curranal};
            tf = logical(entry.labels_known(oocvind));
        end
        function cases = oocvCaseList(handles, oocvind, n)
            entry = handles.OOCVinfo.Analyses{handles.curranal};
            cases = entry.cases{oocvind};
            % nm2-allow: OOCV case-axis validation detects corrupt persisted result/data pairing
            if numel(cases) ~= n
                error('NMResultsViewerTools:OOCVCaseAxisMismatch', ...
                    'OOCV source %d has %d case identifiers but the selected result has %d rows.', ...
                    entry.OOCVvec(oocvind),numel(cases),n);
            end
            cases = cases(:);
        end
        function [P_h, P_oocv_h, zeroLine, info] = oocvPredictionVectors(handles, OOCVres, h, graphType, resultField)
            B = handles.BinClass{h};
            graphType = max(1, min(6, round(double(graphType))));
            info = struct('percentRank',logical(handles.tglPercRank.Value),'probTransform',logical(handles.tglP.Value), ...
                'decisionLineValue',0,'zeroLineY',0,'errorKind','none','hasError',false,'errorMode','none');
            if info.percentRank
                switch graphType
                    case {1,2,3}
                        refsample = double(B.mean_predictions(:));
                        targetsample = double(OOCVres.MeanCV2PredictedValues{h}(:));
                        baseZero = 0;
                    case 4
                        refsample = double(B.prob_predictions(:,1));
                        targetsample = double(OOCVres.BinMajVoteProbabilities{h}(:));
                        baseZero = 0;
                    otherwise
                        refsample = double(B.mean_predictions(:));
                        targetsample = double(OOCVres.BinMajVoteProbabilities{h}(:));
                        baseZero = 0;
                end
                zeroLine = nk_ComputePercentiles(refsample, baseZero, 'inverse');
                P_h = ranktransform(refsample);
                P_oocv_h = ranktransform(refsample, targetsample);
            else
                switch graphType
                    case {1,2,3}
                        P_h = double(B.mean_predictions(:));
                        P_oocv_h = double(OOCVres.MeanCV2PredictedValues{h}(:));
                        zeroLine = 0;
                    case 4
                        P_h = double(B.prob_predictions(:,1));
                        P_oocv_h = double(OOCVres.BinMajVoteProbabilities{h}(:));
                        zeroLine = 0.5;
                    otherwise
                        if ~isfield(B,'CV2grid') || isempty(B.CV2grid)
                            error('NMResultsViewerTools:MissingCV2Grid', 'CV2grid is required for OOCV graph type %d.', graphType);
                        end
                        P_h = double(B.CV2grid.mean_predictions(:));
                        P_oocv_h = double(OOCVres.BinMajVoteProbabilities{h}(:));
                        zeroLine = 0;
                end
                if info.probTransform
                    if strcmp(resultField,'BinResults') && isfield(OOCVres,'Calibration') && isfield(OOCVres.Calibration,'Probabilities') && ~isempty(OOCVres.Calibration.Probabilities) && ...
                            isfield(B,'Calibration') && isfield(B.Calibration,'Probabilities') && ~isempty(B.Calibration.Probabilities)
                        P_oocv_h = double(OOCVres.Calibration.Probabilities(:));
                        P_h = double(B.Calibration.Probabilities(:));
                    else
                        probMethod = handles.alphaProbMethod;
                        P_oocv_h = NMResultsViewerTools.probTransformAgainstReference(B.labelh, P_h, P_oocv_h, probMethod);
                        P_h = NMResultsViewerTools.probTransformAgainstReference(B.labelh, P_h, [], probMethod);
                    end
                    zeroLine = 0.5;
                end
            end
            info.decisionLineValue = double(zeroLine);
            info.zeroLineY = double(zeroLine);
        end

        function p = probTransformAgainstReference(labelh, refScores, targetScores, method)
            if isempty(method), method = 'platt'; end
            y = double(labelh(:)); y(y==-1 | y==2) = 0;
            ref = double(refScores(:));
            if isempty(targetScores)
                target = [];
            else
                target = double(targetScores(:));
            end
            if strcmp(method,'none')
                if isempty(target), p = ref; else, p = target; end
            else
                p = probtransform(y, ref, target, method);
            end
        end

        function contigmat = oocvContingency(OOCVres, h, resultField, labels, scores, zeroLine, metricMask, useStoredContingency) %#ok<INUSD>
            contigmat = [];
            if useStoredContingency && isfield(OOCVres,'contingency') && ~isempty(OOCVres.contingency)
                C = OOCVres.contingency;
                if iscell(C)
                    if numel(C) >= h, contigmat = C{h}; end
                elseif isstruct(C)
                    contigmat = C;
                end
            end
            if ~isstruct(contigmat) || ~NMResultsViewerTools.hasAllFields(contigmat, {'TP','TN','FP','FN'})
                contigmat = ALLPARAM(labels(metricMask), scores(metricMask) - double(zeroLine));
            end
        end

        function p = oocvProbabilityColumn(OOCVres, h, displayedScores, plotInfo, n)
            p = nan(n,1);
            if isfield(OOCVres,'Calibration') && isstruct(OOCVres.Calibration) && isfield(OOCVres.Calibration,'Probabilities') && ~isempty(OOCVres.Calibration.Probabilities)
                p = NMResultsViewerTools.padNumericColumn(double(OOCVres.Calibration.Probabilities(:)), n, NaN);
            elseif plotInfo.probTransform
                p = NMResultsViewerTools.padNumericColumn(double(displayedScores(:)), n, NaN);
            end
            %#ok<INUSD> h documents that probabilities correspond to the active display_classplot_oocv class.
        end

        function [rows, columns] = oocvScoreRows(OOCVres, h, B, cases, labels, labelsKnown, displayedScores, zeroLine, calibratedProbability, plotInfo)
            if isempty(calibratedProbability), calibratedProbability = nan(numel(displayedScores),1); end
            probabilityAvailable = any(isfinite(double(calibratedProbability(:))));
            columns = NMResultsViewerTools.oocvScoreColumns(labelsKnown, probabilityAvailable);
            n = min([numel(cases), numel(displayedScores), numel(OOCVres.MeanCV2PredictedValues{h})]);
            tmpl = struct('case','','expected','','predicted','','error',false,'score',NaN,'stdScore',NaN, ...
                'ensembleProbability',NaN,'ensembleProbabilityMinus1',NaN,'percentRank',NaN,'probability',NaN,'numericExpected',NaN,'numericPredicted',NaN);
            rows = repmat(tmpl, 1, n);
            gn = NMResultsViewerTools.asStringCell(B.groupnames);
            predNumeric = NMResultsViewerTools.padNumericColumn(double(OOCVres.BinProbPredictions{h}(:)), n, NaN);
            meanScore = NMResultsViewerTools.padNumericColumn(double(OOCVres.MeanCV2PredictedValues{h}(:)), n, NaN);
            stdScore = NMResultsViewerTools.padNumericColumn(double(OOCVres.StdCV2PredictedValues{h}(:)), n, NaN);
            ensProb = NMResultsViewerTools.padNumericColumn(double(OOCVres.BinMajVoteProbabilities{h}(:)), n, NaN);
            pr = ranktransform(B.mean_predictions(:), meanScore);
            pr = NMResultsViewerTools.padNumericColumn(double(pr(:)), n, NaN);
            labels = NMResultsViewerTools.padNumericColumn(double(labels(:)), n, 0);
            calibratedProbability = NMResultsViewerTools.padNumericColumn(double(calibratedProbability(:)), n, NaN);
            for ii = 1:n
                expected = 'not labeled';
                err = false;
                if labelsKnown
                    expected = NMResultsViewerTools.binaryGroupName(labels(ii), gn);
                    err = isfinite(predNumeric(ii)) && predNumeric(ii) ~= labels(ii);
                end
                predicted = NMResultsViewerTools.binaryGroupName(predNumeric(ii), gn);
                if strcmp(predicted,'not labeled')
                    predicted = NMResultsViewerTools.binaryGroupName(displayedScores(ii) - double(zeroLine), gn);
                end
                ep2 = NaN;
                if isfinite(ensProb(ii)) && ensProb(ii) >= 0 && ensProb(ii) <= 1, ep2 = 1 - ensProb(ii); end
                rows(ii) = struct('case',cases{ii},'expected',expected,'predicted',predicted,'error',logical(err), ...
                    'score',double(meanScore(ii)),'stdScore',double(stdScore(ii)), ...
                    'ensembleProbability',double(ensProb(ii)),'ensembleProbabilityMinus1',double(ep2), ...
                    'percentRank',double(pr(ii)),'probability',double(calibratedProbability(ii)), ...
                    'numericExpected',double(labels(ii)),'numericPredicted',double(predNumeric(ii)));
            end
        end

        function columns = oocvScoreColumns(labelsKnown, probabilityAvailable)
            if isempty(probabilityAvailable), probabilityAvailable = false; end
            if labelsKnown
                keys = {'case','expected','predicted','error','score','stdScore','ensembleProbability','ensembleProbabilityMinus1','percentRank'};
                labels = {'Case','EXP_LABEL','PRED_LABEL','Errors','Mean_Score','Std_Score','Ens_Prob1','Ens_Prob-1','PercRank_Score'};
            else
                keys = {'case','predicted','score','stdScore','ensembleProbability','ensembleProbabilityMinus1','percentRank'};
                labels = {'Case','PRED_LABEL','Mean_Score','Std_Score','Ens_Prob1','Ens_Prob-1','PercRank_Score'};
            end
            if probabilityAvailable
                keys{end+1} = 'probability';
                labels{end+1} = 'Probability';
            end
            columns = NMResultsViewerTools.tableColumnStruct(keys, labels);
        end

        function name = binaryGroupName(value, groupNames)
            if ~isfinite(double(value)) || double(value) == 0
                name = 'not labeled';
            elseif double(value) > 0
                name = groupNames{1};
            else
                name = groupNames{2};
            end
        end

        function cp = oocvViolinPlotPayload(handles, B, h, P_h, P_oocv_h, labels, labelsKnown, cases, id1, id2, colors, zeroLine, graphType, plotInfo)
            groupNames = NMResultsViewerTools.asStringCell(B.groupnames);
            specs = repmat(struct('x',NaN,'label','','kind','','color','','alpha',0.2,'values',[],'caseIndices',[],'cases',{{}},'expected',{{}},'predicted',{{}},'pointRadius',4), 1, 5);
            nSpec = 0;
            nSpec = nSpec + 1;
            specs(nSpec) = NMResultsViewerTools.oocvViolinSpec(1, sprintf('Discovery: %s', groupNames{1}), 'discovery', colors.group1, 0.10, P_h(id1), zeros(sum(id1),1), repmat({''},sum(id1),1), repmat({groupNames{1}},sum(id1),1), repmat({''},sum(id1),1), 3.6);
            nSpec = nSpec + 1;
            specs(nSpec) = NMResultsViewerTools.oocvViolinSpec(3, sprintf('Discovery: %s', groupNames{2}), 'discovery', colors.group2, 0.10, P_h(id2), zeros(sum(id2),1), repmat({''},sum(id2),1), repmat({groupNames{2}},sum(id2),1), repmat({''},sum(id2),1), 3.6);
            n = numel(P_oocv_h);
            predNames = cell(n,1);
            expectedNames = cell(n,1);
            for ii = 1:n
                predNames{ii} = NMResultsViewerTools.binaryGroupName(P_oocv_h(ii) - double(zeroLine), groupNames);
                if labelsKnown, expectedNames{ii} = NMResultsViewerTools.binaryGroupName(labels(ii), groupNames); else, expectedNames{ii} = 'not labeled'; end
            end
            if labelsKnown
                lab = NMResultsViewerTools.padNumericColumn(labels, n, 0);
                idxKnown = find(lab ~= 0 & isfinite(P_oocv_h));
                hasG1 = any(lab(idxKnown) > 0);
                hasG2 = any(lab(idxKnown) < 0);
                x1 = 2; x2 = 2;
                if hasG1 && hasG2, x2 = 4; end
                ii1 = find(lab > 0 & isfinite(P_oocv_h));
                ii2 = find(lab < 0 & isfinite(P_oocv_h));
                ii0 = find(lab == 0 & isfinite(P_oocv_h));
                if ~isempty(ii1)
                    nSpec = nSpec + 1;
                    specs(nSpec) = NMResultsViewerTools.oocvViolinSpec(x1, sprintf('OOCV: %s', groupNames{1}), 'oocv', colors.group1, 0.30, P_oocv_h(ii1), ii1, cases(ii1), expectedNames(ii1), predNames(ii1), 7.0);
                end
                if ~isempty(ii2)
                    nSpec = nSpec + 1;
                    specs(nSpec) = NMResultsViewerTools.oocvViolinSpec(x2, sprintf('OOCV: %s', groupNames{2}), 'oocv', colors.group2, 0.30, P_oocv_h(ii2), ii2, cases(ii2), expectedNames(ii2), predNames(ii2), 7.0);
                end
                if ~isempty(ii0)
                    nSpec = nSpec + 1;
                    specs(nSpec) = NMResultsViewerTools.oocvViolinSpec(5, 'OOCV: unlabeled/not applicable', 'oocv', '#111827', 0.30, P_oocv_h(ii0), ii0, cases(ii0), expectedNames(ii0), predNames(ii0), 7.0);
                end
            else
                iiAll = find(isfinite(P_oocv_h));
                if ~isempty(iiAll)
                    nSpec = nSpec + 1;
                    specs(nSpec) = NMResultsViewerTools.oocvViolinSpec(2, 'OOCV: unlabeled/not applicable', 'oocv', '#111827', 0.30, P_oocv_h(iiAll), iiAll, cases(iiAll), expectedNames(iiAll), predNames(iiAll), 7.0);
                end
            end
            specs = specs(1:nSpec);
            active = false(1,nSpec);
            for ii = 1:nSpec, active(ii) = ~isempty(specs(ii).values); end
            specs = specs(active);
            groups = NMResultsViewerTools.oocvViolinGroups(specs);
            allY = [P_h(:); P_oocv_h(:); double(zeroLine)];
            [~, yLim] = NMResultsViewerTools.legacyLimits((1:numel(allY))', allY);
            maxX = 1;
            for ii = 1:numel(groups), maxX = max(maxX, double(groups(ii).x)); end
            groups = NMResultsViewerTools.positionViolinDots(groups, yLim, [0.5 maxX+0.5]);
            points = NMResultsViewerTools.flattenViolinPoints(groups);
            cp = struct();
            cp.ok = true;
            cp.mode = 'oocv_violin';
            cp.title = 'OOCV classification distribution plot';
            cp.xLabel = 'Samples';
            cp.yLabel = ['Binned ' NMResultsViewerTools.legacyYAxisLabel(handles, graphType, plotInfo)];
            cp.xLim = [0.5 maxX+0.5];
            cp.yLim = double(yLim);
            cp.points = points;
            cp.violinGroups = groups;
            cp.zeroLine = struct('x',[0.5 maxX+0.5],'y',[double(zeroLine) double(zeroLine)],'coxMode',false);
            cp.legend = NMResultsViewerTools.violinLegendItems(groups);
            cp.groupNames = groupNames;
            cp.colorGroup1 = colors.group1;
            cp.colorGroup2 = colors.group2;
            cp.labelsKnown = logical(labelsKnown);
            cp.percentRank = logical(handles.tglPercRank.Value);
            cp.probTransform = logical(handles.tglP.Value);
            cp.displayedScore = double(P_oocv_h(:));
            cp.message = 'OOCV violin plot follows display_classplot_oocv sample placement and labels_known mechanics.';
        end

        function spec = oocvViolinSpec(x, label, kind, color, alpha, values, caseIndices, cases, expected, predicted, pointRadius)
            spec = struct('x',double(x),'label',label,'kind',kind, ...
                'color',char(string(color)),'alpha',double(alpha),'values',double(values(:)), ...
                'caseIndices',double(caseIndices(:)),'cases',{cases(:)},'expected',{expected(:)},'predicted',{predicted(:)}, ...
                'pointRadius',double(pointRadius));
        end

        function groups = oocvViolinGroups(specs)
            groupTmpl = struct('x',NaN,'label','','kind','','color','','alpha',0.2,'density',[], 'points',[], 'meanValue',NaN, 'medianValue',NaN);
            groups = repmat(groupTmpl, 1, numel(specs));
            for ii = 1:numel(specs)
                density = NMResultsViewerTools.violinDensity(specs(ii).values);
                points = NMResultsViewerTools.violinPoints(specs(ii));
                vals = double(specs(ii).values(:));
                vals = vals(isfinite(vals));
                groups(ii) = struct('x',double(specs(ii).x),'label',specs(ii).label,'kind',specs(ii).kind, ...
                    'color',specs(ii).color,'alpha',double(specs(ii).alpha),'density',density,'points',points, ...
                    'meanValue',mean(vals),'medianValue',median(vals));
            end
        end

        function bw = silvermanBandwidth(values)
            values = sort(double(values(:)));
            n = numel(values);
            sig = std(values);
            if n > 1
                q25 = interp1(1:n, values, 1 + (n-1)*0.25, 'linear');
                q75 = interp1(1:n, values, 1 + (n-1)*0.75, 'linear');
                iq = q75 - q25;
            else
                iq = 0;
            end
            bw = 0.9 * min(sig, iq/1.34) * n^(-1/5);
            if ~isfinite(bw) || bw == 0, bw = 0.001; end
        end

        function points = violinPoints(spec)
            pointTmpl = struct('x',NaN,'y',NaN,'caseId','','caseIndex',0,'expected','','predicted','','kind','','color','','radius',4,'tooltip','');
            values = double(spec.values(:));
            n = numel(values);
            points = repmat(pointTmpl, 1, n);
            if n == 0, return; end
            for ii = 1:n
                caseId = '';
                if ii <= numel(spec.cases), caseId = char(string(spec.cases{ii})); end
                if isempty(caseId), caseId = sprintf('%s sample %d', spec.kind, ii); end
                expected = '';
                if ii <= numel(spec.expected), expected = char(string(spec.expected{ii})); end
                predicted = '';
                if ii <= numel(spec.predicted), predicted = char(string(spec.predicted{ii})); end
                caseIndex = 0;
                if ii <= numel(spec.caseIndices), caseIndex = double(spec.caseIndices(ii)); end
                tip = sprintf('Subject ID: %s\nExpected group: %s\nPredicted Group: %s\nScore: %g', caseId, expected, predicted, values(ii));
                points(ii) = struct('x',double(spec.x),'y',double(values(ii)), ...
                    'caseId',caseId,'caseIndex',caseIndex,'expected',expected,'predicted',predicted, ...
                    'kind',spec.kind,'color',spec.color,'radius',double(spec.pointRadius),'tooltip',tip);
            end
        end

        function groups = positionViolinDots(groups, yLim, xLim)
            % One canonical dot-density layout for browser and exported SVGs.
            % Only presentation x coordinates change; the observed scores, case
            % order, densities and statistical summaries retain their values.
            yBin = diff(double(yLim)) * (13 / 510); % browser 620px minus vertical margins
            xStep = diff(double(xLim)) * (8.5 / 804); % browser 920px minus horizontal margins
            for ii = 1:numel(groups)
                pts = groups(ii).points;
                if isempty(pts), continue; end
                values = double([pts.y]);
                finiteIdx = find(isfinite(values));
                bins = round((values(finiteIdx) - double(yLim(1))) / yBin);
                [~, ~, rowId] = unique(bins);
                for row = 1:max(rowId)
                    idx = finiteIdx(rowId == row);
                    [~, order] = sortrows([double([pts(idx).caseIndex])' idx(:)], [1 2]);
                    idx = idx(order);
                    n = numel(idx);
                    rowY = mean(values(idx));
                    [~, nearest] = min(abs(double([groups(ii).density.y]) - rowY));
                    half = max(0.045, min(0.30, double(groups(ii).density(nearest).width) * 0.92));
                    rawHalf = ((n-1) * xStep) / 2;
                    scale = min(1, half / max(rawHalf, eps));
                    for jj = 1:n
                        pts(idx(jj)).x = double(groups(ii).x) + (jj-(n+1)/2) * xStep * scale;
                    end
                end
                groups(ii).points = pts;
            end
        end

        function points = flattenViolinPoints(groups)
            n = 0;
            for ii = 1:numel(groups), n = n + numel(groups(ii).points); end
            tmpl = struct('x',NaN,'y',NaN,'caseId','','caseIndex',0,'expected','','predicted','','kind','','color','','radius',4,'tooltip','');
            points = repmat(tmpl, 1, n);
            pos = 0;
            for ii = 1:numel(groups)
                P = groups(ii).points;
                for jj = 1:numel(P)
                    pos = pos + 1;
                    points(pos) = P(jj);
                end
            end
        end

        function legendItems = violinLegendItems(groups)
            tmpl = struct('label','','color','','kind','');
            legendItems = repmat(tmpl, 1, numel(groups));
            for ii = 1:numel(groups)
                legendItems(ii) = struct('label',groups(ii).label,'color',groups(ii).color,'kind',groups(ii).kind);
            end
        end

        function [payload, handles] = discoveryRegressionPayloadFromHandles(payload, handles, graphType, thresholdText)
            % load_GDdims owns the admitted regression handle schema.
            R = handles.Regr;
            targetIdx = double(handles.curlabel);
            label = NMResultsViewerTools.asColumnDouble(handles.labels(:,targetIdx));
            pred = NMResultsViewerTools.resultTargetVector(R.mean_predictions, targetIdx);
            sd = NMResultsViewerTools.resultTargetVector(R.std_predictions, targetIdx);
            ci1 = NMResultsViewerTools.resultTargetVector(R.CI1_predictions, targetIdx);
            ci2 = NMResultsViewerTools.resultTargetVector(R.CI2_predictions, targetIdx);
            ind = logical(NMResultsViewerTools.resultTargetVector(R.index_predictions, targetIdx));
            cases = R.cases(:);

            n = numel(pred);
            if numel(label) ~= n
                error('NMResultsViewerTools:RegressionLabelAxisMismatch', ...
                    'load_GDdims produced %d regression predictions but %d labels.',n,numel(label));
            end
            if numel(sd) ~= n
                error('NMResultsViewerTools:RegressionUncertaintyAxisMismatch', ...
                    'Regression SD vector does not match the %d-case prediction axis.',n);
            end
            if numel(ci1) ~= n
                error('NMResultsViewerTools:RegressionUncertaintyAxisMismatch', ...
                    'Regression lower-CI vector does not match the %d-case prediction axis.',n);
            end
            if numel(ci2) ~= n
                error('NMResultsViewerTools:RegressionUncertaintyAxisMismatch', ...
                    'Regression upper-CI vector does not match the %d-case prediction axis.',n);
            end
            if numel(ind) ~= n
                error('NMResultsViewerTools:RegressionIndexAxisMismatch', ...
                    'Regression prediction mask has %d values for %d predictions.',numel(ind),n);
            end
            if numel(cases) ~= n
                error('NMResultsViewerTools:RegressionCaseAxisMismatch', ...
                    'load_GDdims produced %d regression predictions but %d case identifiers.',n,numel(cases));
            end
            if n == 0
                payload.regressionPlot = struct('ok',false,'points',[],'message','No regression predictions were available after load_GDdims.');
                payload.message = 'No regression predictions were available after load_GDdims.';
                return;
            end

            subMask = NMResultsViewerTools.viewerSubIndexMask(handles, n);
            ind = ind(:) & subMask;
            caseIndices = (1:n)';

            % nm2-allow: applyPlotVectorXAxisOverride conditionally writes Regr.Xaxis at the public presentation boundary
            if isfield(R,'Xaxis')
                x = NMResultsViewerTools.asColumnDouble(R.Xaxis);
                if numel(x) ~= n
                    error('NMResultsViewerTools:RegressionXAxisMismatch', ...
                        'The selected regression x-axis has %d values for %d materialized cases.',numel(x),n);
                end
                xLabel = handles.XaxisName;
                alternativeXAxis = true;
            else
                x = label;
                xLabel = 'Observed targets';
                alternativeXAxis = false;
            end

            valid = ind & isfinite(label) & isfinite(pred) & isfinite(x);
            x = x(valid); label = label(valid); pred = pred(valid); sd = sd(valid); ci1 = ci1(valid); ci2 = ci2(valid); cases = cases(valid); caseIndices = caseIndices(valid);
            n = numel(pred);
            if n == 0
                payload.regressionPlot = struct('ok',false,'points',[],'message','Regression predictions exist, but no finite observed/predicted pairs survived the display_regrplot validity filter.');
                payload.summaryRows = NMResultsViewerTools.regressionContinuousMetricRows(R, targetIdx);
                payload.performanceTabulationRows = NMPerformanceMetricTools.regressionRows(R, targetIdx);
                return;
            end

            if isempty(thresholdText)
                threshold = mean(pred(isfinite(pred)), 'omitnan');
                thresholdSource = 'mean(predictions)';
            else
                threshold = str2double(thresholdText);
                thresholdSource = 'user';
                if isnan(threshold)
                    threshold = mean(pred(isfinite(pred)), 'omitnan');
                    thresholdSource = 'mean(predictions; invalid user value ignored)';
                end
            end
            if ~isfinite(threshold), threshold = NaN; end

            handles.curRegr = R;
            handles.curRegr.labels = label;
            handles.curRegr.pred = pred;
            handles.curRegr.b_label = nan(size(label));
            handles.curRegr.b_pred = nan(size(pred));
            handles.curRegr.contigmat = struct();

            points = repmat(struct('x',NaN,'y',NaN,'caseId','','caseIndex',0,'observed',NaN,'predicted',NaN, ...
                'binaryObserved',NaN,'binaryScore',NaN,'binaryPredicted','','error',false,'tooltip',''), 1, n);
            if isfinite(threshold)
                bLabel = -ones(size(label)); bLabel(label >= threshold) = 1;
                bPred = pred - threshold;
            else
                bLabel = nan(size(label)); bPred = nan(size(pred));
            end
            [xPlot, xDiag] = NMResultsViewerTools.xAxisDiagnostics(x, pred, [], {}, struct('group1','#111827','group2','#64748b'), alternativeXAxis, false);
            for i = 1:n
                caseId = cases{i};
                binPred = 'n/a';
                if isfinite(bPred(i))
                    if bPred(i) >= 0
                        binPred = 'Group 1';
                    else
                        binPred = 'Group 2';
                    end
                end
                err = isfinite(bLabel(i)) && isfinite(bPred(i)) && sign(bPred(i)) ~= bLabel(i);
                points(i) = struct('x',double(xPlot(i)),'y',double(pred(i)),'caseId',caseId,'caseIndex',double(caseIndices(i)), ...
                    'observed',double(label(i)),'predicted',double(pred(i)), ...
                    'binaryObserved',double(bLabel(i)),'binaryScore',double(bPred(i)), ...
                    'binaryPredicted',binPred,'error',logical(err), ...
                    'tooltip',sprintf('Subject ID [%d]: %s\nObserved Target: %g\nPredicted Target: %g', caseIndices(i), caseId, label(i), pred(i)));
            end

            errorBars = NMResultsViewerTools.regressionErrorBarsPayload(xPlot, pred, sd, ci1, ci2, graphType);
            [xLim, yLim] = NMResultsViewerTools.regressionLimits(xPlot, pred);
            if xDiag.isCategorical && ~isempty(xDiag.categories)
                xLim = [0.5 numel(xDiag.categories)+0.5];
            end
            fit = NMResultsViewerTools.regressionFitPayload(xPlot, pred);
            thresholdPayload = NMResultsViewerTools.regressionThresholdPayload(threshold, thresholdSource, xLim, yLim, pred);

            payload.regressionPlot = struct();
            payload.regressionPlot.ok = true;
            payload.regressionPlot.title = 'Regression plot';
            payload.regressionPlot.xLabel = xLabel;
            payload.regressionPlot.yLabel = 'Predicted targets';
            payload.regressionPlot.graphType = graphType;
            payload.regressionPlot.graphLabel = NMResultsViewerTools.regressionGraphTypeLabel(graphType);
            payload.regressionPlot.xLim = double(xLim);
            payload.regressionPlot.yLim = double(yLim);
            payload.regressionPlot.points = points;
            payload.regressionPlot.errorBars = errorBars;
            payload.regressionPlot.fit = fit;
            payload.regressionPlot.threshold = thresholdPayload;
            payload.regressionPlot.alternativeXAxis = alternativeXAxis;
            payload.regressionPlot.xAxisMode = xDiag.mode;
            payload.regressionPlot.categories = xDiag.categories;
            payload.regressionPlot.boxGroups = xDiag.boxGroups;
            payload.regressionPlot.associations = xDiag.associations;
            payload.regressionPlot.associationSummary = xDiag.summary;
            payload.regressionPlot.n = n;

            payload.summaryRows = NMResultsViewerTools.regressionContinuousMetricRows(R, targetIdx);
            payload.performanceTabulationRows = NMPerformanceMetricTools.regressionRows(R, targetIdx);
            payload.scoreRows = NMResultsViewerTools.regressionScoreRows(cases, label, pred, sd, ci1, ci2, bLabel, bPred);
            payload.binarization = thresholdPayload;
            payload.roc = struct('ok',false,'points',[],'auc',NaN,'message','Regression-to-binary ROC unavailable.');
            payload.confusion = struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{{}},'message','Regression-to-binary contingency unavailable.');
            payload.pies = struct('ok',false,'charts',[],'message','Regression-to-binary pie charts unavailable.');

            validBinary = isfinite(bLabel) & isfinite(bPred);
            blv = bLabel(validBinary); bpv = bPred(validBinary);
            if numel(unique(blv)) < 2
                note = sprintf('Binarization at %.4g produced only one class; ROC/AUC, contingency metrics and pie charts are disabled.', threshold);
                handles.curRegr.contigmat.BINARIZATION_THRESHOLD = threshold;
                handles.curRegr.contigmat.NOTES = note;
                payload.binarization.ok = false;
                payload.binarization.message = note;
                payload.summaryRows = NMResultsViewerTools.appendRegressionNoticeRow(payload.summaryRows, note);
            else
                contig = ALLPARAM(blv, bpv);
                contig.BINARIZATION_THRESHOLD = threshold;
                handles.curRegr.b_label = blv;
                handles.curRegr.b_pred = bpv;
                handles.curRegr.contigmat = contig;
                groupnames = {sprintf('Group 1 (>=%1.2f)', threshold), sprintf('Group 2 (< %1.2f)', threshold)};
                colors = struct('group1','#64748b','group2','#94a3b8');
                payload.roc = NMResultsViewerTools.rocPayloadFromLegacy(blv, bpv, contig);
                payload.confusion = NMResultsViewerTools.confusionPayloadFromContingency(contig, groupnames);
                payload.pies = NMResultsViewerTools.pieChartsPayloadFromContingency(contig, blv, groupnames, colors);
                payload.summaryRows = [payload.summaryRows NMResultsViewerTools.metricRowsFromContingency(contig, false, handles)];
                payload.binarization.ok = true;
                payload.binarization.message = sprintf('Continuous regression targets collapsed at threshold %.4g using display_regrplot semantics.', threshold);
            end
        end

        function [payload, handles] = discoveryRegressionOOCVPayloadFromHandles(payload, handles, graphType, thresholdText)
            % buildLegacyOOCVViewerState/load_OOCV own the admitted regression OOCV schema.
            targetIdx = double(handles.curlabel);
            oocvind = double(handles.oocvind);
            O = handles.OOCV(oocvind).data.RegrResults{targetIdx};
            labelsKnown = NMResultsViewerTools.oocvLabelsKnown(handles, oocvind);
            subgroupIndex = double(handles.oocvSubgroupIndex);
            groupIdx = subgroupIndex - 1;

            if groupIdx > 0
                % nm2-allow: nk_OOCV conditionally writes RegrResults.Group only when application subgroup results were produced
                if ~isfield(O,'Group')
                    error('NMResultsViewerTools:MissingOOCVRegressionGroup', ...
                        'The selected OOCV subgroup has no regression Group result material.');
                end
                if groupIdx > numel(O.Group)
                    error('NMResultsViewerTools:InvalidOOCVRegressionGroup', ...
                        'OOCV subgroup %d exceeds the %d persisted regression groups.',groupIdx,numel(O.Group));
                end
                G = O.Group{groupIdx};
                pred = NMResultsViewerTools.asColumnDouble(G.MeanCV2PredictedValues);
                sd = NMResultsViewerTools.asColumnDouble(G.StdCV2PredictedValues);
                if size(G.CICV2PredictedValues,2) ~= 2
                    error('NMResultsViewerTools:OOCVRegressionCIAxisMismatch', ...
                        'OOCV subgroup confidence intervals must have exactly two columns.');
                end
                ci1 = NMResultsViewerTools.asColumnDouble(G.CICV2PredictedValues(:,1));
                ci2 = NMResultsViewerTools.asColumnDouble(G.CICV2PredictedValues(:,2));
                idxLocal = double(G.Index(:));
                if any(~isfinite(idxLocal) | idxLocal < 1 | idxLocal ~= round(idxLocal))
                    error('NMResultsViewerTools:InvalidOOCVRegressionGroupIndex', ...
                        'OOCV subgroup result indices must be finite positive integers.');
                end
                allCases = NMResultsViewerTools.oocvCaseList(handles, oocvind, numel(O.MeanCV2PredictedValues));
                if any(idxLocal > numel(allCases))
                    error('NMResultsViewerTools:OOCVRegressionGroupIndexMismatch', ...
                        'OOCV subgroup result indices exceed the committed OOCV case axis.');
                end
                cases = allCases(idxLocal);
                if labelsKnown
                    label = NMResultsViewerTools.asColumnDouble(G.ObservedValues);
                else
                    label = [];
                end
                Rmetric = struct();
                if labelsKnown
                    if numel(G.ObservedValues) > 2
                        Rmetric = G.Regr;
                    end
                end
            else
                pred = NMResultsViewerTools.asColumnDouble(O.MeanCV2PredictedValues);
                sd = NMResultsViewerTools.asColumnDouble(O.StdCV2PredictedValues);
                if size(O.CICV2PredictedValues,2) ~= 2
                    error('NMResultsViewerTools:OOCVRegressionCIAxisMismatch', ...
                        'OOCV regression confidence intervals must have exactly two columns.');
                end
                ci1 = NMResultsViewerTools.asColumnDouble(O.CICV2PredictedValues(:,1));
                ci2 = NMResultsViewerTools.asColumnDouble(O.CICV2PredictedValues(:,2));
                cases = NMResultsViewerTools.oocvCaseList(handles, oocvind, numel(pred));
                if labelsKnown
                    L = handles.OOCVinfo.Analyses{handles.curranal}.label{oocvind};
                    if size(L,2) < targetIdx
                        error('NMResultsViewerTools:OOCVRegressionLabelTargetMismatch', ...
                            'OOCV regression label matrix has %d columns; compact target %d was requested.',size(L,2),targetIdx);
                    end
                    label = NMResultsViewerTools.asColumnDouble(L(:,targetIdx));
                else
                    label = [];
                end
                Rmetric = O.Regr;
            end

            n = numel(pred);
            if numel(sd) ~= n
                error('NMResultsViewerTools:OOCVRegressionUncertaintyAxisMismatch', ...
                    'OOCV regression SD vector does not match the %d-case prediction axis.',n);
            end
            if numel(ci1) ~= n
                error('NMResultsViewerTools:OOCVRegressionUncertaintyAxisMismatch', ...
                    'OOCV regression lower-CI vector does not match the %d-case prediction axis.',n);
            end
            if numel(ci2) ~= n
                error('NMResultsViewerTools:OOCVRegressionUncertaintyAxisMismatch', ...
                    'OOCV regression upper-CI vector does not match the %d-case prediction axis.',n);
            end
            if numel(cases) ~= n
                error('NMResultsViewerTools:OOCVRegressionCaseAxisMismatch', ...
                    'OOCV regression predictions have %d rows but the selected case axis has %d.',n,numel(cases));
            end
            if ~labelsKnown
                payload = NMResultsViewerTools.discoveryRegressionOOCVUnknownPayload(payload, handles, oocvind, pred, sd, ci1, ci2, cases, graphType, subgroupIndex);
                return;
            end
            if numel(label) ~= n
                error('NMResultsViewerTools:OOCVRegressionLabelAxisMismatch', ...
                    'OOCV regression predictions have %d rows but the selected label axis has %d.',n,numel(label));
            end
            valid = isfinite(label) & isfinite(pred);
            label = label(valid); pred = pred(valid); sd = sd(valid); ci1 = ci1(valid); ci2 = ci2(valid); cases = cases(valid);
            n = numel(pred);
            if n == 0
                payload.regressionPlot = struct('ok',false,'points',[],'message','OOCV regression labels are known, but no finite observed/predicted pairs were available.');
                payload.message = payload.regressionPlot.message;
                return;
            end
            if isempty(thresholdText)
                threshold = mean(pred(isfinite(pred)), 'omitnan');
                thresholdSource = 'mean(OOCV predictions)';
            else
                threshold = str2double(thresholdText);
                thresholdSource = 'user';
                if isnan(threshold)
                    threshold = mean(pred(isfinite(pred)), 'omitnan');
                    thresholdSource = 'mean(OOCV predictions; invalid user value ignored)';
                end
            end

            R = handles.Regr;
            discLabel = NMResultsViewerTools.asColumnDouble(handles.labels(:,targetIdx));
            discPred = NMResultsViewerTools.resultTargetVector(R.mean_predictions, targetIdx);
            discSd = NMResultsViewerTools.resultTargetVector(R.std_predictions, targetIdx);
            discCi1 = NMResultsViewerTools.resultTargetVector(R.CI1_predictions, targetIdx);
            discCi2 = NMResultsViewerTools.resultTargetVector(R.CI2_predictions, targetIdx);
            discMask = logical(NMResultsViewerTools.resultTargetVector(R.index_predictions, targetIdx));
            dN = numel(discPred);
            if numel(discLabel) ~= dN
                error('NMResultsViewerTools:OOCVRegressionReferenceAxisMismatch', ...
                    'Discovery regression labels do not match the reference prediction axis.');
            end
            if numel(discSd) ~= dN
                error('NMResultsViewerTools:OOCVRegressionReferenceAxisMismatch', ...
                    'Discovery regression SD values do not match the reference prediction axis.');
            end
            if numel(discCi1) ~= dN
                error('NMResultsViewerTools:OOCVRegressionReferenceAxisMismatch', ...
                    'Discovery regression lower-CI values do not match the reference prediction axis.');
            end
            if numel(discCi2) ~= dN
                error('NMResultsViewerTools:OOCVRegressionReferenceAxisMismatch', ...
                    'Discovery regression upper-CI values do not match the reference prediction axis.');
            end
            if numel(discMask) ~= dN
                error('NMResultsViewerTools:OOCVRegressionReferenceAxisMismatch', ...
                    'Discovery regression prediction mask does not match the reference prediction axis.');
            end
            discCases = R.cases(:);
            if numel(discCases) ~= dN
                error('NMResultsViewerTools:OOCVRegressionReferenceCaseMismatch', ...
                    'Discovery regression reference has %d predictions but %d case identifiers.',dN,numel(discCases));
            end
            discMask = discMask & isfinite(discLabel) & isfinite(discPred);
            discLabel = discLabel(discMask); discPred = discPred(discMask); discSd = discSd(discMask); discCi1 = discCi1(discMask); discCi2 = discCi2(discMask); discCases = discCases(discMask);

            [xLim, yLim] = NMResultsViewerTools.regressionLimits([discLabel(:); label(:)], [discPred(:); pred(:)]);
            thresholdPayload = NMResultsViewerTools.regressionThresholdPayload(threshold, thresholdSource, xLim, yLim, pred);
            points = NMResultsViewerTools.regressionOOCVPointRows(cases, label, pred, threshold, 'OOCV', '#7c3aed');
            referencePoints = NMResultsViewerTools.regressionOOCVPointRows(discCases, discLabel, discPred, threshold, 'Discovery/CV', '#2563eb');
            payload.regressionPlot = struct();
            payload.regressionPlot.ok = true;
            payload.regressionPlot.mode = 'oocv_regression_overlay';
            payload.regressionPlot.title = 'OOCV regression plot';
            payload.regressionPlot.xLabel = 'Observed targets';
            payload.regressionPlot.yLabel = 'Predicted targets';
            payload.regressionPlot.graphType = graphType;
            payload.regressionPlot.graphLabel = NMResultsViewerTools.regressionGraphTypeLabel(graphType);
            payload.regressionPlot.xLim = double(xLim);
            payload.regressionPlot.yLim = double(yLim);
            payload.regressionPlot.points = points;
            payload.regressionPlot.referencePoints = referencePoints;
            payload.regressionPlot.errorBars = NMResultsViewerTools.regressionErrorBarsPayload(label, pred, sd, ci1, ci2, graphType);
            payload.regressionPlot.referenceErrorBars = NMResultsViewerTools.regressionErrorBarsPayload(discLabel, discPred, discSd, discCi1, discCi2, graphType);
            payload.regressionPlot.fit = NMResultsViewerTools.regressionFitPayload(label, pred);
            payload.regressionPlot.referenceFit = NMResultsViewerTools.regressionFitPayload(discLabel, discPred);
            payload.regressionPlot.threshold = thresholdPayload;
            payload.regressionPlot.n = n;
            payload.regressionPlot.oocvColor = '#7c3aed';
            payload.regressionPlot.referenceColor = '#2563eb';
            payload.binarization = thresholdPayload;
            payload.summaryRows = NMResultsViewerTools.regressionContinuousMetricRows(Rmetric, targetIdx);
            payload.performanceTabulationRows = NMPerformanceMetricTools.regressionRows(Rmetric, targetIdx);
            if isempty(payload.summaryRows)
                payload.summaryRows = NMResultsViewerTools.regressionContinuousMetricRows(R, targetIdx);
                payload.performanceTabulationRows = NMPerformanceMetricTools.regressionRows(R, targetIdx);
            end
            % nm2-allow: nk_OOCV conditionally writes permutation significance and the subgroup selector projects it into handles.PermAnal
            if isfield(handles,'PermAnal')
                payload.summaryRows(end+1) = struct('metric','Model P value:', 'value', sprintf('%.3f', double(handles.PermAnal)), 'source','display_regrplot/OOCV PermAnal'); %#ok<AGROW>
            end
            payload.scoreRows = NMResultsViewerTools.regressionScoreRows(cases, label, pred, sd, ci1, ci2, [points.binaryObserved]', [points.binaryScore]');
            validBinary = isfinite([points.binaryObserved]') & isfinite([points.binaryScore]');
            blv = [points.binaryObserved]'; bpv = [points.binaryScore]';
            blv = blv(validBinary); bpv = bpv(validBinary);
            if numel(unique(blv)) >= 2
                contig = ALLPARAM(blv, bpv);
                contig.BINARIZATION_THRESHOLD = threshold;
                groupnames = {sprintf('Group 1 (>=%1.2f)', threshold), sprintf('Group 2 (< %1.2f)', threshold)};
                colors = struct('group1','#7c3aed','group2','#a78bfa');
                payload.roc = NMResultsViewerTools.rocPayloadFromLegacy(blv, bpv, contig);
                payload.roc.color = '#7c3aed';
                payload.roc.label = 'OOCV ROC';
                refBinObserved = [referencePoints.binaryObserved]';
                refBinScore = [referencePoints.binaryScore]';
                refValidBinary = isfinite(refBinObserved) & isfinite(refBinScore);
                refBinObserved = refBinObserved(refValidBinary);
                refBinScore = refBinScore(refValidBinary);
                if numel(unique(refBinObserved)) >= 2
                    refContig = ALLPARAM(refBinObserved, refBinScore);
                    refRoc = NMResultsViewerTools.rocPayloadFromLegacy(refBinObserved, refBinScore, refContig);
                    refRoc.label = 'Discovery/CV ROC';
                    refRoc.color = '#808080';
                    payload.roc.trainingCurve = refRoc;
                end
                payload.confusion = NMResultsViewerTools.confusionPayloadFromContingency(contig, groupnames);
                payload.pies = NMResultsViewerTools.pieChartsPayloadFromContingency(contig, blv, groupnames, colors);
                payload.summaryRows = [payload.summaryRows NMResultsViewerTools.metricRowsFromContingency(contig, false, handles)];
                payload.binarization.ok = true;
                payload.binarization.message = sprintf('OOCV regression targets collapsed at threshold %.4g using display_regrplot semantics.', threshold);
            else
                note = sprintf('OOCV binarization at %.4g produced only one class; ROC/AUC, contingency metrics and pie charts are disabled.', threshold);
                payload.binarization.ok = false;
                payload.binarization.message = note;
                payload.roc = struct('ok',false,'points',[],'auc',NaN,'message',note);
                payload.confusion = struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{{}},'message',note);
                payload.pies = struct('ok',false,'charts',[],'message',note);
                payload.summaryRows = NMResultsViewerTools.appendRegressionNoticeRow(payload.summaryRows, note);
            end
            payload.oocv = struct('ok',true,'labelsKnown',true,'selectedSubgroupIndex',subgroupIndex, ...
                'globalIndex',handles.OOCV(oocvind).num,'resultField','RegrResults');
        end

        function payload = discoveryRegressionOOCVUnknownPayload(payload, handles, oocvind, pred, sd, ci1, ci2, cases, graphType, subgroupIndex)
            R = handles.Regr;
            refPred = NMResultsViewerTools.resultTargetVector(R.mean_predictions, double(handles.curlabel));
            refPred = refPred(isfinite(refPred));
            validPred = isfinite(pred);
            pred = pred(validPred);
            sd = sd(validPred);
            ci1 = ci1(validPred);
            ci2 = ci2(validPred);
            cases = cases(validPred);
            if isempty(refPred) || isempty(pred)
                payload.regressionPlot = struct('ok',false,'points',[],'message','Regression OOCV labels are unknown and prediction distributions were unavailable.');
                return;
            end
            specs = repmat(struct('x',NaN,'label','','kind','','color','','alpha',0.2,'values',[],'caseIndices',[],'cases',{{}},'expected',{{}},'predicted',{{}},'pointRadius',4), 1, 2);
            specs(1) = NMResultsViewerTools.oocvViolinSpec(1, 'Discovery/CV', 'discovery', '#2563eb', 0.10, refPred, zeros(numel(refPred),1), repmat({''},numel(refPred),1), repmat({'not labeled'},numel(refPred),1), repmat({'Discovery/CV'},numel(refPred),1), 3.6);
            predNames = cell(numel(pred),1);
            for ii=1:numel(pred), predNames{ii} = sprintf('%g', pred(ii)); end
            specs(2) = NMResultsViewerTools.oocvViolinSpec(2, 'OOCV', 'oocv', '#7c3aed', 0.30, pred, (1:numel(pred))', cases(1:numel(pred)), repmat({'not labeled'},numel(pred),1), predNames, 7.0);
            groups = NMResultsViewerTools.oocvViolinGroups(specs);
            allY = [refPred(:); pred(:); 0];
            [~, yLim] = NMResultsViewerTools.legacyLimits((1:numel(allY))', allY);
            groups = NMResultsViewerTools.positionViolinDots(groups, yLim, [0.5 2.5]);
            cp = struct();
            cp.ok = true;
            cp.mode = 'oocv_regression_violin';
            cp.title = 'OOCV regression prediction distribution';
            cp.xLabel = 'Samples';
            cp.yLabel = 'Predicted outcome';
            cp.xLim = [0.5 2.5];
            cp.yLim = double(yLim);
            cp.violinGroups = groups;
            cp.points = NMResultsViewerTools.flattenViolinPoints(groups);
            cp.zeroLine = NMResultsViewerTools.zeroLinePayload([0.5 2.5], [1 2], 0, false);
            cp.legend = NMResultsViewerTools.violinLegendItems(groups);
            cp.graphType = graphType;
            payload.regressionPlot = cp;
            payload.summaryRows = NMResultsViewerTools.appendRegressionNoticeRow(repmat(struct('metric','','value','','source',''),1,0), 'OOCV regression labels are unavailable; performance metrics are suppressed.');
            payload.scoreRows = NMResultsViewerTools.regressionOOCVUnknownScoreRows(cases, pred, sd, ci1, ci2);
            payload.roc = struct('ok',false,'points',[],'auc',NaN,'message','OOCV regression labels are unavailable; ROC/AUC is suppressed.');
            payload.confusion = struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{{}},'message','OOCV regression labels are unavailable; contingency matrix is suppressed.');
            payload.pies = struct('ok',false,'charts',[],'message','OOCV regression labels are unavailable; pie charts are suppressed.');
            payload.oocv = struct('ok',true,'labelsKnown',false,'selectedSubgroupIndex',subgroupIndex, ...
                'globalIndex',handles.OOCV(oocvind).num,'resultField','RegrResults');
        end

        function points = regressionOOCVPointRows(cases, observed, predicted, threshold, sourceLabel, color)
            n = min([numel(cases), numel(observed), numel(predicted)]);
            tmpl = struct('x',NaN,'y',NaN,'caseId','','observed',NaN,'predicted',NaN, ...
                'binaryObserved',NaN,'binaryScore',NaN,'binaryPredicted','','error',false,'tooltip','','source','','color','');
            points = repmat(tmpl, 1, n);
            for i = 1:n
                bLabel = NaN; bScore = NaN; binPred = 'n/a'; err = false;
                if isfinite(threshold) && isfinite(observed(i)) && isfinite(predicted(i))
                    bLabel = -1; if observed(i) >= threshold, bLabel = 1; end
                    bScore = predicted(i) - threshold;
                    if bScore >= 0, binPred = 'Group 1'; else, binPred = 'Group 2'; end
                    err = sign(bScore) ~= bLabel;
                end
                points(i) = struct('x',double(observed(i)),'y',double(predicted(i)),'caseId',cases{i}, ...
                    'observed',double(observed(i)),'predicted',double(predicted(i)), ...
                    'binaryObserved',double(bLabel),'binaryScore',double(bScore),'binaryPredicted',binPred,'error',logical(err), ...
                    'tooltip',sprintf('%s\nSubject ID [%d]: %s\nObserved Target: %g\nPredicted Target: %g', sourceLabel, i, cases{i}, observed(i), predicted(i)), ...
                    'source',sourceLabel,'color',color);
            end
        end

        function rows = regressionOOCVUnknownScoreRows(cases, pred, sd, ci1, ci2)
            n = numel(cases);
            tmpl = struct('case','','observed',NaN,'predicted',NaN,'error','', ...
                'score',NaN,'stdScore',NaN,'ciLow',NaN,'ciHigh',NaN, ...
                'binaryObserved',NaN,'binaryScore',NaN,'binaryPredicted','');
            rows = repmat(tmpl, 1, n);
            for i = 1:n
                rows(i) = struct('case',cases{i}, 'observed',NaN, 'predicted',double(pred(i)), ...
                    'error','', 'score',double(pred(i)), 'stdScore',double(sd(i)), ...
                    'ciLow',double(ci1(i)), 'ciHigh',double(ci2(i)), ...
                    'binaryObserved',NaN, 'binaryScore',NaN, 'binaryPredicted','');
            end
        end

        function [payload, handles] = discoveryMultiClassPayloadFromHandles(payload, handles, modeIdx)
            % Materialize CV multi-class Model Performance from transformed Results Viewer handles.
            MC = handles.MultiClass;
            probabilities = double(MC.probabilities);
            labels = double(MC.labels(:));
            N = numel(labels);
            K = size(probabilities,2);
            cases = NMResultsViewerTools.legacyCaseTextColumn(MC.cases, N);
            % nm2-allow: load_GDdims fixes transformed probabilities, labels and cases on one selected-case axis
            if size(probabilities,1) ~= N || K < 1 || numel(cases) ~= N
                error('NMResultsViewerTools:MultiClassCaseAxisMismatch', ...
                    'Transformed multi-class probabilities, labels and cases must share one non-empty case axis.');
            end
            % nm2-allow: load_GDdims writes both one-vs-rest matrices on the exact transformed case-by-group axis
            if ~isequal(size(MC.onevsall_labels),[N K]) || ~isequal(size(MC.onevsall_scores),[N K])
                error('NMResultsViewerTools:MultiClassOvRAxisMismatch', ...
                    'Transformed one-vs-rest labels and scores must match the multi-class case-by-class axis.');
            end
            predicted = double(MC.multi_predictionsCV2(:));
            errors = logical(MC.errors(:));
            % nm2-allow: load_GDdims writes predictions and error flags on the exact transformed case axis
            if numel(predicted) ~= N || numel(errors) ~= N
                error('NMResultsViewerTools:MultiClassPredictionAxisMismatch', ...
                    'Transformed multi-class predictions and errors must match the case axis.');
            end

            rawXaxis = [];
            % nm2-allow: applyPlotVectorXAxisOverride conditionally writes MultiClass.Xaxis only for a resolved public x-axis request.
            if isfield(MC,'Xaxis')
                rawXaxis = double(MC.Xaxis(:));
                if numel(rawXaxis) ~= N
                    error('NMResultsViewerTools:MultiClassXAxisMismatch', ...
                        'The optional transformed multi-class x-axis must match the case axis.');
                end
            end

            plotMask = logical(NMResultsViewerTools.viewerSubIndexMask(handles, N));
            plotMask = plotMask(:);
            if numel(plotMask) ~= N
                error('NMResultsViewerTools:MultiClassSubgroupAxisMismatch', ...
                    'The transformed multi-class subgroup mask must match the case axis.');
            end
            if ~any(plotMask)
                payload.multiClassPlot = struct('ok',false,'points',[],'predictedPoints',[], ...
                    'message','The selected subgroup vector excludes all training/CV cases.');
                payload.message = payload.multiClassPlot.message;
                return;
            end
            plotProbabilities = probabilities(plotMask,:);
            plotLabels = labels(plotMask);
            plotPredicted = predicted(plotMask);
            plotErrors = errors(plotMask);
            plotCases = cases(plotMask);
            plotCaseIndices = find(plotMask);
            if ~isempty(rawXaxis), rawXaxis = rawXaxis(plotMask); end
            nPlot = size(plotProbabilities,1);
            if ~isempty(rawXaxis)
                plotX = rawXaxis;
                alternativeXAxis = true;
                xLabel = handles.XaxisName;
                if isempty(xLabel), xLabel = 'X axis'; end
            else
                plotX = (1:nPlot)';
                alternativeXAxis = false;
                xLabel = 'Subject No.';
            end

            groupNames = NMResultsViewerTools.multiClassGroupNames(handles, K);
            colors = NMResultsViewerTools.multiClassColors(handles, K);
            modeIdx = round(double(modeIdx));
            if modeIdx < 1 || modeIdx > K + 1
                error('NMResultsViewerTools:InvalidMultiClassModeIndex', ...
                    'Multi-class mode index %g is outside the produced selector axis 1:%d.', modeIdx, K+1);
            end
            selectedClass = modeIdx - 1;
            payload.selectedMultiClassModeIndex = modeIdx;
            if selectedClass >= 1
                payload.selectedMultiClassModeLabel = sprintf('%s vs REST', groupNames{selectedClass});
            else
                payload.selectedMultiClassModeLabel = 'Multi-group classification';
            end
            payload.selectedOneVsRestClass = selectedClass;
            payload.multiClassGeneralMode = selectedClass < 1;
            payload.multiClassGroupNames = groupNames;
            payload.multiClassPlot = NMResultsViewerTools.multiClassPlotPayload(plotProbabilities, plotLabels, plotPredicted, plotErrors, plotCases, groupNames, colors, selectedClass, plotX, plotCaseIndices, xLabel, alternativeXAxis);
            if ~isempty(handles.alphaVectorWarning)
                payload.multiClassPlot.message = handles.alphaVectorWarning;
                payload.message = handles.alphaVectorWarning;
            end
            payload.roc = NMResultsViewerTools.multiClassRocPayload(MC, groupNames, colors, selectedClass);
            payload.confusion = NMResultsViewerTools.multiClassConfusionPayload(MC, labels, predicted, groupNames, selectedClass);
            payload.cobweb = NMResultsViewerTools.multiClassCobwebPayload(payload.confusion, groupNames, selectedClass);
            payload.summaryRows = NMResultsViewerTools.multiClassSummaryRows(MC, labels, predicted, groupNames, selectedClass, payload.confusion, payload.cobweb);
            payload.performanceTabulationRows = NMPerformanceMetricTools.emptyRows();
            if selectedClass >= 1
                selectedContingency = NMResultsViewerTools.multiClassContingencyForClass(MC, selectedClass);
                payload.performanceTabulationRows = NMPerformanceMetricTools.classificationRows(selectedContingency);
            end
            [payload.scoreRows, payload.multiClassScoreColumns] = NMResultsViewerTools.multiClassScoreRows(probabilities, labels, predicted, errors, cases, groupNames, selectedClass);
            payload.multiClassTables = NMResultsViewerTools.multiClassTablePayloads(MC, probabilities, labels, predicted, errors, cases, groupNames, selectedClass, payload.confusion, payload.cobweb, payload.summaryRows, payload.scoreRows, payload.multiClassScoreColumns);
            if selectedClass < 1
                payload.multiClassSummaryVisuals = NMResultsViewerTools.multiClassOOCVVisualPayloads(probabilities, labels, predicted, true, cases, groupNames, colors, 'CV');
            else
                payload.multiClassSummaryVisuals = struct('ok',false,'distribution',struct(),'confidence',struct(),'margin',struct(), ...
                    'message','Multi-class summary plots are shown only in aggregate multi-group mode.');
            end
            payload.pies = struct('ok',false,'charts',[],'message','Pre-/post-test probability pies are only available in class-vs-REST mode.');

            if selectedClass >= 1
                c = NMResultsViewerTools.multiClassContingencyForClass(MC, selectedClass);
                labelh = double(MC.onevsall_labels(:,selectedClass));
                selectedNames = {groupNames{selectedClass}, 'REST'};
                selectedColors = struct('group1',colors{selectedClass}, 'group2','#94a3b8');
                payload.confusion = NMResultsViewerTools.confusionPayloadFromContingency(c, selectedNames);
                payload.pies = NMResultsViewerTools.pieChartsPayloadFromContingency(c, labelh, selectedNames, selectedColors);
            end
        end

        function [payload, handles] = oocvMultiClassPayloadFromHandles(payload, handles)
            [Cont, probabilities, expected, predicted, cases, groupNames, colors, labelsKnown, K, oocvind] = ...
                NMResultsViewerTools.oocvMultiClassVectorsFromHandles(handles);
            nAll = numel(predicted);
            [subgroupIndex, subgroupMask] = NMResultsViewerTools.multiClassOOCVSubgroupSelection(handles, oocvind, nAll);
            if ~any(subgroupMask)
                error('NMResultsViewerTools:EmptyOOCVMultiClassSubgroup', ...
                    'The selected OOCV subgroup does not contain any cases on the current OOCV axis.');
            end
            probabilities = probabilities(subgroupMask,:);
            expected = expected(subgroupMask);
            predicted = predicted(subgroupMask);
            cases = cases(subgroupMask);
            n = numel(predicted);
            predIdx = double(predicted(:));
            % nm2-allow: nk_MultiPerfComp may retain NaN for cases without a finite ensemble prediction
            if any(isfinite(predIdx) & (predIdx ~= fix(predIdx) | predIdx < 1 | predIdx > K))
                error('NMResultsViewerTools:InvalidOOCVMultiPredictions', ...
                    'OOCV multi-class predictions must be integer class indices on the produced group axis.');
            end
            expIdx = double(expected(:));
            if labelsKnown && any(isfinite(expIdx) & (expIdx ~= fix(expIdx) | expIdx < 1 | expIdx > K))
                error('NMResultsViewerTools:InvalidOOCVMultiLabels', ...
                    'OOCV multi-class labels must be integer class indices on the produced group axis.');
            end
            if labelsKnown, errors = predIdx ~= expIdx; else, errors = false(n,1); end

            modeIdx = round(double(payload.selectedMultiClassModeIndex));
            if modeIdx < 1 || modeIdx > K + 1
                error('NMResultsViewerTools:InvalidMultiClassModeIndex', ...
                    'Multi-class mode index %g is outside the produced selector axis 1:%d.', modeIdx, K+1);
            end
            selectedClass = modeIdx - 1;
            if ~labelsKnown && selectedClass >= 1
                error('NMResultsViewerTools:OOCVLabelsUnavailableForOvR', ...
                    'Class-vs-REST OOCV performance requires the effective OOCV target labels.');
            end

            if selectedClass >= 1
                evalMask = isfinite(expIdx) & isfinite(predIdx);
                if ~any(evalMask)
                    error('NMResultsViewerTools:EmptyOOCVMultiClassEvaluation', ...
                        'No cases with finite expected and predicted labels remain for class-vs-REST OOCV evaluation.');
                end
                legacyMC = NMResultsViewerTools.multiClassOOCVLegacyStruct(probabilities(evalMask,:), expIdx(evalMask), ...
                    predIdx(evalMask), errors(evalMask), cases(evalMask), groupNames, K);
                oocvHandles = handles;
                oocvHandles.MultiClass = legacyMC;
                [payload, handles] = NMResultsViewerTools.discoveryMultiClassPayloadFromHandles(payload, oocvHandles, modeIdx); %#ok<ASGLU>
                payload.multiClassOOCVVisuals = struct('ok',false,'distribution',struct(),'confidence',struct(),'margin',struct(), ...
                    'message','Predicted-class distribution, confidence and margin summary plots are shown only in aggregate multi-group OOCV mode.');
                payload.multiClassSummaryVisuals = payload.multiClassOOCVVisuals;
                payload.oocv = NMResultsViewerTools.oocvMetadataPayload(handles, oocvind, 'MultiResults', labelsKnown);
                payload.message = sprintf('Class-vs-REST OOCV payload for %s on the selected DataIO OOCV subgroup coordinate.', groupNames{selectedClass});
                return;
            end

            [scoreRows, scoreColumns] = NMResultsViewerTools.multiClassOOCVScoreRows(probabilities, expIdx, predIdx, labelsKnown, cases, groupNames);
            payload.scoreRows = scoreRows;
            payload.multiClassScoreColumns = scoreColumns;
            payload.scoreColumns = scoreColumns;
            payload.summaryRows = NMResultsViewerTools.multiClassOOCVSummaryRows(probabilities, expIdx, predIdx, labelsKnown, groupNames);
            if labelsKnown
                if subgroupIndex == 1
                    payload.confusion = NMResultsViewerTools.multiClassConfusionPayload(Cont.MultiClass, expIdx, predIdx, groupNames, 0);
                    rowSupport = sum(payload.confusion.matrix,2);
                    colSupport = sum(payload.confusion.matrix,1);
                    payload.confusion.expectedSupport = double(rowSupport(:)');
                    payload.confusion.predictedSupport = double(colSupport(:)');
                    payload.confusion.absentExpectedLabels = logical(rowSupport(:)' == 0);
                    payload.confusion.absentPredictedLabels = logical(colSupport(:)' == 0);
                else
                    payload.confusion = NMResultsViewerTools.multiClassOOCVConfusionPayload(expIdx, predIdx, groupNames);
                end
                payload.cobweb = NMResultsViewerTools.multiClassCobwebPayload(payload.confusion, groupNames, 0);
                if payload.cobweb.ok
                    payload.cobweb.series.modelLabel = 'OOCV';
                    payload.cobweb.missingLegendLabel = 'Missing in OOCV data';
                    payload.cobweb = NMResultsViewerTools.attachMultiClassCVReferenceCobweb(payload.cobweb, handles, groupNames);
                    if any(payload.confusion.absentExpectedLabels)
                        absentNames = groupNames(logical(payload.confusion.absentExpectedLabels));
                        payload.cobweb.message = sprintf('%s Missing expected OOCV classes remain visible as shaded axes: %s.', payload.cobweb.message, strjoin(absentNames, ', '));
                    end
                end
                payload.pies = struct('ok',payload.cobweb.ok,'charts',[],'message',payload.cobweb.message);
            else
                payload.confusion = struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{groupNames},'message','OOCV labels are unavailable; multi-class performance metrics and confusion matrix are suppressed.');
                payload.cobweb = struct('ok',false,'axes',[],'series',[],'tmr',NaN,'message','OOCV labels are unavailable; multi-class misclassification web is suppressed.');
                payload.pies = struct('ok',false,'charts',[],'message','OOCV labels are unavailable; multi-class pie/cobweb visualization is suppressed.');
            end
            payload.multiClassTables = NMResultsViewerTools.multiClassOOCVTablePayloads(payload.summaryRows, scoreRows, scoreColumns, payload.confusion, groupNames, labelsKnown);
            visualMask = isfinite(predIdx);
            if labelsKnown, visualMask = visualMask & isfinite(expIdx); end
            if any(visualMask)
                payload.multiClassOOCVVisuals = NMResultsViewerTools.multiClassOOCVVisualPayloads(probabilities(visualMask,:), expIdx(visualMask), ...
                    predIdx(visualMask), labelsKnown, cases(visualMask), groupNames, colors, 'OOCV');
                plotLabels = predIdx(visualMask);
                plotErrors = false(sum(visualMask),1);
                if labelsKnown
                    plotLabels = expIdx(visualMask);
                    plotErrors = predIdx(visualMask) ~= expIdx(visualMask);
                end
                nPlot = sum(visualMask);
                payload.multiClassPlot = NMResultsViewerTools.multiClassPlotPayload(probabilities(visualMask,:), plotLabels, predIdx(visualMask), ...
                    plotErrors, cases(visualMask), groupNames, colors, 0, (1:nPlot)', find(visualMask), 'Subject No.', false);
                payload.multiClassPlot.message = 'Multi-class OOCV probability plot on cases with finite multiclass predictions.';
            else
                payload.multiClassOOCVVisuals = struct('ok',false,'distribution',struct(),'confidence',struct(),'margin',struct(), ...
                    'message','No finite multi-class OOCV predictions are available for summary visualization.');
                payload.multiClassPlot = struct('ok',false,'points',[],'predictedPoints',[],'backgroundPatches',[], ...
                    'groupNames',{groupNames},'colors',{colors},'selectedClassIndex',0,'xLim',[0 1],'yLim',[0 1], ...
                    'zeroLine',0.5,'xLabel','Subject No.','yLabel','Multi-class probabilities','alternativeXAxis',false, ...
                    'message','No finite multi-class OOCV predictions are available for plotting.');
            end
            payload.multiClassSummaryVisuals = payload.multiClassOOCVVisuals;
            payload.roc = NMResultsViewerTools.multiClassOOCVAggregateRocPayload(probabilities, expIdx, predIdx, labelsKnown, cases, groupNames, colors, K);
            payload.selectedMultiClassModeIndex = modeIdx;
            payload.selectedMultiClassModeLabel = 'Multi-group OOCV';
            payload.selectedOneVsRestClass = 0;
            payload.multiClassGeneralMode = true;
            payload.oocv = NMResultsViewerTools.oocvMetadataPayload(handles, oocvind, 'MultiResults', labelsKnown);
        end

        function [Cont, probabilities, expected, predicted, cases, groupNames, colors, labelsKnown, K, oocvind] = oocvMultiClassVectorsFromHandles(handles)
            % Resolve the fixed transformed OOCV multi-class case axis.
            oocvind = double(handles.oocvind);
            data = handles.OOCV(oocvind).data;
            labelIdx = double(handles.curlabel);
            Cont = data.MultiResults{labelIdx};
            MC = Cont.MultiClass;
            predicted = double(MC.multi_predictionsCV2(:));
            n = numel(predicted);
            labelsKnown = NMResultsViewerTools.oocvLabelsKnown(handles, oocvind);
            cases = NMResultsViewerTools.oocvCaseList(handles, oocvind, n);
            if numel(cases) ~= n
                error('NMResultsViewerTools:OOCVMultiCaseAxisMismatch', ...
                    'OOCV case IDs must match the produced multi-class prediction axis.');
            end
            expected = NaN(n,1);
            if labelsKnown
                entry = handles.OOCVinfo.Analyses{handles.curranal};
                expected = double(entry.label{oocvind}(:));
                if numel(expected) ~= n
                    error('NMResultsViewerTools:OOCVMultiLabelAxisMismatch', ...
                        'Known OOCV labels must match the produced multi-class prediction axis.');
                end
            end
            K = numel(handles.NM.groupnames);
            if K < 2
                error('NMResultsViewerTools:InvalidMultiClassGroupAxis', ...
                    'A multi-class Results Viewer context requires at least two produced group names.');
            end
            probabilities = NMResultsViewerTools.multiClassOOCVProbabilityMatrix(MC.multi_probabilitiesCV2, n);
            if size(probabilities,2) ~= K
                error('NMResultsViewerTools:OOCVMultiProbabilityClassMismatch', ...
                    'OOCV multi-class probability columns must match the produced group-name axis.');
            end
            groupNames = NMResultsViewerTools.multiClassGroupNames(handles, K);
            colors = NMResultsViewerTools.multiClassColors(handles, K);
        end

        function roc = multiClassOOCVAggregateRocPayload(probabilities, labels, predicted, labelsKnown, cases, groupNames, colors, K)
            roc = struct('ok',false,'points',[],'auc',NaN,'curves',[], ...
                'multi',true,'message','Multi-class OOCV one-vs-REST ROC curves require labels-known OOCV data.');
            if ~labelsKnown
                roc.message = 'OOCV labels are unavailable; multi-class one-vs-REST ROC curves are suppressed.';
                return;
            end
            valid = isfinite(labels) & isfinite(predicted);
            if ~any(valid)
                roc.message = 'No finite expected/predicted OOCV class pairs are available for ROC evaluation.';
                return;
            end
            errors = predicted(valid) ~= labels(valid);
            legacyMC = NMResultsViewerTools.multiClassOOCVLegacyStruct(probabilities(valid,:), labels(valid), predicted(valid), errors, cases(valid), groupNames, K);
            roc = NMResultsViewerTools.multiClassRocPayload(legacyMC, groupNames, colors, 0);
            if roc.ok
                roc.message = 'Overlaid OOCV one-vs-rest ROC curves generated from the writer-produced K-class probability matrix.';
            else
                roc.message = 'No OOCV one-vs-rest ROC curve could be generated from the selected multi-class result.';
            end
        end

        function MC = multiClassOOCVLegacyStruct(probabilities, labels, predicted, errors, cases, groupNames, K)
            n = numel(labels);
            % nm2-allow: canonical OOCV projection fixes the probability matrix on the exact selected case-by-group axes
            if size(probabilities,1) ~= n || size(probabilities,2) ~= K
                error('NMResultsViewerTools:OOCVMultiLegacyAxisMismatch', ...
                    'The OOCV multi-class probability matrix must match the selected case-by-group axes.');
            end
            % nm2-allow: canonical OOCV projection fixes prediction, error, case and group vectors on those same axes
            if numel(predicted) ~= n || numel(errors) ~= n || numel(cases) ~= n || numel(groupNames) ~= K
                error('NMResultsViewerTools:OOCVMultiLegacyAxisMismatch', ...
                    'The OOCV multi-class compatibility projection requires one exact case-by-class coordinate system.');
            end
            MC = struct();
            MC.probabilities = double(probabilities);
            MC.labels = double(labels(:));
            MC.cases = cases(:);
            MC.multi_predictionsCV2 = double(predicted(:));
            MC.errors = logical(errors(:));
            MC.confusion_matrix = NMResultsViewerTools.multiClassConfusionFromLabels(MC.labels, MC.multi_predictionsCV2, K);
            MC.onevsall_labels = zeros(n,K);
            MC.onevsall_scores = double(probabilities);
            MC.class = cell(1,K);
            MC.X = cell(1,K);
            MC.Y = cell(1,K);
            for jj = 1:K
                MC.onevsall_labels(:,jj) = double(MC.labels == jj);
                MC.class{jj} = NMResultsViewerTools.multiClassOOCVContingencyFromVectors( ...
                    MC.onevsall_labels(:,jj), MC.onevsall_scores(:,jj), MC.multi_predictionsCV2 == jj, groupNames{jj});
                MC.X{jj} = MC.class{jj}.X;
                MC.Y{jj} = MC.class{jj}.Y;
            end
        end

        function c = multiClassOOCVContingencyFromVectors(labels01, scores, predictedPositive, className)
            labels01 = double(labels01(:)) > 0;
            scores = double(scores(:));
            predictedPositive = logical(predictedPositive(:));
            n = numel(labels01);
            % nm2-allow: canonical OOCV one-vs-rest projection fixes labels, scores and predictions on one selected-case axis
            if numel(scores) ~= n || numel(predictedPositive) ~= n
                error('NMResultsViewerTools:OOCVOvRAxisMismatch', ...
                    'One-vs-rest labels, scores and predictions must share one case axis.');
            end
            valid = isfinite(scores);
            labels01 = labels01(valid);
            scores = scores(valid);
            predictedPositive = predictedPositive(valid);
            labelPM = 2*double(labels01) - 1;
            predPM = 2*double(predictedPositive) - 1;
            c = ALLPARAM(labelPM, predPM);
            x = []; y = []; auc = NaN;
            if numel(unique(labels01)) == 2
                [x, y, ~, auc] = perfcurve2(double(labels01), scores, 1);
            end
            c.AUC = double(auc);
            c.X = double(x(:));
            c.Y = double(y(:));
            c.class = className;
        end

        function probabilities = multiClassOOCVProbabilityMatrix(rawProb, n)
            probabilities = double(rawProb);
            if size(probabilities,1) ~= n
                error('NMResultsViewerTools:InvalidOOCVMultiProbabilities', ...
                    'MultiClass.multi_probabilitiesCV2 must have one row per OOCV case.');
            end
        end

        function payload = oocvMetadataPayload(handles, oocvind, resultField, labelsKnown)
            entry = handles.OOCVinfo.Analyses{handles.curranal};
            payload = struct('ok',true,'localIndex',oocvind,'globalIndex',entry.OOCVvec(oocvind), ...
                'labelsKnown',logical(labelsKnown),'resultField',resultField, ...
                'descriptor',entry.descriptor{oocvind}, ...
                'selectedSubgroupIndex',handles.oocvSubgroupIndex, ...
                'selectedSubgroupLabel',handles.oocvSubgroupLabel);
        end
        function [rows, columns] = multiClassOOCVScoreRows(probabilities, expected, predicted, labelsKnown, cases, groupNames)
            [N,K] = size(probabilities);
            if labelsKnown
                keys = {'case','expected','predicted','correct','error','maxProbability','secondProbability','probabilityMargin','entropy'};
                labelsOut = {'Case','Expected class','Predicted class','Correct','Error','Max probability','Second probability','Probability margin','Entropy'};
            else
                keys = {'case','predicted','maxProbability','secondProbability','probabilityMargin','entropy'};
                labelsOut = {'Case','Predicted class','Max probability','Second probability','Probability margin','Entropy'};
            end
            for jj = 1:K
                keys{end+1} = sprintf('p%03d', jj); %#ok<AGROW>
                labelsOut{end+1} = sprintf('P(%s)', groupNames{jj}); %#ok<AGROW>
            end
            columns = NMResultsViewerTools.tableColumnStruct(keys, labelsOut);
            tmpl = struct();
            for jj = 1:numel(keys), tmpl.(keys{jj}) = ''; end
            for jj = 1:K, tmpl.(sprintf('p%03d', jj)) = NaN; end
            rows = repmat(tmpl, 1, N);
            for ii = 1:N
                predValue = double(predicted(ii));
                probs = double(probabilities(ii,:));
                sorted = sort(probs(isfinite(probs)), 'descend');
                top1 = NaN; top2 = NaN;
                if ~isempty(sorted), top1 = sorted(1); end
                if numel(sorted) >= 2, top2 = sorted(2); end
                rows(ii).case = cases{ii};
                if isfinite(predValue)
                    predIdx = round(predValue);
                    rows(ii).predicted = groupNames{predIdx};
                else
                    predIdx = NaN;
                    rows(ii).predicted = 'Unavailable';
                end
                rows(ii).maxProbability = double(top1);
                rows(ii).secondProbability = double(top2);
                rows(ii).probabilityMargin = double(top1 - top2);
                rows(ii).entropy = double(NMResultsViewerTools.normalizedEntropy(probs));
                if labelsKnown
                    expValue = double(expected(ii));
                    if isfinite(expValue)
                        expIdx = round(expValue);
                        rows(ii).expected = groupNames{expIdx};
                    else
                        expIdx = NaN;
                        rows(ii).expected = 'Unavailable';
                    end
                    rows(ii).correct = logical(isfinite(predIdx) && isfinite(expIdx) && predIdx == expIdx);
                    rows(ii).error = logical(isfinite(predIdx) && isfinite(expIdx) && predIdx ~= expIdx);
                end
                for jj = 1:K
                    rows(ii).(sprintf('p%03d', jj)) = double(probabilities(ii,jj));
                end
            end
        end

        function e = normalizedEntropy(probs)
            p = double(probs(:));
            p = p(isfinite(p) & p > 0);
            if isempty(p)
                e = NaN;
                return;
            end
            p = p ./ sum(p);
            if numel(p) <= 1
                e = 0;
            else
                e = -sum(p .* log(p)) ./ log(numel(p));
            end
        end

        function rows = multiClassOOCVSummaryRows(probabilities, expected, predicted, labelsKnown, groupNames)
            tmpl = struct('metric','','value','','source','MultiResults.MultiClass');
            rows = repmat(tmpl, 1, 0);
            K = numel(groupNames);
            N = numel(predicted);
            predValid = isfinite(predicted);
            rows(end+1) = struct('metric','Cases:', 'value',sprintf('%d', N), 'source','MultiResults.MultiClass'); %#ok<AGROW>
            rows(end+1) = struct('metric','Groups:', 'value',sprintf('%d', K), 'source','MultiResults.MultiClass'); %#ok<AGROW>
            if labelsKnown, labelState = 'true'; else, labelState = 'false'; end
            rows(end+1) = struct('metric','Labels known:', 'value',labelState, 'source','OOCVinfo.labels_known'); %#ok<AGROW>
            if labelsKnown
                valid = predValid & isfinite(expected);
                acc = NaN;
                if any(valid), acc = sum(predicted(valid) == expected(valid)) ./ sum(valid) .* 100; end
                rows(end+1) = struct('metric','Multi-class OOCV accuracy [%]:', 'value',sprintf('%.1f', acc), 'source','OOCV expected/predicted labels'); %#ok<AGROW>
                conf = NMResultsViewerTools.multiClassOOCVConfusionPayload(expected, predicted, groupNames);
                M = double(conf.matrix);
                rs = sum(M,2);
                rec = NaN(size(rs));
                for rr = 1:numel(rs)
                    if rs(rr) > 0, rec(rr) = M(rr,rr) ./ rs(rr) * 100; end
                end
                meanRecall = mean(rec(isfinite(rec)));
                rows(end+1) = struct('metric','Mean class recall [%]:', 'value',sprintf('%.1f', meanRecall), 'source','OOCV confusion matrix'); %#ok<AGROW>
            else
                rows(end+1) = struct('metric','Performance metrics:', 'value','Suppressed because OOCV labels are unavailable', 'source','OOCVinfo.labels_known'); %#ok<AGROW>
            end
            if any(isfinite(probabilities(:)))
                mx = max(probabilities, [], 2, 'omitnan');
                ent = NaN(size(mx));
                for ii = 1:numel(mx), ent(ii) = NMResultsViewerTools.normalizedEntropy(probabilities(ii,:)); end
                rows(end+1) = struct('metric','Mean max probability:', 'value',sprintf('%.3f', mean(mx(isfinite(mx)))), 'source','MultiClass.multi_probabilitiesCV2'); %#ok<AGROW>
                rows(end+1) = struct('metric','Mean entropy:', 'value',sprintf('%.3f', mean(ent(isfinite(ent)))), 'source','MultiClass.multi_probabilitiesCV2'); %#ok<AGROW>
            else
                rows(end+1) = struct('metric','Class probabilities:', 'value','Unavailable in MultiClass.multi_probabilitiesCV2', 'source','MultiResults.MultiClass'); %#ok<AGROW>
            end
        end

        function conf = multiClassOOCVConfusionPayload(expected, predicted, groupNames)
            K = numel(groupNames);
            M = NMResultsViewerTools.multiClassConfusionFromLabels(expected, predicted, K);
            rowSum = sum(M,2);
            colSum = sum(M,1);
            P = zeros(size(M));
            for rr = 1:size(M,1)
                if rowSum(rr) > 0, P(rr,:) = M(rr,:) ./ rowSum(rr) * 100; end
            end
            absentExpected = rowSum(:)' == 0;
            absentPredicted = colSum(:)' == 0;
            conf = struct('ok',true,'matrix',M,'percentMatrix',P,'labels',{groupNames}, ...
                'expectedSupport',double(rowSum(:)'),'predictedSupport',double(colSum(:)'), ...
                'absentExpectedLabels',logical(absentExpected),'absentPredictedLabels',logical(absentPredicted), ...
                'message','Multi-class OOCV confusion matrix computed from expected and predicted OOCV labels; zero-support labels are retained from the model/group schema.');
        end

        function tables = multiClassOOCVTablePayloads(summaryRows, scoreRows, scoreColumns, conf, groupNames, labelsKnown)
            metricCols = NMResultsViewerTools.tableColumnStruct({'metric','value'}, {'Metric','Value'});
            tables = struct();
            tables.summary = NMResultsViewerTools.namedTable('Summary', 'Multi-class OOCV summary', metricCols, summaryRows);
            tables.caseScores = NMResultsViewerTools.namedTable('CaseScores', 'Case-level multi-class OOCV probabilities', scoreColumns, scoreRows);
            if labelsKnown
                [cntRows,cntCols] = NMResultsViewerTools.multiClassConfusionTableRows(conf, groupNames, false);
                tables.confusionCounts = NMResultsViewerTools.namedTable('ConfusionCounts', 'OOCV observed-by-predicted confusion counts', cntCols, cntRows);
                [pctRows,pctCols] = NMResultsViewerTools.multiClassConfusionTableRows(conf, groupNames, true);
                tables.confusionRowPercent = NMResultsViewerTools.namedTable('ConfusionRowPercent', 'OOCV row-normalized confusion matrix [%]', pctCols, pctRows);
                metricRows = NMResultsViewerTools.multiClassOOCVPerClassMetricRows(conf, groupNames);
                metricColumns = NMResultsViewerTools.tableColumnStruct({'class','support','prevalencePercent','sensitivityPercent','specificityPercent','ppvPercent','npvPercent','f1Percent','balancedAccuracyPercent','missingInOOCVData'}, ...
                    {'Class','Support','Prevalence [%]','Sensitivity / TPR [%]','Specificity [%]','PPV [%]','NPV [%]','F1 [%]','Balanced accuracy [%]','Missing in OOCV data'});
                tables.perClassMetrics = NMResultsViewerTools.namedTable('PerClassMetrics', 'OOCV per-class metrics', metricColumns, metricRows);
                axRows = NMResultsViewerTools.multiClassMisclassificationAxisRows(conf, groupNames);
                axCols = NMResultsViewerTools.tableColumnStruct({'axis','sourceClass','targetClass','count','sourceTotal','misclassificationLikelihoodPercent','randomBaselinePercent','excessVsRandomPercent'}, ...
                    {'Axis','Source class','Target class','Count','Source-class total','Misclassification likelihood [%]','Random baseline [%]','Excess vs random [%]'});
                tables.misclassificationAxes = NMResultsViewerTools.namedTable('MisclassificationAxes', 'OOCV cobweb misclassification axes', axCols, axRows);
            else
                emptyCols = NMResultsViewerTools.tableColumnStruct({'message'}, {'Message'});
                emptyRows = struct('message','Suppressed because OOCV labels are unavailable.');
                tables.confusionCounts = NMResultsViewerTools.namedTable('ConfusionCounts', 'OOCV confusion counts', emptyCols, emptyRows);
                tables.confusionRowPercent = NMResultsViewerTools.namedTable('ConfusionRowPercent', 'OOCV row-normalized confusion matrix [%]', emptyCols, emptyRows);
                tables.perClassMetrics = NMResultsViewerTools.namedTable('PerClassMetrics', 'OOCV per-class metrics', emptyCols, emptyRows);
                tables.misclassificationAxes = NMResultsViewerTools.namedTable('MisclassificationAxes', 'OOCV cobweb misclassification axes', emptyCols, emptyRows);
            end
            tables.oneVsRestAuc = NMResultsViewerTools.namedTable('OneVsRestAUC', 'One-vs-REST AUC', NMResultsViewerTools.tableColumnStruct({'message'}, {'Message'}), struct('message','Suppressed in true multi-class OOCV mode.'));
        end

        function rows = multiClassOOCVPerClassMetricRows(conf, groupNames)
            K = numel(groupNames);
            tmpl = struct('class','','support',NaN,'prevalencePercent',NaN,'sensitivityPercent',NaN,'specificityPercent',NaN, ...
                'ppvPercent',NaN,'npvPercent',NaN,'f1Percent',NaN,'balancedAccuracyPercent',NaN,'missingInOOCVData',false);
            rows = repmat(tmpl, 1, K+2);
            M = double(conf.matrix);
            % nm2-allow: multiClassOOCVConfusionPayload writer fixes the model group axis; disagreement is scientific axis corruption
            if ~isequal(size(M), [K K])
                error('NMResultsViewerTools:InvalidOOCVConfusionAxis', 'OOCV confusion matrix must be K-by-K on the model group axis.');
            end
            total = sum(M(:));
            rowSum = sum(M,2);
            colSum = sum(M,1)';
            diagVals = diag(M);
            for jj = 1:K
                TP = diagVals(jj);
                FN = rowSum(jj) - TP;
                FP = colSum(jj) - TP;
                TN = total - TP - FN - FP;
                rows(jj) = NMResultsViewerTools.multiClassMetricRow(tmpl, groupNames{jj}, TP, TN, FP, FN, rowSum(jj), total, rowSum(jj) == 0);
            end
            rows(K+1) = NMResultsViewerTools.multiClassMetricSummaryRow(tmpl, 'Macro mean', rows(1:K), total, false);
            TP = sum(diagVals);
            FN = sum(rowSum - diagVals);
            FP = sum(colSum - diagVals);
            TN = K * total - TP - FN - FP;
            rows(K+2) = NMResultsViewerTools.multiClassMetricRow(tmpl, 'Micro / pooled', TP, TN, FP, FN, total, total, false);
        end

        function row = multiClassMetricRow(tmpl, label, TP, TN, FP, FN, support, total, missing)
            sens = NMResultsViewerTools.percentRatio(TP, TP + FN);
            spec = NMResultsViewerTools.percentRatio(TN, TN + FP);
            ppv = NMResultsViewerTools.percentRatio(TP, TP + FP);
            npv = NMResultsViewerTools.percentRatio(TN, TN + FN);
            f1 = NMResultsViewerTools.percentRatio(2 * TP, 2 * TP + FP + FN);
            bal = NaN;
            if isfinite(sens) && isfinite(spec), bal = (sens + spec) / 2; end
            prev = NMResultsViewerTools.percentRatio(support, total);
            row = tmpl;
            row.class = label;
            row.support = double(support);
            row.prevalencePercent = double(prev);
            row.sensitivityPercent = double(sens);
            row.specificityPercent = double(spec);
            row.ppvPercent = double(ppv);
            row.npvPercent = double(npv);
            row.f1Percent = double(f1);
            row.balancedAccuracyPercent = double(bal);
            row.missingInOOCVData = logical(missing);
        end

        function row = multiClassMetricSummaryRow(tmpl, label, classRows, total, missing)
            row = tmpl;
            row.class = label;
            row.support = double(total);
            row.prevalencePercent = 100;
            row.sensitivityPercent = NMResultsViewerTools.meanFinite([classRows.sensitivityPercent]);
            row.specificityPercent = NMResultsViewerTools.meanFinite([classRows.specificityPercent]);
            row.ppvPercent = NMResultsViewerTools.meanFinite([classRows.ppvPercent]);
            row.npvPercent = NMResultsViewerTools.meanFinite([classRows.npvPercent]);
            row.f1Percent = NMResultsViewerTools.meanFinite([classRows.f1Percent]);
            row.balancedAccuracyPercent = NMResultsViewerTools.meanFinite([classRows.balancedAccuracyPercent]);
            row.missingInOOCVData = logical(missing);
        end

        function pct = percentRatio(num, den)
            if isfinite(num) && isfinite(den) && den > 0
                pct = double(num) ./ double(den) .* 100;
            else
                pct = NaN;
            end
        end

        function m = meanFinite(values)
            v = double(values(:));
            v = v(isfinite(v));
            if isempty(v), m = NaN; else, m = mean(v); end
        end


        function visuals = multiClassOOCVVisualPayloads(probabilities, expected, predicted, labelsKnown, cases, groupNames, colors, sourceType)
            N = numel(predicted);
            K = numel(groupNames);
            % nm2-allow: nk_MultiPerfComp writer fixes one probability column per model group and one row per selected case
            if ~isequal(size(probabilities), [N K])
                error('NMResultsViewerTools:InvalidMultiClassProbabilityAxis', 'Multi-class probability matrix must be N-by-K on the selected case and model group axes.');
            end
            visuals = struct();
            visuals.ok = true;
            visuals.kind = 'multiclass_summary';
            visuals.sourceType = sourceType;
            visuals.labelsKnown = logical(labelsKnown);
            visuals.groupNames = groupNames;
            visuals.colors = colors;
            visuals.distribution = NMResultsViewerTools.multiClassOOCVDistributionPayload(predicted, expected, labelsKnown, groupNames, colors, sourceType);
            visuals.confidence = NMResultsViewerTools.multiClassOOCVConfidencePayload(probabilities, predicted, expected, labelsKnown, cases, groupNames, colors, false, sourceType);
            visuals.margin = NMResultsViewerTools.multiClassOOCVConfidencePayload(probabilities, predicted, expected, labelsKnown, cases, groupNames, colors, true, sourceType);
            visuals.message = sprintf('Multi-class %s predicted-class distribution and confidence/margin summaries.', sourceType);
        end

        function dist = multiClassOOCVDistributionPayload(predicted, expected, labelsKnown, groupNames, colors, sourceType)
            K = numel(groupNames);
            N = numel(predicted);
            barTmpl = struct('classIndex',NaN,'className','','count',0,'percent',0,'correct',0,'error',0,'color','#2563eb');
            bars = repmat(barTmpl, 1, K);
            for jj = 1:K
                predMask = predicted == jj;
                count = sum(predMask);
                correct = 0;
                err = 0;
                if labelsKnown
                    correct = sum(predMask & expected == jj);
                    err = sum(predMask & expected ~= jj & isfinite(expected));
                end
                pct = 0;
                if N > 0, pct = 100 * count / N; end
                bars(jj) = struct('classIndex',double(jj),'className',groupNames{jj},'count',double(count),'percent',double(pct), ...
                    'correct',double(correct),'error',double(err),'color',colors{jj});
            end
            dist = struct('ok',true,'bars',bars,'labelsKnown',logical(labelsKnown),'xLabel','Predicted class','yLabel',sprintf('%s cases', sourceType), ...
                'sourceType',sourceType,'message',sprintf('Predicted-class distribution for the selected %s sample.', sourceType));
        end

        function conf = multiClassOOCVConfidencePayload(probabilities, predicted, expected, labelsKnown, cases, groupNames, colors, useMargin, sourceType)
            N = numel(predicted);
            K = numel(groupNames);
            pointTmpl = struct('x',NaN,'y',NaN,'caseIndex',NaN,'caseId','','predicted','','expected','','classIndex',NaN, ...
                'maxProbability',NaN,'secondProbability',NaN,'margin',NaN,'entropy',NaN,'error',false,'color','#2563eb','tooltip','');
            records = repmat(pointTmpl, 1, N);
            for ii = 1:N
                predIdx = round(double(predicted(ii)));
                if ~isfinite(predIdx) || predIdx < 1 || predIdx > K
                    error('NMResultsViewerTools:InvalidMultiClassPrediction', 'Multi-class prediction values must index the model group axis.');
                end
                probs = double(probabilities(ii,:));
                valid = isfinite(probs);
                sorted = sort(probs(valid), 'descend');
                top1 = NaN; top2 = NaN;
                if ~isempty(sorted), top1 = sorted(1); end
                if numel(sorted) >= 2, top2 = sorted(2); end
                margin = top1 - top2;
                entropy = NMResultsViewerTools.normalizedEntropy(probs);
                y = top1;
                if useMargin, y = margin; end
                isErr = false;
                expectedName = '';
                if labelsKnown
                    expIdx = round(double(expected(ii)));
                    if ~isfinite(expIdx) || expIdx < 1 || expIdx > K
                        error('NMResultsViewerTools:InvalidMultiClassLabel', 'Known multi-class labels must index the model group axis.');
                    end
                    isErr = predIdx ~= expIdx;
                    expectedName = groupNames{expIdx};
                end
                tip = sprintf('Case: %s\nPredicted: %s\nMax probability: %1.3f\nMargin: %1.3f\nEntropy: %1.3f', cases{ii}, groupNames{predIdx}, top1, margin, entropy);
                if labelsKnown, tip = sprintf('%s\nExpected: %s\nError: %d', tip, expectedName, isErr); end
                records(ii) = struct('x',NaN,'y',double(y),'caseIndex',double(ii),'caseId',cases{ii},'predicted',groupNames{predIdx},'expected',expectedName, ...
                    'classIndex',double(predIdx),'maxProbability',double(top1),'secondProbability',double(top2),'margin',double(margin),'entropy',double(entropy), ...
                    'error',logical(isErr),'color',colors{predIdx},'tooltip',tip);
            end
            keys = zeros(N,3);
            for ii = 1:N
                keys(ii,1) = round(double(predicted(ii)));
                if useMargin, keys(ii,2) = -records(ii).margin; else, keys(ii,2) = -records(ii).maxProbability; end
                keys(ii,3) = ii;
            end
            if N > 0
                [~,ord] = sortrows(keys, [1 2 3]);
                records = records(ord);
                for ii = 1:N, records(ii).x = double(ii); end
            end
            yLabel = 'Max class probability';
            msg = sprintf('%s case confidence sorted by predicted class and confidence.', sourceType);
            if useMargin
                yLabel = 'Probability margin';
                msg = sprintf('%s top-1 minus top-2 probability margin sorted by predicted class and margin.', sourceType);
            end
            conf = struct('ok',any(isfinite([records.y])),'points',records,'labelsKnown',logical(labelsKnown),'groupNames',{groupNames},'colors',{colors}, ...
                'sourceType',sourceType,'xLim',[1 max(1,N)],'yLim',[0 1],'xLabel',sprintf('%s cases sorted by predicted class', sourceType),'yLabel',yLabel,'message',msg);
        end

        function names = multiClassGroupNames(handles, K)
            names = handles.NM.groupnames(:)';
            % nm2-allow: load_GDdims uses the analysis-projected NM.groupnames as the fixed multiclass model axis
            if numel(names) ~= K
                error('NMResultsViewerTools:InvalidMultiClassGroupAxis', 'Multi-class group-name count must match the transformed model group axis.');
            end
        end

        function colors = multiClassColors(handles, K)
            C = double(handles.colptin);
            colors = cell(1,K);
            for ii = 1:K
                colors{ii} = NMResultsViewerTools.rgbHex(C(mod(ii-1,size(C,1))+1,:));
            end
        end

        function cases = legacyCaseTextColumn(rawCases, n)
            cases = rawCases(:);
            % nm2-allow: load_GDdims/load_OOCV writers align transformed case IDs exactly to the result case axis
            if numel(cases) ~= n
                error('NMResultsViewerTools:InvalidTransformedCaseAxis', 'Transformed case identifiers must match the result case axis.');
            end
        end

        function plot = multiClassPlotPayload(probabilities, labels, predicted, errors, cases, groupNames, colors, selectedClass, xValues, caseIndices, xLabel, alternativeXAxis)
            [N,K] = size(probabilities);
            xValues = double(xValues(:));
            caseIndices = double(caseIndices(:));
            % nm2-allow: load_GDdims and the public plot-vector projector define one shared selected-case axis
            if numel(xValues) ~= N || numel(caseIndices) ~= N || numel(labels) ~= N || numel(predicted) ~= N || numel(errors) ~= N || numel(cases) ~= N
                error('NMResultsViewerTools:InvalidMultiClassPlotVectorLength', ...
                    'Multi-class plot vectors must share the transformed selected-case axis.');
            end
            pointTmpl = struct('x',NaN,'y',NaN,'caseIndex',NaN,'classIndex',NaN,'className','','probability',NaN, ...
                'caseId','','expected','','predicted','','error',false,'isPredicted',false,'marker','circle','color','#2563eb','dimmed',false,'tooltip','');
            probPoints = repmat(pointTmpl, 1, N*K);
            predPoints = repmat(pointTmpl, 1, N);
            nProb = 0;
            for ii = 1:N
                expIdx = round(double(labels(ii)));
                predIdx = round(double(predicted(ii)));
                if ~isfinite(expIdx) || expIdx < 1 || expIdx > K || ~isfinite(predIdx) || predIdx < 1 || predIdx > K
                    error('NMResultsViewerTools:InvalidMultiClassCaseLabel', 'Transformed expected/predicted labels must index the model group axis.');
                end
                expected = groupNames{expIdx};
                predictedName = groupNames{predIdx};
                baseTip = sprintf('Subject ID: %s\nExpected group: %s\nPredicted Group: %s', cases{ii}, expected, predictedName);
                for jj = 1:K
                    baseTip = sprintf('%s\nProbability %s: %1.2f', baseTip, groupNames{jj}, probabilities(ii,jj));
                end
                for jj = 1:K
                    nProb = nProb + 1;
                    dimmed = selectedClass >= 1 && jj ~= selectedClass;
                    if dimmed, col = '#9ca3af'; else, col = colors{jj}; end
                    probPoints(nProb) = struct('x',double(xValues(ii)),'y',double(probabilities(ii,jj)), ...
                        'caseIndex',double(caseIndices(ii)),'classIndex',double(jj),'className',groupNames{jj},'probability',double(probabilities(ii,jj)), ...
                        'caseId',cases{ii},'expected',expected,'predicted',predictedName,'error',logical(errors(ii)), ...
                        'isPredicted',false,'marker','small','color',col,'dimmed',logical(dimmed),'tooltip',baseTip);
                end
                dimmedPred = selectedClass >= 1 && predIdx ~= selectedClass;
                if dimmedPred, predCol = '#9ca3af'; else, predCol = colors{predIdx}; end
                marker = 'circle'; if errors(ii), marker = 'x'; end
                predPoints(ii) = struct('x',double(xValues(ii)),'y',double(probabilities(ii,predIdx)), ...
                    'caseIndex',double(caseIndices(ii)),'classIndex',double(predIdx),'className',groupNames{predIdx},'probability',double(probabilities(ii,predIdx)), ...
                    'caseId',cases{ii},'expected',expected,'predicted',predictedName,'error',logical(errors(ii)), ...
                    'isPredicted',true,'marker',marker,'color',predCol,'dimmed',logical(dimmedPred),'tooltip',baseTip);
            end
            if alternativeXAxis
                patches = NMResultsViewerTools.multiClassBackgroundPatches([], groupNames, colors, selectedClass);
                finiteX = xValues(isfinite(xValues));
                if isempty(finiteX)
                    xLim = [0 1];
                else
                    [xLim, ~] = NMResultsViewerTools.legacyLimits(finiteX, zeros(size(finiteX)));
                end
            else
                patches = NMResultsViewerTools.multiClassBackgroundPatches(labels, groupNames, colors, selectedClass);
                xLim = [1 max(1,N)];
            end
            plot = struct('ok',true,'points',probPoints,'predictedPoints',predPoints,'backgroundPatches',patches, ...
                'groupNames',{groupNames},'colors',{colors},'selectedClassIndex',double(selectedClass), ...
                'xLim',double(xLim),'yLim',[0 1],'zeroLine',0.5,'xLabel',xLabel,'yLabel','Multi-class probabilities', ...
                'alternativeXAxis',logical(alternativeXAxis), ...
                'message','Multi-class probability plot payload from the fixed load_GDdims transformed schema.');
        end

        function patches = multiClassBackgroundPatches(labels, groupNames, colors, selectedClass)
            K = numel(groupNames); N = numel(labels);
            tmpl = struct('x',NaN,'y',0,'w',NaN,'h',1,'color','#94a3b8','alpha',0.10,'label','');
            patches = repmat(tmpl, 1, 0);
            if N < 1, return; end
            startIdx = 1; cur = labels(1);
            for ii = 2:(N+1)
                if ii > N || labels(ii) ~= cur
                    g = round(double(cur));
                    if ~isfinite(g) || g < 1 || g > K
                        error('NMResultsViewerTools:InvalidMultiClassLabel', 'Transformed multi-class labels must index the model group axis.');
                    end
                    if selectedClass >= 1 && g ~= selectedClass
                        patchColor = '#e5e7eb';
                        patchAlpha = 0.38;
                        patchLabel = 'REST';
                    else
                        patchColor = colors{g};
                        patchAlpha = 0.10;
                        patchLabel = groupNames{g};
                    end
                    patches(end+1) = struct('x',double(startIdx),'y',0,'w',double(ii-startIdx),'h',1, ...
                        'color',patchColor,'alpha',patchAlpha,'label',patchLabel); %#ok<AGROW>
                    if ii <= N, startIdx = ii; cur = labels(ii); end
                end
            end
        end

        function roc = multiClassRocPayload(MC, groupNames, colors, selectedClass)
            K = numel(groupNames);
            curveTmpl = struct('ok',false,'label','','color','#2563eb','auc',NaN,'points',[],'message','');
            if selectedClass >= 1, classList = selectedClass; else, classList = 1:K; end
            curves = repmat(curveTmpl, 1, numel(classList));
            for ii = 1:numel(classList)
                jj = classList(ii);
                c = NMResultsViewerTools.multiClassContingencyForClass(MC, jj);
                curves(ii) = NMResultsViewerTools.singleRocCurvePayload(MC.X{jj}, MC.Y{jj}, c.AUC, sprintf('%s vs REST', groupNames{jj}), colors{jj});
            end
            roc = struct('ok',false,'points',[],'auc',NaN,'curves',curves,'multi',true, ...
                'trainingCurve',struct('ok',false,'points',[],'auc',NaN,'label','Discovery/CV ROC','color','#8a8a8a'), ...
                'message','No one-vs-rest ROC curve available.');
            okVec = [curves.ok];
            roc.ok = any(okVec);
            if selectedClass >= 1 && roc.ok
                firstOk = find(okVec,1,'first');
                roc.points = curves(firstOk).points;
                roc.auc = curves(firstOk).auc;
                roc.color = curves(firstOk).color;
                roc.label = curves(firstOk).label;
                roc.selectedClassIndex = double(selectedClass);
                roc.multi = false;
                roc.message = '';
            elseif roc.ok
                roc.message = 'All one-vs-rest ROC curves extracted from the fixed transformed MultiClass.X/Y schema.';
            end
        end

        function curve = singleRocCurvePayload(x, y, auc, label, color)
            pointTmpl = struct('fpr',0,'tpr',0);
            pts = repmat(pointTmpl, 1, 0);
            n = min(numel(x), numel(y));
            if n > 0
                pts = repmat(pointTmpl, 1, n);
                for ii = 1:n, pts(ii) = struct('fpr',double(x(ii)),'tpr',double(y(ii))); end
            end
            curve = struct('ok',n > 0,'label',label,'color',color,'auc',double(auc),'points',pts,'message','');
            if n < 1, curve.message = 'ROC curve has no finite points.'; end
        end

        function c = multiClassContingencyForClass(MC, classIdx)
            c = MC.class{classIdx};
        end

        function conf = multiClassConfusionPayload(MC, labels, predicted, groupNames, selectedClass) %#ok<INUSD>
            K = numel(groupNames);
            if selectedClass >= 1
                c = NMResultsViewerTools.multiClassContingencyForClass(MC, selectedClass);
                conf = NMResultsViewerTools.confusionPayloadFromContingency(c, {groupNames{selectedClass}, 'REST'});
                return;
            end
            M = double(MC.confusion_matrix);
            % nm2-allow: nk_MultiEvalPerf writer fixes confusion_matrix on the analysis model group axis
            if ~isequal(size(M), [K K])
                error('NMResultsViewerTools:InvalidMultiClassConfusionAxis', 'Transformed multi-class confusion matrix must be K-by-K.');
            end
            rowSum = sum(M,2); P = zeros(size(M));
            for rr = 1:K
                if rowSum(rr) > 0, P(rr,:) = M(rr,:) ./ rowSum(rr) * 100; end
            end
            conf = struct('ok',true,'matrix',M,'percentMatrix',P,'labels',{groupNames},'message','Multi-class confusion matrix from the fixed load_GDdims transformed schema.');
        end

        function cob = multiClassCobwebPayload(conf, groupNames, selectedClass)
            cob = struct('ok',false,'axes',[],'series',[],'tmr',NaN,'message','Cobweb/misclassification web is available only in multi-group mode.');
            if selectedClass >= 1, return; end
            if ~conf.ok
                cob.message = 'Multi-class confusion matrix is unavailable; cobweb cannot be generated.';
                return;
            end
            M = double(conf.matrix);
            K = numel(groupNames);
            if K < 3
                cob.message = 'Cobweb/spider display requires at least three classes.';
                return;
            end
            % nm2-allow: multiClassConfusionPayload fixes a square matrix on the exact model group axis
            if ~isequal(size(M), [K K])
                error('NMResultsViewerTools:InvalidCobwebGroupAxis', 'Cobweb confusion matrix must be K-by-K on the model group axis.');
            end
            rowSums = sum(M,2);
            axesTmpl = struct('index',0,'fromIndex',0,'toIndex',0,'from','','to','','label','','model',0,'random',0, ...
                'missingSource',false,'missingTarget',false,'missingInData',false);
            axes = repmat(axesTmpl, 1, K*(K-1));
            pos = 0;
            for rr = 1:K
                for cc = 1:K
                    if rr == cc, continue; end
                    pos = pos + 1;
                    if rowSums(rr) > 0, modelPct = M(rr,cc) ./ rowSums(rr) * 100; else, modelPct = 0; end
                    randPct = 100 ./ K;
                    missingSource = rowSums(rr) == 0;
                    missingTarget = rowSums(cc) == 0;
                    axes(pos) = struct('index',double(pos),'fromIndex',double(rr),'toIndex',double(cc), ...
                        'from',groupNames{rr},'to',groupNames{cc}, ...
                        'label',sprintf('%s → %s', groupNames{rr}, groupNames{cc}), ...
                        'model',double(modelPct),'random',double(randPct), ...
                        'missingSource',logical(missingSource),'missingTarget',logical(missingTarget),'missingInData',logical(missingSource || missingTarget));
                end
            end
            modelSum = sum([axes.model]) / 100;
            randomSum = sum([axes.random]) / 100;
            tmr = NaN;
            if randomSum > 0, tmr = (1 - (modelSum ./ randomSum)) * 100; end
            series = struct('random',[axes.random], 'model',[axes.model], 'randomLabel','Random baseline', 'modelLabel','Model');
            missingAxis = [axes.missingInData];
            cob = struct('ok',true,'axes',axes,'series',series,'tmr',double(tmr), ...
                'missingAxis',logical(missingAxis),'missingLegendLabel','Missing in data', ...
                'message','Cobweb payload generated from the canonical multi-class confusion matrix.');
        end

        function cob = attachMultiClassCVReferenceCobweb(cob, handles, groupNames)
            if ~cob.ok, return; end
            MC = handles.MultiClass;
            conf = NMResultsViewerTools.multiClassConfusionPayload(MC, double(MC.labels(:)), double(MC.multi_predictionsCV2(:)), groupNames, 0);
            refCob = NMResultsViewerTools.multiClassCobwebPayload(conf, groupNames, 0);
            ref = struct('ok',refCob.ok,'values',double(refCob.series.model),'tmr',double(refCob.tmr), ...
                'label','CV reference','message','Faint CV reference cobweb generated from the transformed CV multi-class confusion payload.');
            cob.referenceSeries = ref;
        end

        function M = multiClassConfusionFromLabels(labels, predicted, K)
            labels = double(labels(:));
            predicted = double(predicted(:));
            % nm2-allow: selected expected/predicted vectors must remain on one exact transformed case axis
            if numel(labels) ~= numel(predicted)
                error('NMResultsViewerTools:InvalidMultiClassCaseAxis', 'Expected and predicted multi-class vectors must have equal length.');
            end
            valid = isfinite(labels) & isfinite(predicted);
            if any(labels(valid) ~= round(labels(valid)) | labels(valid) < 1 | labels(valid) > K | ...
                    predicted(valid) ~= round(predicted(valid)) | predicted(valid) < 1 | predicted(valid) > K)
                error('NMResultsViewerTools:InvalidMultiClassGroupIndex', 'Finite expected/predicted values must index the model group axis.');
            end
            M = zeros(K,K);
            idx = find(valid);
            for ii = 1:numel(idx)
                r = labels(idx(ii)); c = predicted(idx(ii));
                M(r,c) = M(r,c) + 1;
            end
        end

        function rows = multiClassSummaryRows(MC, labels, predicted, groupNames, selectedClass, conf, cobweb)
            tmpl = struct('metric','','value','','source','display_multiclassplot');
            rows = repmat(tmpl, 1, 0);
            K = numel(groupNames);
            if selectedClass >= 1
                c = NMResultsViewerTools.multiClassContingencyForClass(MC, selectedClass);
                rows = NMResultsViewerTools.metricRowsFromContingency(c, false, struct());
                return;
            end
            % nm2-allow: load_GDdims writes expected and predicted vectors on the same selected-case axis
            if numel(labels) ~= numel(predicted)
                error('NMResultsViewerTools:InvalidMultiClassCaseAxis', 'Expected and predicted multi-class vectors must have equal length.');
            end
            valid = isfinite(labels) & isfinite(predicted);
            acc = NaN;
            if any(valid), acc = sum(labels(valid) == predicted(valid)) / sum(valid) * 100; end
            M = double(conf.matrix);
            rs = sum(M,2);
            rec = NaN(size(rs));
            for rr = 1:numel(rs)
                if rs(rr) > 0, rec(rr) = M(rr,rr) ./ rs(rr) * 100; end
            end
            meanRecall = mean(rec(isfinite(rec)));
            aucRows = NMResultsViewerTools.multiClassAucRows(MC, groupNames);
            aucVals = [aucRows.auc];
            meanAuc = mean(aucVals(isfinite(aucVals)));
            tmr = double(cobweb.tmr);
            rows(end+1) = struct('metric','Cases:', 'value',sprintf('%d', sum(valid)), 'source','display_multiclassplot'); %#ok<AGROW>
            rows(end+1) = struct('metric','Groups:', 'value',sprintf('%d', K), 'source','display_multiclassplot'); %#ok<AGROW>
            rows(end+1) = struct('metric','Multi-class accuracy [%]:', 'value',sprintf('%.1f', acc), 'source','display_multiclassplot'); %#ok<AGROW>
            rows(end+1) = struct('metric','Mean class recall [%]:', 'value',sprintf('%.1f', meanRecall), 'source','multi-class confusion matrix'); %#ok<AGROW>
            rows(end+1) = struct('metric','Mean one-vs-REST AUC:', 'value',sprintf('%.3f', meanAuc), 'source','display_roc/multiclass'); %#ok<AGROW>
            rows(end+1) = struct('metric','TMR [%]:', 'value',sprintf('%.1f', tmr), 'source','nk_MultiClassRatio2Random semantics'); %#ok<AGROW>
        end

        function [rows, columns] = multiClassScoreRows(probabilities, labels, predicted, errors, cases, groupNames, selectedClass)
            [N,K] = size(probabilities);
            labels = double(labels(:));
            predicted = double(predicted(:));
            % nm2-allow: load_GDdims fixes finite expected/predicted class indices on the transformed CV case axis
            if numel(labels) ~= N || numel(predicted) ~= N || any(~isfinite(labels) | labels ~= fix(labels) | labels < 1 | labels > K) || ...
                    any(~isfinite(predicted) | predicted ~= fix(predicted) | predicted < 1 | predicted > K)
                error('NMResultsViewerTools:InvalidMultiClassScoreAxis', ...
                    'CV multi-class score rows require finite expected/predicted indices on the model group axis.');
            end
            baseKeys = {'case','expected','predicted','correct','error','score','observedClassProbability','decisionMargin'};
            baseLabels = {'Case','Observed class','Predicted class','Correct','Error','Predicted-class probability','Observed-class probability','Decision margin'};
            keys = baseKeys; labelsOut = baseLabels;
            if selectedClass >= 1
                keys = [keys {'selectedClass','selectedClassScore','oneVsRestObserved','oneVsRestPredicted','oneVsRestScore','oneVsRestError'}];
                labelsOut = [labelsOut {'Selected class','Selected-class probability','One-vs-REST observed','One-vs-REST predicted','One-vs-REST score','One-vs-REST error'}];
            end
            for jj = 1:K
                keys{end+1} = sprintf('p%03d', jj); %#ok<AGROW>
                labelsOut{end+1} = sprintf('P(%s)', groupNames{jj}); %#ok<AGROW>
            end
            columns = NMResultsViewerTools.tableColumnStruct(keys, labelsOut);
            tmpl = struct();
            for jj = 1:numel(keys), tmpl.(keys{jj}) = ''; end
            for jj = 1:K, tmpl.(sprintf('p%03d', jj)) = NaN; end
            rows = repmat(tmpl, 1, N);
            for ii = 1:N
                expIdx = labels(ii);
                predIdx = predicted(ii);
                probs = double(probabilities(ii,:));
                sorted = sort(probs(isfinite(probs)), 'descend');
                if isempty(sorted), top1 = NaN; else, top1 = sorted(1); end
                if numel(sorted) < 2, top2 = NaN; else, top2 = sorted(2); end
                rows(ii).case = cases{ii};
                rows(ii).expected = groupNames{expIdx};
                rows(ii).predicted = groupNames{predIdx};
                rows(ii).correct = logical(predIdx == expIdx);
                rows(ii).error = logical(errors(ii));
                rows(ii).score = double(probabilities(ii,predIdx));
                rows(ii).observedClassProbability = double(probabilities(ii,expIdx));
                rows(ii).decisionMargin = double(top1 - top2);
                if selectedClass >= 1
                    rows(ii).selectedClass = groupNames{selectedClass};
                    rows(ii).selectedClassScore = double(probabilities(ii,selectedClass));
                    if expIdx == selectedClass, rows(ii).oneVsRestObserved = groupNames{selectedClass}; else, rows(ii).oneVsRestObserved = 'REST'; end
                    if predIdx == selectedClass, rows(ii).oneVsRestPredicted = groupNames{selectedClass}; else, rows(ii).oneVsRestPredicted = 'REST'; end
                    rows(ii).oneVsRestScore = double(probabilities(ii,selectedClass));
                    rows(ii).oneVsRestError = ~strcmp(rows(ii).oneVsRestObserved, rows(ii).oneVsRestPredicted);
                end
                for jj = 1:K
                    rows(ii).(sprintf('p%03d', jj)) = double(probabilities(ii,jj));
                end
            end
        end

        function columns = tableColumnStruct(keys, labels)
            tmpl = struct('key','','label','');
            columns = repmat(tmpl, 1, numel(keys));
            for ii = 1:numel(keys)
                columns(ii) = struct('key',keys{ii},'label',labels{ii});
            end
        end

        function tables = multiClassTablePayloads(MC, probabilities, labels, predicted, errors, cases, groupNames, selectedClass, conf, cobweb, summaryRows, scoreRows, scoreColumns) %#ok<INUSD>
            tables = struct();
            metricCols = NMResultsViewerTools.tableColumnStruct({'metric','value'}, {'Metric','Value'});
            tables.summary = NMResultsViewerTools.namedTable('Summary', 'Multi-class summary', metricCols, summaryRows);
            tables.caseScores = NMResultsViewerTools.namedTable('CaseScores', 'Case-level multi-class probabilities', scoreColumns, scoreRows);
            aucRows = NMResultsViewerTools.multiClassAucRows(MC, groupNames);
            if selectedClass >= 1, aucRows = aucRows(selectedClass); end
            aucCols = NMResultsViewerTools.tableColumnStruct({'class','auc','nClass','nRest'}, {'Class','AUC','n class','n REST'});
            tables.oneVsRestAuc = NMResultsViewerTools.namedTable('OneVsRestAUC', 'One-vs-REST AUC', aucCols, aucRows);
            if selectedClass >= 1
                tableNames = {groupNames{selectedClass}, 'REST'};
                [cntRows,cntCols] = NMResultsViewerTools.multiClassConfusionTableRows(conf, tableNames, false);
                tables.confusionCounts = NMResultsViewerTools.namedTable('ConfusionCounts', 'Class-vs-REST observed-by-predicted confusion counts', cntCols, cntRows);
                [pctRows,pctCols] = NMResultsViewerTools.multiClassConfusionTableRows(conf, tableNames, true);
                tables.confusionRowPercent = NMResultsViewerTools.namedTable('ConfusionRowPercent', 'Class-vs-REST row-normalized confusion matrix [%]', pctCols, pctRows);
                msgCols = NMResultsViewerTools.tableColumnStruct({'message'}, {'Message'});
                tables.misclassificationAxes = NMResultsViewerTools.namedTable('MisclassificationAxes', 'Cobweb misclassification axes', msgCols, ...
                    struct('message','Cobweb misclassification axes apply only to aggregate K-class mode.'));
            else
                [cntRows,cntCols] = NMResultsViewerTools.multiClassConfusionTableRows(conf, groupNames, false);
                tables.confusionCounts = NMResultsViewerTools.namedTable('ConfusionCounts', 'Observed-by-predicted confusion counts', cntCols, cntRows);
                [pctRows,pctCols] = NMResultsViewerTools.multiClassConfusionTableRows(conf, groupNames, true);
                tables.confusionRowPercent = NMResultsViewerTools.namedTable('ConfusionRowPercent', 'Row-normalized confusion matrix [%]', pctCols, pctRows);
                axRows = NMResultsViewerTools.multiClassMisclassificationAxisRows(conf, groupNames);
                axCols = NMResultsViewerTools.tableColumnStruct({'axis','sourceClass','targetClass','count','sourceTotal','misclassificationLikelihoodPercent','randomBaselinePercent','excessVsRandomPercent'}, ...
                    {'Axis','Source class','Target class','Count','Source-class total','Misclassification likelihood [%]','Random baseline [%]','Excess vs random [%]'});
                tables.misclassificationAxes = NMResultsViewerTools.namedTable('MisclassificationAxes', 'Cobweb misclassification axes', axCols, axRows);
            end
        end

        function T = namedTable(sheetName, title, columns, rows)
            T = struct('sheetName',sheetName,'title',title,'columns',columns,'rows',rows);
        end

        function rows = multiClassAucRows(MC, groupNames)
            K = numel(groupNames);
            tmpl = struct('class','','auc',NaN,'nClass',NaN,'nRest',NaN);
            rows = repmat(tmpl, 1, K);
            for jj = 1:K
                c = NMResultsViewerTools.multiClassContingencyForClass(MC, jj);
                lab = double(MC.onevsall_labels(:,jj));
                rows(jj) = struct('class',groupNames{jj},'auc',double(c.AUC), ...
                    'nClass',double(sum(lab == 1)),'nRest',double(sum(lab ~= 1 & isfinite(lab))));
            end
        end

        function [rows, columns] = multiClassConfusionTableRows(conf, groupNames, asPercent)
            K = numel(groupNames);
            keys = [{'observedClass'} arrayfun(@(jj)sprintf('pred%03d', jj), 1:K, 'UniformOutput', false)];
            labels = [{'Observed class'} arrayfun(@(jj)sprintf('Pred %s', groupNames{jj}), 1:K, 'UniformOutput', false)];
            columns = NMResultsViewerTools.tableColumnStruct(keys, labels);
            tmpl = struct();
            for ii = 1:numel(keys), tmpl.(keys{ii}) = ''; end
            rows = repmat(tmpl, 1, K);
            M = double(conf.matrix);
            P = double(conf.percentMatrix);
            % nm2-allow: multiClassConfusionPayload fixes both table matrices on the exact model group axis
            if ~isequal(size(M), [K K]) || ~isequal(size(P), [K K])
                error('NMResultsViewerTools:InvalidMultiClassTableAxis', 'Confusion count/percent matrices must both be K-by-K.');
            end
            for rr = 1:K
                rows(rr).observedClass = groupNames{rr};
                for cc = 1:K
                    key = sprintf('pred%03d', cc);
                    if asPercent, rows(rr).(key) = double(P(rr,cc)); else, rows(rr).(key) = double(M(rr,cc)); end
                end
            end
        end

        function rows = multiClassMisclassificationAxisRows(conf, groupNames)
            K = numel(groupNames);
            tmpl = struct('axis','','sourceClass','','targetClass','','count',NaN,'sourceTotal',NaN, ...
                'misclassificationLikelihoodPercent',NaN,'randomBaselinePercent',NaN,'excessVsRandomPercent',NaN);
            rows = repmat(tmpl, 1, 0);
            M = double(conf.matrix);
            % nm2-allow: multiClassConfusionPayload fixes the misclassification matrix on the exact model group axis
            if ~isequal(size(M), [K K])
                error('NMResultsViewerTools:InvalidMultiClassMisclassificationAxis', 'Misclassification matrix must be K-by-K.');
            end
            rowSums = sum(M,2);
            randomPct = 100 ./ K;
            for rr = 1:K
                for cc = 1:K
                    if rr == cc, continue; end
                    if rowSums(rr) > 0, pct = M(rr,cc) ./ rowSums(rr) * 100; else, pct = 0; end
                    rows(end+1) = struct('axis',sprintf('%s → %s', groupNames{rr}, groupNames{cc}), ...
                        'sourceClass',groupNames{rr},'targetClass',groupNames{cc},'count',double(M(rr,cc)), ...
                        'sourceTotal',double(rowSums(rr)),'misclassificationLikelihoodPercent',double(pct), ...
                        'randomBaselinePercent',double(randomPct),'excessVsRandomPercent',double(pct-randomPct)); %#ok<AGROW>
                end
            end
            if numel(rows) > 1
                vals = [rows.misclassificationLikelihoodPercent];
                [~,ord] = sort(vals, 'descend');
                rows = rows(ord);
            end
        end

        function rows = regressionContinuousMetricRows(R, targetIdx)
            rows = repmat(struct('metric','','value','','source','display_contigmat/regression'), 1, 0);
            rows = NMResultsViewerTools.appendMetric(rows, 'R² [%]:', '%.1f', R, {'R2'}, targetIdx);
            rows = NMResultsViewerTools.appendRegressionRMetric(rows, R, targetIdx);
            rows = NMResultsViewerTools.appendRegressionPTMetric(rows, R, targetIdx);
            rows = NMResultsViewerTools.appendMetric(rows, 'MAE:', '%.1f', R, {'MAE'}, targetIdx);
            rows = NMResultsViewerTools.appendMetric(rows, 'MSE:', '%.1f', R, {'MSE'}, targetIdx);
            rows = NMResultsViewerTools.appendMetric(rows, 'NRMSD [%]:', '%.1f', R, {'NRSMD'}, targetIdx);
        end

        function rows = appendRegressionRMetric(rows, R, targetIdx)
            fields = {'r','r_95CI_low','r_95CI_up'};
            if ~NMResultsViewerTools.hasAllFields(R, fields), return; end
            vals = NMResultsViewerTools.scalarFieldsAt(R, fields, targetIdx);
            rows(end+1) = struct('metric','r (95%-CI):','value',sprintf('%.2f (%.2f-%.2f)', vals(1), vals(2), vals(3)), 'source','display_contigmat/regression'); %#ok<AGROW>
        end

        function rows = appendRegressionPTMetric(rows, R, targetIdx)
            fields = {'p','t'};
            if ~NMResultsViewerTools.hasAllFields(R, fields), return; end
            vals = NMResultsViewerTools.scalarFieldsAt(R, fields, targetIdx);
            rows(end+1) = struct('metric','P(T) value:','value',sprintf('%.3f (%.2f)', vals(1), vals(2)), 'source','display_contigmat/regression'); %#ok<AGROW>
        end

        function rows = appendRegressionNoticeRow(rows, note)
            rows(end+1) = struct('metric','Regression-to-binary:', 'value', char(string(note)), 'source','display_regrplot'); %#ok<AGROW>
        end

        function rows = regressionScoreRows(cases, label, pred, sd, ci1, ci2, bLabel, bPred)
            n = numel(pred);
            tmpl = struct('case','','observed',NaN,'predicted',NaN,'error','', ...
                'score',NaN,'stdScore',NaN,'ciLow',NaN,'ciHigh',NaN, ...
                'binaryObserved',NaN,'binaryScore',NaN,'binaryPredicted','');
            rows = repmat(tmpl, 1, n);
            for i = 1:n
                binPred = 'n/a';
                if isfinite(bPred(i))
                    if bPred(i) >= 0
                        binPred = 'Group 1';
                    else
                        binPred = 'Group 2';
                    end
                end
                err = isfinite(bLabel(i)) && isfinite(bPred(i)) && sign(bPred(i)) ~= bLabel(i);
                rows(i) = struct('case',cases{i}, 'observed',double(label(i)), 'predicted',double(pred(i)), ...
                    'error',char(string(err)), 'score',double(pred(i)), 'stdScore',double(sd(i)), ...
                    'ciLow',double(ci1(i)), 'ciHigh',double(ci2(i)), ...
                    'binaryObserved',double(bLabel(i)), 'binaryScore',double(bPred(i)), 'binaryPredicted',binPred);
            end
        end

        function out = regressionErrorBarsPayload(x, pred, sd, ci1, ci2, graphType)
            out = struct('ok',false,'mode','none','kind','','bars',[],'band',[]);
            n = numel(pred);
            if graphType == 2
                lo = ci1(:); hi = ci2(:); kind = '95%-CI';
            elseif graphType == 3
                lo = pred(:) - sd(:); hi = pred(:) + sd(:); kind = 'SD';
            else
                return;
            end
            good = isfinite(x(:)) & isfinite(pred(:)) & isfinite(lo(:)) & isfinite(hi(:));
            if ~any(good), return; end
            ix = find(good);
            bars = repmat(struct('x',NaN,'y',NaN,'lower',NaN,'upper',NaN), 1, numel(ix));
            for k = 1:numel(ix)
                i = ix(k);
                bars(k) = struct('x',double(x(i)),'y',double(pred(i)), ...
                    'lower',max(0,double(pred(i)-lo(i))), 'upper',max(0,double(hi(i)-pred(i))));
            end
            out.ok = true; out.mode = 'bars'; out.kind = kind; out.bars = bars;
            if n == 0, out.ok = false; end
        end

        function fit = regressionFitPayload(x, pred)
            fit = struct('ok',false,'line',[],'band',[],'message','Linear fit unavailable.');
            good = isfinite(x(:)) & isfinite(pred(:));
            xv = double(x(good)); yv = double(pred(good));
            if numel(xv) < 2 || numel(unique(xv)) < 2
                fit.message = 'Linear fit requires at least two distinct x values.';
                return;
            end
            try
                p = polyfit(xv, yv, 1);
                xLine = linspace(min(xv), max(xv), max(2, min(200, numel(xv)*3)))';
                yLine = polyval(p, xLine);
                line = repmat(struct('x',NaN,'y',NaN), 1, numel(xLine));
                for i = 1:numel(xLine), line(i) = struct('x',double(xLine(i)),'y',double(yLine(i))); end
                fit.ok = true; fit.line = line; fit.message = '';
                if exist('polyconf','file') == 2
                    try
                        [~,S] = polyfit(xv, yv, 1);
                        [yhat,dy] = polyconf(p, xLine, S, 'predopt', 'curve');
                        band = repmat(struct('x',NaN,'lower',NaN,'upper',NaN), 1, numel(xLine));
                        for i = 1:numel(xLine)
                            band(i) = struct('x',double(xLine(i)),'lower',double(yhat(i)-dy(i)),'upper',double(yhat(i)+dy(i)));
                        end
                        fit.band = band;
                    catch
                        fit.band = [];
                    end
                end
            catch ME
                fit.message = ['Linear fit failed: ' ME.message];
            end
        end

        function out = regressionThresholdPayload(threshold, source, xLim, yLim, pred)
            out = struct('ok',isfinite(threshold),'value',double(threshold),'source',source, ...
                'message','','xLim',double(xLim),'yLim',double(yLim),'minPred',NaN,'maxPred',NaN);
            pv = pred(isfinite(pred));
            if ~isempty(pv), out.minPred = double(min(pv)); out.maxPred = double(max(pv)); end
            if ~isfinite(threshold)
                out.message = 'No finite binarization threshold could be computed.';
                return;
            end
            out.message = sprintf('Regression-to-binary threshold %.4g (%s).', threshold, source);
            if isfinite(out.minPred) && (threshold < out.minPred || threshold > out.maxPred)
                out.message = sprintf('%s Threshold is outside the predicted-target range [%g, %g].', out.message, out.minPred, out.maxPred);
            end
        end

        function lab = regressionGraphTypeLabel(graphType)
            switch max(1, min(3, round(double(graphType))))
                case 2, lab = 'Mean target predictions (95%-CIs)';
                case 3, lab = 'Mean target predictions (SD)';
                otherwise, lab = 'Mean target predictions';
            end
        end

        function [predh, info, contingency] = legacyPredictionVector(handles, h, graphType)
            B = handles.BinClass{h};
            info = struct('percentRank',false,'probTransform',false,'decisionLineValue',0, ...
                'zeroLineY',0,'errorKind','none','hasError',false,'errorMode','none', ...
                'errorLower',[],'errorUpper',[],'shadeLower',[],'shadeUpper',[],'disabledMessage','');
            contingency = B.contingency;
            graphType = max(1, min(6, double(graphType)));
            info.percentRank = logical(handles.tglPercRank.Value);
            info.probTransform = logical(handles.tglP.Value);
            sortedView = logical(handles.tglSort.Value);

            switch graphType
                case {1,2,3}
                    basePred = double(B.mean_predictions(:));
                    predh = basePred;
                    if info.percentRank
                        info.decisionLineValue = nk_ComputePercentiles(basePred, 0, 'inverse');
                        predh = ranktransform(basePred);
                        contingency = ALLPARAM(B.labelh, predh-info.decisionLineValue);
                    elseif info.probTransform
                        info.decisionLineValue = 0.5;
                        if isfield(B,'Calibration') && isfield(B.Calibration,'Probabilities') && ~isempty(B.Calibration.Probabilities)
                            predh = double(B.Calibration.Probabilities(:));
                        else
                            probMethod = handles.alphaProbMethod;
                            predh = NMResultsViewerTools.probTransformMethod(B.labelh, basePred, probMethod);
                        end
                        contingency = ALLPARAM(B.labelh, predh-0.5);
                    else
                        info.decisionLineValue = 0;
                    end
                    if graphType == 2
                        info.errorKind = '95%-CI';
                        ci1 = double(B.CI1_predictions(:)); ci2 = double(B.CI2_predictions(:));
                        if info.percentRank
                            ci2 = ranktransform(basePred, ci2);
                            ci1 = ranktransform(basePred, ci1);
                        elseif info.probTransform
                            ci2 = NMResultsViewerTools.probTransformMethod(B.labelh, ci2, 'platt');
                            ci1 = NMResultsViewerTools.probTransformMethod(B.labelh, ci1, 'platt');
                        end
                        info = NMResultsViewerTools.attachLegacyErrorPayload(info, predh, ci1, ci2, sortedView);
                    elseif graphType == 3
                        info.errorKind = 'SD';
                        errbar = double(B.std_predictions(:));
                        if info.percentRank
                            errbarL = ranktransform(basePred, basePred-errbar/2);
                            errbarU = ranktransform(basePred, basePred+errbar/2);
                            lo = predh - (predh - errbarL);
                            hi = predh + (errbarU - predh);
                        else
                            lo = predh - errbar/2;
                            hi = predh + errbar/2;
                        end
                        info = NMResultsViewerTools.attachLegacyErrorPayload(info, predh, lo, hi, sortedView);
                    end
                case 4
                    predh = double(B.prob_predictions(:,1));
                    info.decisionLineValue = 0.5;
                    if info.percentRank
                        info.decisionLineValue = nk_ComputePercentiles(predh, 0.5, 'inverse');
                        predh = ranktransform(predh);
                    end
                    contingency = B.prob_contingency;
                case {5,6}
                    if ~isfield(B,'CV2grid') || isempty(B.CV2grid)
                        info.disabledMessage = 'BinClass.CV2grid is not available for this analysis.';
                        predh = [];
                        return;
                    end
                    basePred = double(B.CV2grid.mean_predictions(:));
                    predh = basePred;
                    info.decisionLineValue = 0.5;
                    if info.percentRank
                        info.decisionLineValue = nk_ComputePercentiles(basePred, 0.5, 'inverse');
                        predh = ranktransform(basePred);
                    end
                    contingency = B.prob_contingency;
                    if graphType == 5
                        info.errorKind = '95%-CI';
                        ci1 = double(B.CV2grid.CI1_predictions(:)); ci2 = double(B.CV2grid.CI2_predictions(:));
                        if info.percentRank
                            ci2 = ranktransform(basePred, ci2);
                            ci1 = ranktransform(basePred, ci1);
                        end
                        info = NMResultsViewerTools.attachLegacyErrorPayload(info, predh, ci1, ci2, sortedView);
                    else
                        info.errorKind = 'SD';
                        errbar = double(B.CV2grid.std_predictions(:));
                        if info.percentRank
                            errbarL = ranktransform(double(B.mean_predictions(:)), basePred-errbar/2);
                            errbarU = ranktransform(double(B.mean_predictions(:)), basePred+errbar/2);
                            lo = predh - (predh - errbarL);
                            hi = predh + (errbarU - predh);
                        else
                            lo = predh - errbar/2;
                            hi = predh + errbar/2;
                        end
                        info = NMResultsViewerTools.attachLegacyErrorPayload(info, predh, lo, hi, sortedView);
                    end
            end
            if graphType > 3 || info.percentRank || info.probTransform
                if info.percentRank || info.probTransform
                    info.zeroLineY = info.decisionLineValue;
                else
                    info.zeroLineY = 0.5;
                end
            else
                info.zeroLineY = 0;
            end
        end

        function info = attachLegacyErrorPayload(info, predh, lo, hi, sortedView)
            n = min([numel(predh), numel(lo), numel(hi)]);
            if n == 0, return; end
            predh = double(predh(1:n)); lo = double(lo(1:n)); hi = double(hi(1:n));
            info.hasError = true;
            if sortedView
                info.errorMode = 'shaded';
                info.shadeLower = lo;
                info.shadeUpper = hi;
            else
                info.errorMode = 'bars';
                info.errorLower = max(0, predh - lo);
                info.errorUpper = max(0, hi - predh);
            end
        end

        function out = errorBarsPayload(x, predh, plotInfo, sortedView)
            out = struct('ok',false,'mode','none','kind',plotInfo.errorKind,'bars',[],'band',[]);
            if ~isfield(plotInfo,'hasError') || ~plotInfo.hasError, return; end
            x = double(x(:)); predh = double(predh(:));
            if sortedView && isfield(plotInfo,'shadeLower') && ~isempty(plotInfo.shadeLower)
                n = min([numel(x), numel(plotInfo.shadeLower), numel(plotInfo.shadeUpper)]);
                band = repmat(struct('x',NaN,'lower',NaN,'upper',NaN), 1, n);
                for i=1:n
                    band(i).x = double(x(i));
                    band(i).lower = double(plotInfo.shadeLower(i));
                    band(i).upper = double(plotInfo.shadeUpper(i));
                end
                out.ok = true; out.mode = 'band'; out.band = band;
            elseif isfield(plotInfo,'errorLower') && ~isempty(plotInfo.errorLower)
                n = min([numel(x), numel(predh), numel(plotInfo.errorLower), numel(plotInfo.errorUpper)]);
                bars = repmat(struct('x',NaN,'y',NaN,'lower',NaN,'upper',NaN), 1, n);
                for i=1:n
                    bars(i).x = double(x(i));
                    bars(i).y = double(predh(i));
                    bars(i).lower = double(plotInfo.errorLower(i));
                    bars(i).upper = double(plotInfo.errorUpper(i));
                end
                out.ok = true; out.mode = 'bars'; out.bars = bars;
            end
        end

        function tf = cv2GridScoreModeAvailable(GD)
            tf = false;
            if ~isstruct(GD) || ~isfield(GD,'CV2grid'), return; end
            % Mirror load_GDdims.m.  The legacy transformer only creates
            % BinClass{j}.CV2grid when this exact contract is present.
            if ~isfield(GD,'mean_predictions'), return; end
            tf = true;
        end

        function [ok, handles, msg] = buildLegacyViewerState(NM, idx, targetIdx, graphType, viewerOpts)
            ok = false; msg = ''; handles = struct();
            % nm2-allow: external NM1.4 load_GDdims runtime dependency is checked at the transformation boundary
            if exist('load_GDdims','file') ~= 2
                msg = 'Legacy helper load_GDdims.m is not available on the MATLAB path. Add the NM Results Viewer GUI folder before using the browser alpha.';
                return;
            end
            % nm2-allow: external NM1.4 ALLPARAM runtime dependency is checked at the transformation boundary
            if exist('ALLPARAM','file') ~= 2
                msg = 'Legacy helper ALLPARAM.m is not available on the MATLAB path. Add the NM Results Viewer GUI folder before using the browser alpha.';
                return;
            end
            A = NM.analysis{idx};
            resultKind = viewerOpts.resultType;
            [sourceOk, GD, modelSource, sourceMsg] = NMResultsViewerTools.resultGDForSpec(NM, idx, resultKind, viewerOpts);
            if ~sourceOk, msg = sourceMsg; return; end

            [label, modeflag] = NMResultsViewerTools.analysisLabelAndMode(NM, A);
            originalTargetIdx = max(1, min(round(double(targetIdx)), size(label,2)));

            yStrings = NMResultsViewerTools.yAxisStringsForResult(GD, resultKind);
            graphType = max(1, min(numel(yStrings), double(graphType)));
            % nm2-allow: NM1.4 load_GDdims selects conditional GDdims.MultiClassProb only for the optional similarity-averaging multi-class probability view.
            if strcmp(resultKind,'multiclass') && graphType == 2 && ~isfield(GD,'MultiClassProb')
                msg = 'The legacy similarity-averaging multi-class probability field GDdims.MultiClassProb is absent; select the CV2-ensemble multi-class probability mode.';
                return;
            end
            if strcmp(resultKind,'classification') && ismember(graphType, [5 6]) && ~NMResultsViewerTools.cv2GridScoreModeAvailable(GD)
                msg = 'This analysis does not expose transformed CV2-grid probability score payloads. The legacy viewer disables the selected score mode.';
                return;
            end

            [targetLabel, legacyTargetIdx, targetGD, targetOk, targetMsg] = NMResultsViewerTools.legacyTargetLabelMatrix(A, GD, label, originalTargetIdx, resultKind, modeflag);
            if ~targetOk
                msg = targetMsg;
                return;
            end
            GD = targetGD;
            targetIdx = legacyTargetIdx;

            popupStrings = NMResultsViewerTools.legacyPopupStrings(NM, A, GD, resultKind);
            classifierIndex = viewerOpts.classifierIndex;
            popupValue = NMResultsViewerTools.legacyPopupValue(GD, resultKind, classifierIndex);
            multiModes = NMResultsViewerTools.multiClassModeOptions(NM, idx, viewerOpts);
            oneVsRestValue = NMResultsViewerTools.selectedMultiClassModeIndex(multiModes, viewerOpts);

            handles.NM = NM;
            % SYNTH data are stored per child; the analysis-local label fixes
            % the viewer's subject axis. Fully synthetic cases replace the
            % template cases, whereas existing-data SYNTH extends them.
            % nm2-allow: Normal NM analyses lack simulation, and only the fully synthetic producer writes simulation.mode.
            if isfield(A,'simulation')
                sim=A.simulation;
                % nm2-allow: Fully synthetic child manifests publish mode; existing-data child manifests publish observedN instead.
                if isfield(sim,'mode') && strcmp(sim.mode,'fully_synthetic')
                    % NMSynthPopulationGenerator.generate is the case-ID producer.
                    handles.NM.cases=arrayfun(@(j)sprintf('SYNTH_%06d',j), ...
                        (1:sim.sampleSize)','UniformOutput',false);
                else
                    syntheticRows=(sim.observedN+1:sim.sampleSize)';
                    newCases=arrayfun(@(j)sprintf('SYN_%s_%06d', ...
                        sim.synthAnalysisId(7:14),j),syntheticRows,'UniformOutput',false);
                    handles.NM.cases=[NM.cases(:);newCases];
                end
            end
            % The result transformer derives its CV case mask from NM.label;
            % bind that mask to the completed analysis, not the live workspace.
            handles.NM.label = label;
            if strcmp(modeflag,'classification')
                handles.NM.groupnames = NMResultsViewerTools.groupNamesForAnalysis(NM,idx);
            end
            handles.curranal = idx;
            handles.curmodal = 1; if isfinite(double(modelSource.index)), handles.curmodal = max(1,round(double(modelSource.index))); end
            handles.curlabel = targetIdx;
            handles.label = targetLabel;
            handles.modeflag = modeflag;
            handles.params = A.params;
            handles.subjects = NMResultsViewerTools.caseList(handles.NM, size(targetLabel,1));
            handles.oocvview = false;
            handles.METAstr = 'none'; if logical(modelSource.isMeta), handles.METAstr = 'bagged'; end
            handles.multi_modal = strcmp(NMResultsViewerTools.analysisFusionMode(A),'late');
            handles.modelSource = modelSource.id;
            handles.modelSourceLabel = modelSource.label;
            handles.alphaVectorWarning = '';
            handles.popupmenu1 = struct('String',{popupStrings}, 'Value', popupValue, 'Enable','on');
            handles.selYaxis = struct('String',{yStrings}, 'Value', graphType);
            handles.selOneVsAll_Info = struct('String',{NMResultsViewerTools.optionLabels(multiModes)}, 'Value', oneVsRestValue, 'Enable','off', 'Visible','off');
            handles.txtBinarize = struct('String',viewerOpts.binarizationThreshold, 'Enable','off');
            handles.tglSort = struct('Value', double(viewerOpts.sort));
            handles.tglPercRank = struct('Value', double(viewerOpts.percentRank), 'Enable','on');
            handles.tglP = struct('Value', double(viewerOpts.probTransform), 'Enable','on');
            handles.alphaProbMethod = viewerOpts.probMethod;
            handles.tglClrSwp = struct('Value', double(viewerOpts.colorSwap), 'Enable', 'on');
            handles.colptin = NMResultsViewerTools.colorTable();
            handles.colpt = 'o';
            handles.DataMarkerSize = 100;
            handles.DataMarkerWidth = 2;
            handles.DataMissMarkerSize = 100;
            handles.DataMissMarkerWidth = 2;
            handles.XaxisName = 'X axis';
            handles.GDdims = GD;
            handles.calibflag = false;
            [handles.params.algostr, handles.params.probflag] = determine_probflag(A.params.TrainParam.SVM);

            doProfile = NMResultsViewerTools.profileEnabled(viewerOpts);
            tLegacy = tic;
            handles = load_GDdims(handles, A.params.cv, targetLabel, GD);
            NMResultsViewerTools.profileLog(doProfile, ...
                '[nm-prof]       load_GDdims analysis=%d target=%d type=%s: %.3fs\n', ...
                double(idx), double(originalTargetIdx), resultKind, toc(tLegacy));
            handles = NMResultsViewerTools.overlayPersistedBinClassCalibration(handles, GD);
            handles.popupmenu1.String = popupStrings;
            handles.popupmenu1.Value = popupValue;
            handles.selYaxis.String = yStrings;
            handles.selYaxis.Value = graphType;
            handles.selOneVsAll_Info.String = NMResultsViewerTools.optionLabels(multiModes);
            handles.selOneVsAll_Info.Value = oneVsRestValue;
            handles = NMResultsViewerTools.applyPlotVectorXAxisOverride(handles, handles.NM, viewerOpts);
            handles = NMResultsViewerTools.applyPlotVectorSubgroupOverride(handles, handles.NM, viewerOpts);
            ok = true;
        end

        function [ok, handles, msg] = buildLegacyOOCVViewerState(NM, idx, targetIdx, graphType, viewerOpts, globalOOCVIndex)
            baseViewerOpts = viewerOpts;
            baseViewerOpts.deferPlotVectorOverrides = true;
            [ok, handles, msg] = NMResultsViewerTools.buildLegacyViewerState(NM,idx,targetIdx,graphType,baseViewerOpts);
            if ~ok, return; end
            ok = false;
            resultKind = NMResultsViewerTools.normalizeResultType(viewerOpts.resultType);
            requiredOOCVLabel = NMResultsViewerTools.oocvRequiredResultLabel(resultKind);
            descriptors = NMResultsViewerTools.oocvSourceDescriptors(NM,idx,resultKind);
            if isempty(descriptors)
                msg = sprintf('No applied %s OOCV/application result container with %s was detected for the selected analysis.', ...
                    resultKind,requiredOOCVLabel);
                return;
            end
            localOOCVIndex = find([descriptors.globalIndex] == globalOOCVIndex,1,'first');
            if isempty(localOOCVIndex)
                msg = sprintf('OOCV source oocv:%d is not a %s plotting source for analysis %d; %s is required.', ...
                    globalOOCVIndex,resultKind,idx,requiredOOCVLabel);
                return;
            end
            A = NM.analysis{idx};
            subgroupSpec = struct('source',sprintf('oocv:%d',globalOOCVIndex),'resultType',resultKind, ...
                'targetIndex',targetIdx,'oocvSubgroupIndex',viewerOpts.oocvSubgroupIndex);
            [subgroupOptions,handles.oocvSubgroupIndex] = NMResultsViewerTools.oocvSubgroupsForAnalysis(NM,idx,subgroupSpec);
            subgroupHit = find([subgroupOptions.index] == handles.oocvSubgroupIndex,1,'first');
            handles.oocvSubgroupLabel = subgroupOptions(subgroupHit).label;

            if strcmp(resultKind,'regression')
                handles.oocvResultField = 'RegrResults';
            elseif strcmp(resultKind,'multiclass')
                handles.oocvResultField = 'MultiResults';
            else
                % nm2-allow: load_GDdims creates MultiClass only for the multi-group training result family
                if isfield(handles,'MultiClass')
                    handles.oocvResultField = 'MultiResults';
                else
                    handles.oocvResultField = 'BinResults';
                end
            end
            selectedData = A.OOCV{globalOOCVIndex};
            % nm2-allow: nk_OOCVPrep writer condition selects the OOCV result family stored for this analysis application
            if ~isfield(selectedData,handles.oocvResultField) || isempty(selectedData.(handles.oocvResultField))
                msg = sprintf('Analysis %d OOCV source oocv:%d does not contain %s required by the selected model result family.', ...
                    idx,globalOOCVIndex,handles.oocvResultField);
                return;
            end

            handles.OOCVinfo = NMResultsViewerTools.oocvInfoForAnalysis(NM,idx,resultKind);
            sourceStrings = cell(1,numel(descriptors)+1);
            sourceStrings{1} = 'Training/CV data';
            for iiSource = 1:numel(descriptors)
                sourceStrings{iiSource+1} = descriptors(iiSource).descriptor;
            end
            handles.selCVoocv = struct('String',{sourceStrings},'Value',localOOCVIndex+1,'Enable','on');
            handles.selLabel = struct('Value',targetIdx);
            handles.prevanal = idx;
            handles.oocvview = true;

            oocvdata = cell(1,numel(descriptors));
            localOOCVMeta = cell(1,numel(descriptors));
            for iiOOCV = 1:numel(descriptors)
                g = descriptors(iiOOCV).globalIndex;
                oocvdata{iiOOCV} = A.OOCV{g};
                localOOCVMeta{iiOOCV} = NM.OOCV{g};
            end
            % nm2-allow: external NM1.4 transformation dependency must be present on the runtime path
            if exist('load_OOCV','file') ~= 2
                msg = 'Legacy helper load_OOCV.m is not available on the MATLAB path. Add the NM Results Viewer GUI folder before using OOCV Results Viewer payloads.';
                return;
            end
            handlesForLoad = handles;
            handlesForLoad.NM.OOCV = localOOCVMeta;
            handles = load_OOCV(handlesForLoad,oocvdata);
            handles.NM = NM;
            if strcmp(resultKind,'classification') || strcmp(resultKind,'multiclass')
                handles.NM.groupnames = NMResultsViewerTools.groupNamesForAnalysis(NM,idx);
            end
            for iiOOCV = 1:numel(descriptors)
                handles.OOCV(iiOOCV).num = descriptors(iiOOCV).globalIndex;
            end
            handles.oocvind = localOOCVIndex;
            ok = true;
            msg = '';
        end
        function [selectedIndex, mask] = multiClassOOCVSubgroupSelection(handles, oocvind, n)
            selectedIndex = double(handles.oocvSubgroupIndex);
            mask = true(n,1);
            if selectedIndex == 1, return; end
            D = handles.OOCV(oocvind);
            [opts, groupValues, groupIndex, refValue] = NMResultsViewerTools.multiClassOOCVSubgroupCatalogue(D);
            hit = find([opts.index] == selectedIndex,1,'first');
            if isempty(hit) || hit == 1
                error('NMResultsViewerTools:InvalidOOCVMultiClassSubgroup', ...
                    'The selected multiclass OOCV subgroup is not available.');
            end
            targetValue = groupValues(hit-1);
            if numel(groupIndex) ~= n
                error('NMResultsViewerTools:OOCVMultiClassSubgroupAxisMismatch', ...
                    'The persisted OOCV grouping axis must match the multiclass OOCV case axis.');
            end
            mask = groupIndex == targetValue;
            if isfinite(refValue), mask = mask | groupIndex == refValue; end
            mask = logical(mask(:));
        end

        function [opts, activeValues, groupIndex, refValue] = multiClassOOCVSubgroupCatalogue(D)
            tmpl = struct('index',1,'label','Show entire OOCV sample','enabled',true);
            opts = tmpl;
            activeValues = [];
            groupIndex = [];
            refValue = NaN;
            % nm2-allow: OOCV grouping itself is optional persisted DataIO/legacy metadata
            if ~isfield(D,'groups') || isempty(D.groups), return; end
            raw = D.groups;
            % nm2-allow: nk_OOCVPrep explicitly supports inherited logical-dummy and ordinal-vector persisted grouping generations
            if islogical(raw) && size(raw,2) > 1
                if any(sum(raw,2) ~= 1)
                    error('NMResultsViewerTools:InvalidOOCVGroupMembership', ...
                        'Inherited logical OOCV grouping must contain exactly one active group per case.');
                end
                [~,groupIndex] = max(raw,[],2);
                values = 1:size(raw,2);
            else
                groupIndex = double(raw(:));
                if any(~isfinite(groupIndex) | groupIndex ~= fix(groupIndex) | groupIndex < 1)
                    error('NMResultsViewerTools:InvalidOOCVGroupMembership', ...
                        'OOCV group identifiers must be finite positive integer values.');
                end
                values = unique(groupIndex,'sorted')';
                if ~isequal(values,1:numel(values))
                    error('NMResultsViewerTools:InvalidOOCVGroupAxis', ...
                        'Persisted OOCV group identifiers must form the canonical 1:G axis.');
                end
            end
            if isempty(groupIndex), return; end
            % nm2-allow: nk_OOCVPrep treats refgroup as optional persisted grouping metadata
            if isfield(D,'refgroup') && ~isempty(D.refgroup)
                refValue = double(D.refgroup);
                if ~isscalar(refValue) || ~isfinite(refValue) || refValue ~= fix(refValue) || ~ismember(refValue,values)
                    error('NMResultsViewerTools:InvalidOOCVReferenceGroup', ...
                        'Persisted OOCV reference group must identify one group on the grouping axis.');
                end
            end
            names = arrayfun(@(v)sprintf('OOCV subgroup %d',v),values,'UniformOutput',false);
            % nm2-allow: nk_OOCVPrep consumes optional grpnames only when one name exists for every persisted group
            if isfield(D,'grpnames') && ~isempty(D.grpnames)
                if numel(D.grpnames) ~= numel(values)
                    error('NMResultsViewerTools:InvalidOOCVGroupNameAxis', ...
                        'Persisted OOCV group names must match the grouping axis.');
                end
                names = D.grpnames(:)';
            end
            activeValues = values;
            if isfinite(refValue), activeValues(activeValues == refValue) = []; end
            opts = repmat(tmpl,1,numel(activeValues)+1);
            for ii = 1:numel(activeValues)
                v = activeValues(ii);
                label = names{v};
                if isfinite(refValue), label = sprintf('%s vs %s',names{v},names{refValue}); end
                opts(ii+1) = struct('index',ii+1,'label',label,'enabled',true);
            end
        end

        function [handles, selectedIndex, mask] = applyOOCVSubgroupSelection(handles, OOCVres, h, oocvind, n)
            selectedIndex = double(handles.oocvSubgroupIndex);
            mask = true(n,1);
            if selectedIndex > 1
                gIdx = selectedIndex - 1;
                mask = NMResultsViewerTools.oocvSubgroupMask(handles, OOCVres, oocvind, gIdx, n);
                handles.SubIndex = mask;
                % nm2-allow: nk_OOCV conditionally writes Group subgroup result material
                if isfield(OOCVres,'Group')
                    % nm2-allow: nk_OOCV conditionally writes subgroup permutation analysis material
                    if isfield(OOCVres.Group{gIdx},'PermAnal') && isfield(OOCVres.Group{gIdx}.PermAnal,'ModelPermSignificance')
                        handles.PermAnal = NMResultsViewerTools.selectPermValue(OOCVres.Group{gIdx}.PermAnal.ModelPermSignificance, h);
                    % nm2-allow: applyOOCVSubgroupSelection itself conditionally writes PermAnal only when permutation material exists
                    elseif isfield(handles,'PermAnal')
                        handles = rmfield(handles,'PermAnal');
                    end
                % nm2-allow: selected subgroup without writer Group material cannot retain whole-sample permutation state
                elseif isfield(handles,'PermAnal')
                    handles = rmfield(handles,'PermAnal');
                end
            else
                % nm2-allow: applyOOCVSubgroupSelection itself conditionally writes SubIndex only for a selected subgroup
                if isfield(handles,'SubIndex'), handles = rmfield(handles,'SubIndex'); end
                % nm2-allow: nk_OOCV conditionally writes whole-OOCV permutation analysis material
                if isfield(OOCVres,'PermAnal') && isfield(OOCVres.PermAnal,'ModelPermSignificance')
                    handles.PermAnal = NMResultsViewerTools.selectPermValue(OOCVres.PermAnal.ModelPermSignificance, h);
                % nm2-allow: applyOOCVSubgroupSelection itself conditionally writes PermAnal only when permutation material exists
                elseif isfield(handles,'PermAnal')
                    handles = rmfield(handles,'PermAnal');
                end
            end
        end

        function mask = oocvSubgroupMask(handles, OOCVres, oocvind, groupIdx, n)
            mask = false(n,1);
            if isfield(OOCVres,'Group') && numel(OOCVres.Group) >= groupIdx && isfield(OOCVres.Group{groupIdx},'Index')
                idx = double(OOCVres.Group{groupIdx}.Index(:));
                idx = idx(isfinite(idx) & idx >= 1 & idx <= n);
                mask(round(idx)) = true;
                return;
            end
            % oocvInfoForAnalysis builds the complete local/global source map;
            % buildLegacyOOCVViewerState restores the committed NM after load_OOCV.
            entry = handles.OOCVinfo.Analyses{handles.curranal};
            g = entry.OOCVvec(oocvind);
            D = handles.NM.OOCV{g};
            if isfield(D,'groups') % nm2-allow: OOCV DataIO grouping metadata is optional after source admission.
                mask = NMResultsViewerTools.oocvMaskFromDescriptorGroups(D, groupIdx, n);
            end
        end

        function mask = oocvMaskFromDescriptorGroups(D, groupIdx, n)
            mask = false(n,1);
            groups = D.groups;
            if islogical(groups)
                G = groups;
            else
                gv = double(groups(:));
                lev = unique(gv(isfinite(gv)),'sorted');
                G = false(numel(gv), numel(lev));
                for ii = 1:numel(lev), G(:,ii) = gv == lev(ii); end
            end
            if isfield(D,'refgroup') && ~isempty(D.refgroup)
                ref = round(double(D.refgroup));
                if groupIdx >= ref, groupIdx = groupIdx + 1; end
                cols = [groupIdx ref];
            else
                cols = groupIdx;
            end
            cols = cols(cols >= 1 & cols <= size(G,2));
            m = any(G(:,cols),2);
            mask(1:min(n,numel(m))) = logical(m(1:min(n,numel(m))));
        end

        function val = selectPermValue(v, h)
            v = double(v(:));
            if isempty(v), val = NaN; return; end
            if numel(v) >= h, val = v(h); else, val = v(1); end
        end

        function [label, modeflag, info] = analysisLabelAndMode(~, A)
            % analysisLabelAndMode  Resolve the persisted analysis-local target contract.
            %
            % nk_InitAnalysisPrep writes analysis.params.label for every analysis.
            % Results Viewer consumes that snapshot directly; native/alternative
            % target selection has already been resolved at the analysis boundary.
            L = A.params.label;
            label = L.label;
            modeflag = L.modeflag;
            info = struct('source','analysis.params.label','labelName',L.labelname,'selectedColumns',[]);
            if ~logical(L.altlabelflag)
                info.selectedColumns = NMResultsViewerTools.multiLabelSelection(A,size(label,2));
            end
        end


        function opts = yAxisOptionsForAnalysis(NM, idx, resultType, spec)
            if isempty(resultType), resultType = 'classification'; end

            kind = NMResultsViewerTools.normalizeResultType(resultType);
            if strcmp(kind, 'model_optimization')
                opts = NMResultsViewerTools.modelOptimizationMeasureOptions(NM, idx, spec);
                return;
            end
            [~, GD] = NMResultsViewerTools.resultGDForSpec(NM, idx, kind, spec);
            labels = NMResultsViewerTools.yAxisStringsForResult(GD, kind);
            tmpl = struct('index',1,'id','1','label','Mean classifier scores','enabled',true,'reason','');
            opts = repmat(tmpl, 1, max(1,numel(labels)));
            for ii = 1:numel(labels)
                opts(ii).index = ii;
                opts(ii).id = char(string(ii));
                opts(ii).label = labels{ii};
                opts(ii).enabled = true;
                opts(ii).reason = '';
                if strcmp(kind,'classification') && ismember(ii, [5 6]) && ~NMResultsViewerTools.cv2GridScoreModeAvailable(GD)
                    opts(ii).enabled = false;
                    opts(ii).reason = 'CV2-grid ensemble probability payload was not generated by the legacy load_GDdims backend for this analysis.';
                elseif strcmp(kind,'multiclass') && ii == 2 && (~isstruct(GD) || ~isfield(GD,'MultiClassProb'))
                    opts(ii).enabled = false;
                    opts(ii).reason = 'GDdims.MultiClassProb is absent; similarity-averaging multi-class probabilities are unavailable.';
                end
            end
        end

    end

    methods (Static)
        function [opts, spec] = viewerPlotOptions(spec)
            % Existing direct-MATLAB specification producer. The browser uses
            % NMResultsViewerUI.requestSpec to apply envelope and navigation rules.
            if isempty(spec), spec = struct(); end
            hasVersion = isfield(spec,'canonicalSpecVersion'); % nm2-allow: viewerPlotOptions marks its fully materialized typed structure; subsequent internal reads reuse it.
            if hasVersion && spec.canonicalSpecVersion ~= 2
                error('NMResultsViewerTools:InvalidCanonicalSpecVersion', ...
                    'Results Viewer specification version %g is not supported.',spec.canonicalSpecVersion);
            end
            if ~hasVersion
            defaults = struct('plotSort',false,'colorSwap',false,'percentRank',false, ...
                'probTransform',false,'calibrationMethod','platt','source','cv', ...
                'modelSource','','analysisIndex',NaN,'targetIndex',1, ...
                'resultType','classification','classifierIndex',1,'multiClassModeIndex',1, ...
                'binarizationThreshold','','oocvSubgroupIndex',1, ...
                'xAxisExpression','','xAxisLabel','','subgroupExpression','', ...
                'targetNativeIndex',NaN,'graphType',1,'modalityIndex',NaN, ...
                'componentIndex',NaN,'maxFeatures',200,'maxComponents',200, ...
                'subjectCaseIndex',0,'numBins',10,'maxProb',NaN,'stepSize',0.05, ...
                'binarizationEnabled',false,'forceRecomputeProbability',false, ...
                'smoothCurve',false,'featureContextId','','backprojectionComponentId','', ...
                'measureId','','subjectCaseId','','action','probability', ...
                'calibrationMetric','ECE','featureInspectionPayloadScope','full', ...
                'featureInspectionCatalogueScope','complete');
            names = fieldnames(defaults);
            for j = 1:numel(names)
                name = names{j}; fallback = defaults.(name);
                if ~isfield(spec,name) || ... % nm2-allow: typed template fills absent specification fields; explicit empty selectors retain their scientific-catalogue meaning.
                        (isempty(spec.(name)) && ~any(strcmp(name,{'resultType','source'}))) % nm2-allow: typed template defaults partial MATLAB specifications; explicit empty result/source selectors preserve scientific-catalogue reselection.
                    spec.(name) = fallback;
                    continue;
                end
                raw = spec.(name);
                if islogical(fallback) % nm2-allow: the field template defines which properties are logical scalars.
                    if isnumeric(raw) || islogical(raw) % nm2-allow: some MATLAB fixture definitions encode flags as numeric values and others as text.
                        spec.(name) = logical(raw(1));
                    else
                        spec.(name) = any(strcmp(lower(strtrim(char(string(raw)))), ... % nm2-allow: this typed specification template materializes textual logical states once.
                            {'1','true','yes','on'})); % nm2-allow: this template-based producer converts logical text tokens into canonical logical values.
                    end
                elseif isnumeric(fallback) % nm2-allow: the field template defines which properties are numeric scalars.
                    if isnumeric(raw) || islogical(raw) % nm2-allow: the typed specification template permits scalar numeric or numeric text values.
                        spec.(name) = double(raw(1));
                    else
                        spec.(name) = str2double(string(raw(1)));
                    end
                else
                    spec.(name) = char(string(raw)); % nm2-allow: the typed specification template materializes text once from stored values.
                end
            end
            spec.calibrationMethod = lower(strtrim(spec.calibrationMethod)); % nm2-allow: the plotting specification template stores the calibration token in canonical form.
            if ~any(strcmp(spec.calibrationMethod,{'platt','isotonic','bbq','none'}))
                error('NMResultsViewerTools:UnknownCalibrationMethod', ...
                    'Unknown calibration method: %s.',spec.calibrationMethod);
            end
            spec.action = lower(strtrim(spec.action)); % nm2-allow: the plotting specification template stores the selected action spelling canonically.
            spec.xAxisExpression = strtrim(spec.xAxisExpression);
            spec.xAxisLabel = strtrim(spec.xAxisLabel);
            spec.subgroupExpression = strtrim(spec.subgroupExpression);
            spec.featureContextId = strtrim(spec.featureContextId);
            spec.backprojectionComponentId = strtrim(spec.backprojectionComponentId);
            spec.measureId = strtrim(spec.measureId);
            spec.featureInspectionPayloadScope = validatestring( ...
                lower(strtrim(spec.featureInspectionPayloadScope)),{'full','metadata'}); % nm2-allow: the feature inspection specification template constrains payload scope to its two defined states.
            spec.featureInspectionCatalogueScope = validatestring( ...
                lower(strtrim(spec.featureInspectionCatalogueScope)),{'complete','selected'}); % nm2-allow: the feature inspection specification template constrains catalogue scope to its two defined states.
            spec.canonicalSpecVersion = 2;
            end
            opts = struct('sort',spec.plotSort,'colorSwap',spec.colorSwap, ...
                'percentRank',spec.percentRank,'probTransform',spec.probTransform, ...
                'probMethod',spec.calibrationMethod,'source',spec.source, ...
                'modelSource',spec.modelSource,'analysisIndex',spec.analysisIndex, ...
                'targetIndex',spec.targetIndex,'resultType',spec.resultType, ...
                'classifierIndex',spec.classifierIndex, ...
                'multiClassModeIndex',spec.multiClassModeIndex, ...
                'binarizationThreshold',spec.binarizationThreshold, ...
                'oocvSubgroupIndex',spec.oocvSubgroupIndex, ...
                'xAxisExpression',spec.xAxisExpression,'xAxisLabel',spec.xAxisLabel, ...
                'subgroupExpression',spec.subgroupExpression,'deferPlotVectorOverrides',false);
        end

    end

    methods (Static, Access = private)
        function strs = yAxisStringsForResult(GD, resultType)
            switch NMResultsViewerTools.normalizeResultType(resultType)
                case 'regression'
                    strs = {'Mean target predictions','Mean target predictions (95%-CIs)','Mean target predictions (SD)'};
                case 'multiclass'
                    strs = {'Multi-group probabilities derived from CV2-ensembles', ...
                        'Multi-group probabilities derived from similarity averaging'};
                otherwise
                    strs = {'Mean classifier scores','Mean classifier scores (95%-CIs)','Mean classifier scores (SD)', ...
                        'Ensemble-based probability scores','Mean ensemble-based probability scores (95%-CIs)', ...
                        'Mean ensemble-based probability scores (SD)'};
            end
        end

        function cases = caseList(NM, n)
            cases = repmat({''}, n, 1);
            if isstruct(NM) && isfield(NM,'cases') && ~isempty(NM.cases)
                c = NM.cases;
                if iscell(c)
                    for i=1:min(n,numel(c)), cases{i} = char(string(c{i})); end
                else
                    cs = cellstr(string(c));
                    for i=1:min(n,numel(cs)), cases{i} = char(string(cs{i})); end
                end
            end
            for i=1:n, if isempty(cases{i}), cases{i} = sprintf('Case %d', i); end, end
        end

        function colors = classColors(handles, B)
            clrswp = false;
            if isfield(handles,'tglClrSwp') && isfield(handles.tglClrSwp,'Value'), clrswp = logical(handles.tglClrSwp.Value); end
            if clrswp, g1 = 2; g2 = 1; else, g1 = 1; g2 = 2; end
            C = handles.colptin;
            gi = double(B.groupind(:));
            i1 = min(max(1, gi(min(g1,numel(gi)))), size(C,1));
            colors.group1 = NMResultsViewerTools.rgbHex(C(i1,:));
            if isfield(B,'one_vs_all') && B.one_vs_all
                colors.group2 = NMResultsViewerTools.rgbHex([0.35 0.35 0.35]);
            else
                i2 = min(max(1, gi(min(g2,numel(gi)))), size(C,1));
                colors.group2 = NMResultsViewerTools.rgbHex(C(i2,:));
            end
        end

        function points = classPlotPoints(x, y, cases, labelh, id1, id2, err, groupnames, colors, offs)
            tmpl = struct('x',NaN,'y',NaN,'caseId','','expected','','predicted','','group',0,'misclassified',false,'marker','circle','color','#2563eb','cutoff',0,'tooltip','');
            n = numel(y); points = repmat(tmpl, 1, n);
            gn = NMResultsViewerTools.asStringCell(groupnames);
            for i=1:n
                expected = gn{2}; if labelh(i) > 0, expected = gn{1}; end
                predicted = gn{2}; if y(i) > offs(i), predicted = gn{1}; end
                if id1(i), grp = 1; color = colors.group1; elseif id2(i), grp = 2; color = colors.group2; else, grp = 0; color = '#64748b'; end
                marker = 'circle'; if err(i), marker = 'x'; end
                caseId = char(string(cases{i}));
                if isfinite(double(offs(i))) && abs(double(offs(i))) > eps
                    tip = sprintf('Subject ID [%d]: %s\nExpected group: %s\nPredicted Group: %s\nScore: %g\nCutoff: %g', i, caseId, expected, predicted, y(i), offs(i));
                else
                    tip = sprintf('Subject ID: %s\nExpected group: %s\nPredicted Group: %s\nScore: %g', caseId, expected, predicted, y(i));
                end
                points(i) = struct('x',double(x(i)),'y',double(y(i)),'caseId',caseId, ...
                    'expected',expected,'predicted',predicted,'group',grp,'misclassified',logical(err(i)), ...
                    'marker',marker,'color',color,'cutoff',double(offs(i)),'tooltip',tip);
            end
        end

        function [xLim,yLim] = legacyLimits(x, y)
            if isempty(x), xLim = [0 1]; yLim = [0 1]; return; end
            minX = min(x); maxX = max(x);
            if numel(x) == numel(unique(x)) && all(abs(diff(sort(x))-1) < 1e-12)
                r = 1;
            else
                r = NMResultsViewerTools.rangeValue(x)/100*5;
            end
            if r == 0, r = 1; end
            xLim = [minX-r maxX+r];
            yr = NMResultsViewerTools.rangeValue(y)*0.05;
            if yr == 0, yr = max(0.1, abs(double(y(1)))*0.05); end
            yLim = [min(y)-yr max(y)+yr];
            if sum(yLim < 0) == 2, yLim(2) = 0.1; end
            if sum(yLim > 0) == 2, yLim(1) = -0.1; end
        end

        function [xLim,yLim] = regressionLimits(x, y)
            % regressionLimits  Match legacy display_regrplot range padding without forcing zero into view.
            %
            % Regression predictions can occupy a narrow positive interval. The
            % generic classification limit helper expands such data to -0.1, which
            % compresses the scientifically relevant range. Legacy
            % display_regrplot instead applies five-percent padding around each
            % finite data range and does not force either axis through zero.
            x = double(x(:));
            y = double(y(:));
            x = x(isfinite(x));
            y = y(isfinite(y));
            if isempty(x), xLim = [0 1]; else
                xr = max(x) - min(x);
                if xr <= 0, xr = max(1, abs(x(1))*0.05); end
                xp = 0.05 * xr;
                xLim = [min(x)-xp max(x)+xp];
            end
            if isempty(y), yLim = [0 1]; else
                yr = max(y) - min(y);
                if yr <= 0, yr = max(0.1, abs(y(1))*0.05); end
                yp = 0.05 * yr;
                yLim = [min(y)-yp max(y)+yp];
            end
        end

        function [xPlot, diag] = xAxisDiagnostics(x, y, labels, groupNames, colors, alternativeXAxis, classificationMode)

            x = double(x(:)); y = double(y(:));
            if isempty(labels), labels = nan(size(y)); else, labels = double(labels(:)); end
            if numel(labels) < numel(y), labels(end+1:numel(y),1) = NaN; end %#ok<AGROW>
            labels = labels(1:numel(y));
            xPlot = x;
            emptyCats = repmat(struct('index',NaN,'value',NaN,'label',''),1,0);
            emptyBoxes = repmat(struct('categoryIndex',NaN,'categoryLabel','','groupIndex',NaN,'groupLabel','','color','#64748b','n',0,'low',NaN,'q1',NaN,'median',NaN,'q3',NaN,'high',NaN,'mean',NaN),1,0);
            emptyAssoc = repmat(struct('label','','color','#111827','n',0,'slope',NaN,'intercept',NaN,'r',NaN,'p',NaN,'line',[],'text',''),1,0);
            diag = struct('ok',false,'mode','continuous','isCategorical',false,'categories',emptyCats,'boxGroups',emptyBoxes,'associations',emptyAssoc,'summary','');
            if ~alternativeXAxis
                return;
            end
            good = isfinite(x) & isfinite(y);
            if sum(good) < 2
                diag.summary = 'Association unavailable because fewer than two finite points are present.';
                return;
            end
            finiteX = x(good);
            ux = unique(finiteX);
            if alternativeXAxis && numel(ux) >= 2 && numel(ux) < 10
                diag.mode = 'categorical';
                diag.isCategorical = true;
                [~,~,icAll] = unique(x);
                xPlot = double(icAll(:));
                xPlot(~isfinite(x)) = NaN;
                cats = repmat(struct('index',NaN,'value',NaN,'label',''),1,numel(ux));
                for ii = 1:numel(ux)
                    cats(ii) = struct('index',double(ii),'value',double(ux(ii)),'label',NMResultsViewerTools.formatNumber(ux(ii)));
                end
                diag.categories = cats;
                [boxGroups, summary] = NMResultsViewerTools.categoricalBoxGroups(xPlot, y, labels, cats, groupNames, colors, classificationMode);
                diag.boxGroups = boxGroups;
                diag.summary = summary;
                diag.ok = true;
                return;
            end
            diag.associations = NMResultsViewerTools.continuousAssociations(x, y, labels, groupNames, colors, classificationMode);
            diag.ok = ~isempty(diag.associations);
            if diag.ok
                txt = {diag.associations.text}; txt = txt(~cellfun(@isempty,txt));
                diag.summary = strjoin(txt, ' | ');
            else
                diag.summary = 'Association unavailable.';
            end
        end

        function [boxes, summary] = categoricalBoxGroups(xCat, y, labels, cats, groupNames, colors, classificationMode)
            summary = '';
            tmpl = struct('categoryIndex',NaN,'categoryLabel','','groupIndex',NaN,'groupLabel','','color','#64748b','n',0,'low',NaN,'q1',NaN,'median',NaN,'q3',NaN,'high',NaN,'mean',NaN);
            rows = repmat(tmpl, 1, max(1,numel(cats)*3));
            nRows = 0;
            groupInfo = struct('value',NaN,'index',1,'label','All','color','#64748b');
            if classificationMode && ~isempty(labels)
                lv = unique(labels(isfinite(labels) & labels ~= 0));
                if ~isempty(lv)
                    gn = NMResultsViewerTools.asStringCell(groupNames);
                    posVals = lv(lv > 0);
                    otherVals = lv(lv <= 0);
                    if isempty(otherVals) && numel(lv) > numel(posVals)
                        otherVals = setdiff(lv, posVals);
                    end
                    ordered = [posVals(:); otherVals(:)];
                    if isempty(ordered), ordered = lv(:); end
                    groupInfo = repmat(struct('value',NaN,'index',1,'label','All','color','#64748b'),1,numel(ordered));
                    for gg = 1:numel(ordered)
                        if ordered(gg) > 0
                            groupInfo(gg) = struct('value',double(ordered(gg)),'index',1,'label',gn{1},'color',colors.group1);
                        else
                            groupInfo(gg) = struct('value',double(ordered(gg)),'index',2,'label',gn{2},'color',colors.group2);
                        end
                    end
                end
            end
            for cc = 1:numel(cats)
                for gg = 1:numel(groupInfo)
                    if isnan(groupInfo(gg).value)
                        mask = xCat == cc & isfinite(y);
                    else
                        mask = xCat == cc & isfinite(y) & labels == groupInfo(gg).value;
                    end
                    vals = double(y(mask));
                    if isempty(vals), continue; end
                    st = NMResultsViewerTools.vectorBoxStats(vals);
                    nRows = nRows + 1;
                    if nRows > numel(rows), rows(end+1:end+numel(cats)) = tmpl; end %#ok<AGROW>
                    rows(nRows) = struct('categoryIndex',double(cc),'categoryLabel',cats(cc).label,'groupIndex',double(groupInfo(gg).index), ...
                        'groupLabel',groupInfo(gg).label,'color',groupInfo(gg).color,'n',double(numel(vals)), ...
                        'low',double(st.low),'q1',double(st.q1),'median',double(st.median),'q3',double(st.q3),'high',double(st.high),'mean',double(st.mean));
                end
            end
            boxes = rows(1:nRows);
            good = isfinite(xCat) & isfinite(y);
            if sum(good) >= 3 && numel(unique(xCat(good))) >= 2
                [eta2, pCat] = NMResultsViewerTools.categoryDifferenceStats(xCat(good), y(good));
                summary = sprintf('Category difference: eta^2=%s', NMResultsViewerTools.formatNumber(eta2));
                if isfinite(pCat), summary = sprintf('%s, p=%s', summary, NMResultsViewerTools.formatNumber(pCat)); end
                ux = unique(xCat(good));
                if numel(ux) == 2
                    a = y(good & xCat == ux(1)); b = y(good & xCat == ux(2));
                    d = NMResultsViewerTools.cohenD(a,b);
                    summary = sprintf('%s, Cohen d=%s', summary, NMResultsViewerTools.formatNumber(d));
                end
            end
        end

        function st = vectorBoxStats(vals)
            vals = sort(double(vals(:))); vals = vals(isfinite(vals));
            if isempty(vals)
                st = struct('low',NaN,'q1',NaN,'median',NaN,'q3',NaN,'high',NaN,'mean',NaN); return;
            end
            st = struct('low',double(vals(1)), 'q1',NMResultsViewerTools.percentileSorted(vals,25), ...
                'median',NMResultsViewerTools.percentileSorted(vals,50), 'q3',NMResultsViewerTools.percentileSorted(vals,75), ...
                'high',double(vals(end)), 'mean',double(mean(vals,'omitnan')));
        end

        function q = percentileSorted(vals, pct)
            vals = double(vals(:)); vals = vals(isfinite(vals)); vals = sort(vals);
            if isempty(vals), q = NaN; return; end
            if numel(vals) == 1, q = double(vals(1)); return; end
            pos = 1 + (numel(vals)-1) * (double(pct)/100);
            lo = floor(pos); hi = ceil(pos);
            if lo == hi, q = double(vals(lo)); else, q = double(vals(lo) + (pos-lo)*(vals(hi)-vals(lo))); end
        end

        function [eta2, pVal] = categoryDifferenceStats(xCat, y)
            xCat = double(xCat(:)); y = double(y(:));
            good = isfinite(xCat) & isfinite(y);
            xCat = xCat(good); y = y(good);
            eta2 = NMResultsViewerTools.oneWayEtaSquared(xCat, y);
            pVal = NaN;
            cats = unique(xCat);
            if numel(cats) < 2 || numel(y) < 3, return; end
            if numel(cats) == 2
                a = y(xCat == cats(1)); b = y(xCat == cats(2));
                pVal = NMResultsViewerTools.twoSampleTApproxP(a,b);
                return;
            end
            grand = mean(y,'omitnan');
            ssBetween = 0; ssWithin = 0; k = 0; n = 0;
            for ii = 1:numel(cats)
                vals = y(xCat == cats(ii)); vals = vals(isfinite(vals));
                if isempty(vals), continue; end
                k = k + 1; n = n + numel(vals);
                mu = mean(vals,'omitnan');
                ssBetween = ssBetween + numel(vals) * (mu - grand)^2;
                ssWithin = ssWithin + sum((vals - mu).^2,'omitnan');
            end
            df1 = k - 1; df2 = n - k;
            if df1 <= 0 || df2 <= 0 || ssWithin <= 0, return; end
            F = (ssBetween / df1) / (ssWithin / df2);
            pVal = NMResultsViewerTools.fUpperTailP(F, df1, df2);
        end

        function pVal = twoSampleTApproxP(a,b)
            a = double(a(:)); b = double(b(:)); a = a(isfinite(a)); b = b(isfinite(b));
            pVal = NaN;
            if numel(a) < 2 || numel(b) < 2, return; end
            ma = mean(a,'omitnan'); mb = mean(b,'omitnan');
            va = var(a,0,'omitnan'); vb = var(b,0,'omitnan');
            se2 = va/numel(a) + vb/numel(b);
            if se2 <= 0, return; end
            t = (ma - mb) / sqrt(se2);
            dfNum = se2^2;
            dfDen = (va/numel(a))^2 / max(1,numel(a)-1) + (vb/numel(b))^2 / max(1,numel(b)-1);
            if dfDen <= 0, return; end
            df = dfNum / dfDen;
            pVal = NMResultsViewerTools.tTwoSidedP(t, df);
        end

        function pVal = tTwoSidedP(t, df)
            pVal = NaN;
            if ~isfinite(t) || ~isfinite(df) || df <= 0, return; end
            x = df / (df + double(t)^2);
            pVal = betainc(max(0,min(1,x)), df/2, 0.5);
        end

        function pVal = fUpperTailP(F, df1, df2)
            pVal = NaN;
            if ~isfinite(F) || F < 0 || df1 <= 0 || df2 <= 0, return; end
            x = (df1 * F) / (df1 * F + df2);
            pVal = 1 - betainc(max(0,min(1,x)), df1/2, df2/2);
        end

        function eta2 = oneWayEtaSquared(xCat, y)
            xCat = double(xCat(:)); y = double(y(:));
            good = isfinite(xCat) & isfinite(y);
            xCat = xCat(good); y = y(good);
            eta2 = NaN;
            if numel(y) < 2, return; end
            grand = mean(y,'omitnan');
            ssTotal = sum((y-grand).^2,'omitnan');
            if ssTotal <= 0, return; end
            cats = unique(xCat);
            ssBetween = 0;
            for ii = 1:numel(cats)
                vals = y(xCat == cats(ii));
                if isempty(vals), continue; end
                ssBetween = ssBetween + numel(vals) * (mean(vals,'omitnan') - grand)^2;
            end
            eta2 = ssBetween / ssTotal;
        end

        function d = cohenD(a,b)
            a = double(a(:)); b = double(b(:)); a = a(isfinite(a)); b = b(isfinite(b));
            d = NaN;
            if numel(a) < 2 || numel(b) < 2, return; end
            va = var(a,0,'omitnan'); vb = var(b,0,'omitnan');
            sp = sqrt(((numel(a)-1)*va + (numel(b)-1)*vb) / max(1, numel(a)+numel(b)-2));
            if sp > 0, d = (mean(a,'omitnan') - mean(b,'omitnan')) / sp; end
        end

        function assoc = continuousAssociations(x, y, labels, groupNames, colors, classificationMode)
            tmpl = struct('label','','color','#111827','n',0,'slope',NaN,'intercept',NaN,'r',NaN,'p',NaN,'line',[],'text','');
            assoc = repmat(tmpl,1,0);
            groupInfo = struct('value',NaN,'label','All','color','#111827');
            if classificationMode && ~isempty(labels)
                lv = unique(labels(isfinite(labels) & labels ~= 0));
                if ~isempty(lv)
                    gn = NMResultsViewerTools.asStringCell(groupNames);
                    posVals = lv(lv > 0);
                    otherVals = lv(lv <= 0);
                    ordered = [posVals(:); otherVals(:)];
                    if isempty(ordered), ordered = lv(:); end
                    groupInfo = repmat(struct('value',NaN,'label','All','color','#111827'),1,numel(ordered));
                    for gg = 1:numel(ordered)
                        if ordered(gg) > 0
                            groupInfo(gg) = struct('value',double(ordered(gg)),'label',gn{1},'color',colors.group1);
                        else
                            groupInfo(gg) = struct('value',double(ordered(gg)),'label',gn{2},'color',colors.group2);
                        end
                    end
                end
            end
            rows = repmat(tmpl,1,numel(groupInfo)); nRows = 0;
            for gg = 1:numel(groupInfo)
                if isnan(groupInfo(gg).value)
                    mask = isfinite(x) & isfinite(y);
                else
                    mask = isfinite(x) & isfinite(y) & labels == groupInfo(gg).value;
                end
                xv = double(x(mask)); yv = double(y(mask));
                if numel(xv) < 3 || numel(unique(xv)) < 2, continue; end
                p = polyfit(xv, yv, 1);
                r = corrcoef(xv, yv); rr = NaN; if numel(r) >= 4, rr = r(1,2); end
                pv = NaN;
                if isfinite(rr) && abs(rr) < 1
                    t = rr * sqrt((numel(xv)-2) / max(eps, 1-rr^2));
                    pv = NMResultsViewerTools.tTwoSidedP(t, numel(xv)-2);
                end
                xLine = linspace(min(xv), max(xv), 2)';
                yLine = polyval(p, xLine);
                line = repmat(struct('x',NaN,'y',NaN),1,2);
                for ii = 1:2, line(ii) = struct('x',double(xLine(ii)),'y',double(yLine(ii))); end
                nRows = nRows + 1;
                rows(nRows) = struct('label',groupInfo(gg).label,'color',groupInfo(gg).color,'n',double(numel(xv)), ...
                    'slope',double(p(1)),'intercept',double(p(2)),'r',double(rr),'p',double(pv),'line',line, ...
                    'text',NMResultsViewerTools.associationText(groupInfo(gg).label, p(1), rr, pv, numel(xv)));
            end
            assoc = rows(1:nRows);
        end

        function txt = associationText(label, slope, r, p, n)
            if isfinite(p)
                txt = sprintf('%s: slope=%s, r=%s, p=%s, n=%d', label, NMResultsViewerTools.formatNumber(slope), NMResultsViewerTools.formatNumber(r), NMResultsViewerTools.formatNumber(p), n);
            else
                txt = sprintf('%s: slope=%s, r=%s, n=%d', label, NMResultsViewerTools.formatNumber(slope), NMResultsViewerTools.formatNumber(r), n);
            end
        end

        function patches = classBackgroundPatches(x, id1, id2, altAx, sortedFlag, xLim, yLim, offy, colors)
            tmpl = struct('x',NaN,'y',NaN,'w',NaN,'h',NaN,'color','','alpha',0.15);
            patches = tmpl([]);
            if altAx || sortedFlag || ~any(id1) || ~any(id2), return; end
            f1 = find(id1); f2 = find(id2); r = 1;
            patches(end+1) = struct('x',double(x(f1(1))-1),'y',double(offy),'w',double((x(f1(end))+r)-(x(f1(1))-1)), ...
                'h',double(yLim(2)-offy),'color',colors.group1,'alpha',0.15); %#ok<AGROW>
            if f1(1)>1 && f1(end)<xLim(2)
                patches(end+1) = struct('x',double(x(f2(1))),'y',double(yLim(1)),'w',double(x(f1(1))-x(f2(1))), ...
                    'h',double(offy-yLim(1)),'color',colors.group2,'alpha',0.15); %#ok<AGROW>
                patches(end+1) = struct('x',double(x(f1(end))),'y',double(yLim(1)),'w',double(xLim(2)-x(f1(end))), ...
                    'h',double(offy-yLim(1)),'color',colors.group2,'alpha',0.15); %#ok<AGROW>
            else
                patches(end+1) = struct('x',double(x(f2(1))),'y',double(yLim(1)),'w',double(xLim(2)-x(f2(1))), ...
                    'h',double(offy-yLim(1)),'color',colors.group2,'alpha',0.15); %#ok<AGROW>
            end
        end

        function z = zeroLinePayload(xLim, x, zeroY, coxMode)
            z = struct('x',double(xLim(:)'),'y',[double(zeroY) double(zeroY)],'coxMode',logical(coxMode));
            if coxMode && numel(zeroY) == numel(x)
                z.x = double(x(:)'); z.y = double(zeroY(:)');
            end
        end

        function lab = legacyYAxisLabel(handles, graphType, plotInfo)
            switch graphType
                case {1,2,3}
                    if isfield(handles.params,'algostr') && ~isempty(handles.params.algostr)
                        lab = handles.params.algostr;
                        if iscell(lab), lab = lab{1}; end
                        if isstring(lab) && isscalar(lab) && ismissing(lab), lab = 'classifier score'; end
                        lab = char(string(lab));
                    else
                        lab = 'classifier score';
                    end
                case 4
                    lab = 'OOT-Probability';
                case 5
                    lab = 'Mean OOT-Probability (95%-CIs)';
                case 6
                    lab = 'Mean OOT-Probability (SD)';
                otherwise
                    lab = 'classifier score';
            end
            if plotInfo.percentRank
                lab = [lab ' (%-ranks)'];
            elseif plotInfo.probTransform
                lab = [lab ' (prob)'];
            end
        end

        function legendItems = classLegend(groupnames, graphType, plotInfo)
            gn = NMResultsViewerTools.asStringCell(groupnames);
            legendItems = {gn{1}, gn{2}, 'misclassified', 'misclassified'};
            if ismember(graphType,[2 3 5 6]) && ~strcmp(plotInfo.errorKind,'none')
                legendItems{end+1} = plotInfo.errorKind;
            end
        end

        function p = cvProbabilityColumn(B, n)
            p = nan(n,1);
            if isstruct(B) && isfield(B,'Calibration') && isstruct(B.Calibration) && isfield(B.Calibration,'Probabilities') && ~isempty(B.Calibration.Probabilities)
                p = NMResultsViewerTools.padNumericColumn(double(B.Calibration.Probabilities(:)), n, NaN);
            end
        end

        function [rows, columns] = scoreRowsFromLegacyTable(B, predh, signpred, err, plotInfo, probabilityColumn)
            if isempty(probabilityColumn), probabilityColumn = nan(numel(predh),1); end
            probabilityAvailable = any(isfinite(double(probabilityColumn(:))));
            tmpl = struct('case','','expected','','predicted','','error',false,'score',NaN,'stdScore',NaN,'ensembleProbability',NaN,'percentRank',NaN,'probability',NaN);
            n = min([numel(B.cases), numel(B.labelh), numel(predh), 1000]);
            rows = repmat(tmpl, 1, n);
            gn = NMResultsViewerTools.asStringCell(B.groupnames);
            pr = ranktransform(B.mean_predictions(:));
            probabilityColumn = NMResultsViewerTools.padNumericColumn(double(probabilityColumn(:)), n, NaN);
            for i=1:n
                expected = gn{2}; if B.labelh(i) > 0, expected = gn{1}; end
                predicted = gn{2}; if signpred(i) > 0, predicted = gn{1}; end
                rows(i).case = B.cases{i};
                rows(i).expected = expected;
                rows(i).predicted = predicted;
                rows(i).error = logical(err(i));
                rows(i).score = double(B.mean_predictions(i));
                if numel(B.std_predictions) >= i, rows(i).stdScore = double(B.std_predictions(i)); end
                if size(B.prob_predictions,1) >= i, rows(i).ensembleProbability = double(B.prob_predictions(i,1)); end
                rows(i).percentRank = double(pr(i));
                rows(i).probability = double(probabilityColumn(i));
            end
            keys = {'case','expected','predicted','error','score','stdScore','ensembleProbability','percentRank'};
            labels = {'Case','Observed','Predicted','Error','Mean score','SD','Ens. prob.','% rank'};
            if probabilityAvailable
                keys{end+1} = 'probability';
                labels{end+1} = 'Probability';
            end
            columns = NMResultsViewerTools.tableColumnStruct(keys, labels);
            %#ok<INUSD> plotInfo reserved for later graph-type-specific table labelling.
        end

        function rows = metricRowsFromContingency(c, calibflag, handles)
            tmpl = struct('metric','','value','','source','display_contigmat');
            rows = repmat(tmpl, 1, 0);
            rows = NMResultsViewerTools.appendMetric(rows, 'TP / TN:', '%d / %d', c, {'TP','TN'});
            rows = NMResultsViewerTools.appendMetric(rows, 'FP / FN:', '%d / %d', c, {'FP','FN'});
            rows = NMResultsViewerTools.appendMetric(rows, 'Accuracy [%]:', '%.1f', c, {'acc'});
            rows = NMResultsViewerTools.appendMetric(rows, 'Sensitivity [%]:', '%.1f', c, {'sens'});
            rows = NMResultsViewerTools.appendMetric(rows, 'Specificity [%]:', '%.1f', c, {'spec'});
            rows = NMResultsViewerTools.appendMetric(rows, 'BAC [%]:', '%.1f', c, {'BAC'});
            if isfield(c,'AUC')
                if isfield(c,'AUC_lower') && isfield(c,'AUC_upper')
                    rows(end+1) = struct('metric','AUC (95%-CI):','value',sprintf('%.2f (%.2f-%.2f)', c.AUC, c.AUC_lower, c.AUC_upper),'source','display_contigmat'); %#ok<AGROW>
                else
                    rows(end+1) = struct('metric','AUC:','value',sprintf('%.2f', c.AUC),'source','display_contigmat'); %#ok<AGROW>
                end
            end
            rows = NMResultsViewerTools.appendMetric(rows, 'MCC:', '%.2f', c, {'MCC'});
            rows = NMResultsViewerTools.appendMetric(rows, 'PPV [%]:', '%.1f', c, {'PPV'});
            rows = NMResultsViewerTools.appendMetric(rows, 'NPV [%]:', '%.1f', c, {'NPV'});
            rows = NMResultsViewerTools.appendMetric(rows, 'FPR:', '%.1f', c, {'FPR'});
            rows = NMResultsViewerTools.appendMetric(rows, '+LR:', '%.2f', c, {'pLR'});
            rows = NMResultsViewerTools.appendMetric(rows, '-LR:', '%.2f', c, {'nLR'});
            rows = NMResultsViewerTools.appendMetric(rows, 'PSI:', '%.1f', c, {'PSI'});
            rows = NMResultsViewerTools.appendMetric(rows, 'Youden''s J:', '%.2f', c, {'Youden'});
            rows = NMResultsViewerTools.appendMetric(rows, 'NNP / NND:', '%.1f / %.1f', c, {'NNP','NND'});
            rows = NMResultsViewerTools.appendMetric(rows, 'DOR:', '%.2f', c, {'DOR'});
            if isfield(c,'ECE') && calibflag
                rows = NMResultsViewerTools.appendMetric(rows, 'ECE:', '%.2f', c, {'ECE'});
            end
            if isfield(handles,'PermAnal')
                if handles.PermAnal < 0.001, pvStr = '<0.001'; else, pvStr = sprintf('%.3f', handles.PermAnal); end
                rows(end+1) = struct('metric','Model P value:','value',pvStr,'source','display_contigmat'); %#ok<AGROW>
            end
        end

        function rows = appendMetric(rows, label, fmt, c, fields, idx)
            if nargin < 6 || isempty(idx), idx = 1; end
            for i=1:numel(fields)
                if ~isfield(c, fields{i}), return; end
            end
            vals = cell(1,numel(fields));
            for i=1:numel(fields)
                v = c.(fields{i});
                if isempty(v), return; end
                v = double(v);
                if numel(v) >= idx, vals{i} = v(idx); else, vals{i} = v(1); end
            end
            rows(end+1) = struct('metric',label,'value',sprintf(fmt, vals{:}),'source','display_contigmat'); %#ok<AGROW>
        end

        function roc = rocPayloadFromLegacy(labelh, predh, contingency, trainLabels, trainPredictions)
            roc = struct('ok',false,'points',[],'auc',NaN,'multi',false,'curves',struct([]), ...
                'trainingCurve',struct('ok',false,'points',[],'auc',NaN,'label','Discovery/CV ROC','color','#8a8a8a'), ...
                'message','No ROC payload available.');
            if nargin < 4, trainLabels = []; end
            if nargin < 5, trainPredictions = []; end
            [okMain, pts, auc, msg] = NMResultsViewerTools.rocPointsFromLegacy(labelh, predh);
            if ~okMain
                roc.message = msg;
                return;
            end
            if isfield(contingency,'AUC') && isfinite(double(contingency.AUC)), auc = double(contingency.AUC); end
            roc.ok = true;
            roc.points = pts;
            roc.auc = double(auc);
            roc.message = '';
            [okTrain, trainPts, trainAuc] = NMResultsViewerTools.rocPointsFromLegacy(trainLabels, trainPredictions);
            if okTrain
                roc.trainingCurve = struct('ok',true,'points',trainPts,'auc',double(trainAuc),'label','Discovery/CV ROC','color','#8a8a8a');
            else
                roc.trainingCurve = struct('ok',false,'points',[],'auc',NaN,'label','Discovery/CV ROC','color','#8a8a8a');
            end
        end

        function [ok, pts, auc, msg] = rocPointsFromLegacy(labelh, predh)
            ok = false;
            pts = repmat(struct('fpr',0,'tpr',0), 1, 0);
            auc = NaN;
            msg = 'No ROC payload available.';
            if isempty(labelh) || isempty(predh), return; end
            good = isfinite(labelh(:)) & isfinite(predh(:));
            labelh = labelh(good); predh = predh(good);
            if numel(unique(labelh)) < 2 || numel(predh) < 3
                msg = 'ROC requires at least two observed classes.';
                return;
            end
            try
                [x,y,~,auc] = perfcurve2(labelh, predh, 1);
                n = min(numel(x), numel(y));
                pts = repmat(struct('fpr',0,'tpr',0), 1, n);
                for i=1:n, pts(i).fpr = double(x(i)); pts(i).tpr = double(y(i)); end
                ok = true;
                msg = '';
            catch ME
                msg = ['ROC extraction failed via display_roc/perfcurve2 semantics: ' ME.message];
            end
        end

        function conf = confusionPayloadFromContingency(c, groupnames)
            conf = struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{{}},'message','No confusion matrix available.');
            needed = {'TP','TN','FP','FN'};
            for i=1:numel(needed), if ~isfield(c,needed{i}), return; end, end
            M = [double(c.TP) double(c.FN); double(c.FP) double(c.TN)];
            rowSum = sum(M,2); P = zeros(size(M));
            for r=1:size(M,1)
                if rowSum(r) > 0, P(r,:) = M(r,:) ./ rowSum(r) * 100; end
            end
            gn = NMResultsViewerTools.asStringCell(groupnames);
            conf.ok = true; conf.matrix = M; conf.percentMatrix = P; conf.labels = gn(1:2); conf.message = '';
        end

        function pies = pieChartsPayloadFromContingency(c, labelh, groupnames, colors)
            pies = struct('ok',false,'charts',[],'message','No pre-/post-test probability pie chart payload available.');
            needed = {'pLR','spec','sens'};
            for i=1:numel(needed)
                if ~isfield(c, needed{i}) || isempty(c.(needed{i})) || ~isfinite(double(c.(needed{i})))
                    pies.message = sprintf('Pie chart payload requires contingency field %s.', needed{i});
                    return;
                end
            end
            labelh = double(labelh(:));
            labelh = labelh(isfinite(labelh));
            if isempty(labelh)
                pies.message = 'Pie chart payload requires finite binary labels.';
                return;
            end
            pre1 = sum(labelh == 1) / numel(labelh);
            pre2 = 1 - pre1;
            lr1 = double(c.pLR);
            denom2 = 1 - double(c.sens)/100;
            if abs(denom2) < eps
                lr2 = Inf;
            else
                lr2 = (double(c.spec)/100) / denom2;
            end
            gn = NMResultsViewerTools.asStringCell(groupnames);
            charts = repmat(struct('name','','pre',NaN,'lr',NaN,'lrLabel','','post',NaN,'gain',NaN,'color','','segments',[],'message',''), 1, 2);
            charts(1) = NMResultsViewerTools.singlePiePayload(gn{1}, pre1, lr1, colors.group1, sprintf('+LR %.3f', lr1));
            charts(2) = NMResultsViewerTools.singlePiePayload(gn{2}, pre2, lr2, colors.group2, sprintf('1/-LR %.3f', lr2));
            pies.ok = any(isfinite([charts.post]));
            pies.charts = charts;
            if pies.ok
                pies.message = 'Pre-/post-test probability pie charts extracted from display_piecharts semantics.';
            else
                pies.message = 'Pre-/post-test probabilities could not be computed from the contingency payload.';
            end
        end

        function pie = singlePiePayload(name, pre, lr, color, lrLabel)
            if isempty(lrLabel), lrLabel = sprintf('LR %.3f', lr); end
            post = pre * lr / (1 - pre + pre * lr);
            if ~isfinite(post), post = 1; end
            gain = post - pre;
            segTmpl = struct('label','','value',NaN,'kind','','color','','alpha',1);
            if ~isfinite(post) || isnan(post)
                segs = segTmpl([]);
                msg = 'Post-test probability is not finite.';
            elseif gain > 0
                segs = repmat(segTmpl, 1, 2);
                segs(1) = struct('label',sprintf('Pre\n%1.1f%%', pre*100),'value',double(pre),'kind','pre','color',color,'alpha',0.30);
                segs(2) = struct('label',sprintf('Gain\n%1.1f%%', gain*100),'value',double(gain),'kind','gain','color',color,'alpha',1.00);
                msg = '';
            else
                segs = segTmpl;
                segs(1) = struct('label',sprintf('Pre\n%1.1f%%', pre*100),'value',double(pre),'kind','pre','color',color,'alpha',0.30);
                msg = '';
            end
            pie = struct('name',char(string(name)),'pre',double(pre),'lr',double(lr),'lrLabel',char(lrLabel),'post',double(post),'gain',double(gain),'color',color,'segments',segs,'message',msg);
        end

    end

    methods (Static)
        function scopeContext = reportAnalysisScope(NM,spec)
            if nargin<2 || ~isstruct(spec),spec=struct();end % nm2-allow: report-scope producer accepts omitted optional MATLAB configuration input.
            selected=1;
            if isfield(spec,'AnalysisIndex') && isnumeric(spec.AnalysisIndex) && ~isempty(spec.AnalysisIndex) && ... % nm2-allow: upstream report-scope producer reads optional MATLAB configuration focus once.
                    isfinite(spec.AnalysisIndex(1)), selected=round(double(spec.AnalysisIndex(1)));
            elseif isfield(spec,'analysisIndex') && isnumeric(spec.analysisIndex) && ~isempty(spec.analysisIndex) && ... % nm2-allow: upstream report-scope producer also reads canonical Results Viewer selection once.
                    isfinite(spec.analysisIndex(1)), selected=round(double(spec.analysisIndex(1)));
            end
            raw=struct('Scope','analysis');
            if isfield(spec,'ReportContext') && isstruct(spec.ReportContext), raw=spec.ReportContext; % nm2-allow: upstream report-scope producer receives an optional configuration context.
            elseif isfield(spec,'reportContext') && isstruct(spec.reportContext), raw=spec.reportContext; % nm2-allow: upstream report-scope producer translates the one historical input spelling.
            end
            scope='analysis';
            if isfield(raw,'Scope') && ~isempty(raw.Scope), scope=lower(strtrim(char(string(raw.Scope)))); % nm2-allow: upstream report-scope producer canonicalizes the optional MATLAB mode once.
            elseif isfield(raw,'scope') && ~isempty(raw.scope), scope=lower(strtrim(char(string(raw.scope)))); % nm2-allow: upstream report-scope producer canonicalizes the historical MATLAB mode once.
            end
            if strcmp(scope,'cross_analysis'),scope='multi_analysis';end
            catalogue=NMResultsViewerTools.listAnalyses(NM);
            completed=[catalogue([catalogue.completed]).index];
            switch scope
                case 'analysis'
                    indices=selected;
                case {'analysis_set','multi_analysis'}
                    if ~isfield(raw,'AnalysisIndices'), error('NMResultsViewerReportTools:EmptyAnalysisContext','%s context requires AnalysisIndices.',scope); end % nm2-allow: upstream report-scope producer rejects an incomplete user-selected analysis set.
                    indices=raw.AnalysisIndices;
                case 'nm'
                    indices=completed;
                case 'nm_set'
                    error('NMResultsViewerReportTools:CrossNMContextRequiresCaller','The single-NM Report Builder API cannot resolve an nm_set context; the caller must first select an NM structure.');
                otherwise
                    error('NMResultsViewerReportTools:InvalidReportContext','Unsupported Report Builder context scope %s.',scope);
            end
            indices=NMResultsViewerTools.canonicalCompletedAnalysisSet(catalogue,indices);
            if ~any(indices==selected),selected=indices(1);end
            % One direct-MATLAB ingress projects the documented Report Builder
            % selector spellings into the established typed Results Viewer spec.
            viewerSpec=spec;
            legacyNames={'AnalysisIndex','Source','ModelSource','ClassifierIndex', ...
                'TargetIndex','MultiClassModeIndex','OOCVSubgroupIndex','MeasureId', ...
                'ModalityIndex','FeatureContextId','BackprojectionComponentId', ...
                'ComponentIndex','MaxFeatures','MaxComponents','ResultType'};
            viewerNames={'analysisIndex','source','modelSource','classifierIndex', ...
                'targetIndex','multiClassModeIndex','oocvSubgroupIndex','measureId', ...
                'modalityIndex','featureContextId','backprojectionComponentId', ...
                'componentIndex','maxFeatures','maxComponents','resultType'};
            overridden=false;
            for jj=1:numel(legacyNames)
                if isfield(viewerSpec,legacyNames{jj})
                    viewerSpec.(viewerNames{jj})=viewerSpec.(legacyNames{jj});
                    overridden=true;
                end
            end
            if overridden && isfield(viewerSpec,'canonicalSpecVersion')
                viewerSpec=rmfield(viewerSpec,'canonicalSpecVersion');
            end
            [~,viewerSpec]=NMResultsViewerTools.viewerPlotOptions(viewerSpec);
            viewerSpec.analysisIndex=selected;
            payloadSpec=struct('analysisIndex',selected,'source',viewerSpec.source, ...
                'modelSource',viewerSpec.modelSource,'classifierIndex',viewerSpec.classifierIndex, ...
                'targetIndex',viewerSpec.targetIndex,'multiClassModeIndex',viewerSpec.multiClassModeIndex, ...
                'oocvSubgroupIndex',viewerSpec.oocvSubgroupIndex);
            % Optional public selectors retain their explicit-presence semantics.
            optional={'measureId','modalityIndex','featureContextId', ...
                'backprojectionComponentId','componentIndex','maxFeatures','maxComponents'};
            for jj=1:numel(optional)
                if isfield(spec,optional{jj}) || isfield(spec,legacyNames{jj+7})
                    value=viewerSpec.(optional{jj});
                    % An unselected optional index is absent from the report catalogue schema.
                    if any(strcmp(optional{jj},{'modalityIndex','componentIndex'})) && ...
                            (isempty(value) || isnan(value))
                        continue;
                    end
                    payloadSpec.(optional{jj})=value;
                end
            end
            scopeContext=struct('Scope',scope,'AnalysisIndices',indices, ...
                'SelectedAnalysisIndex',selected,'PayloadSpec',payloadSpec);
        end

        function indices = canonicalCompletedAnalysisSet(catalogue,analysisIndices)
            requested=double(analysisIndices(:)');
            if isempty(requested) || any(~isfinite(requested)) || any(requested<1) || ...
                    any(abs(requested-round(requested))>eps(max(1,abs(requested)))) || ...
                    numel(unique(requested))~=numel(requested)
                error('NMResultsViewerScientificState:InvalidAnalysisSet','Scientific State analysis_set inventory requires unique positive integer analysis ids.');
            end
            completed=[catalogue([catalogue.completed]).index];
            indices=completed(ismember(completed,requested));
            if numel(indices)~=numel(requested)
                error('NMResultsViewerScientificState:InvalidAnalysisSet','Scientific State analysis_set inventory requires explicitly selected completed analyses.');
            end
        end

    end

    methods (Static, Access = private)
        function selected = selectedAnalysisIndex(analyses, spec)
            selected = spec.analysisIndex;
            if ~isnan(selected) && selected >= 1 && selected <= numel(analyses) && analyses(selected).completed
                selected = double(selected); return;
            end
            selected = 0;
            for i = 1:numel(analyses)
                if analyses(i).completed, selected = i; return; end
            end
        end

        function source = selectedSourceId(sources, spec)
            source='cv';
            if isempty(sources),return;end
            ids={sources.id};enabled=[sources.enabled];
            requested=spec.source;
            if ~isempty(requested)
                hit=find(strcmp(ids,requested)&enabled,1,'first');
                if isempty(hit),error('NMResultsViewerTools:InvalidSourceSelection','Source %s is not enabled for the selected result context.',requested);end
                source=ids{hit};return;
            end
            firstEnabled=find(enabled,1,'first');
            if ~isempty(firstEnabled),source=ids{firstEnabled};end
        end

        function payload = attachPayloadSource(payload, source)
            if isempty(source), source = 'cv'; end
            [isOOCVSource, requestedOOCVIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            payload.requestedSource = source;
            payload.selectedSource = source;
            payload.source = source;
            if isOOCVSource
                payload.sourceKind = 'oocv';
                if ~isfield(payload,'oocv') || isempty(payload.oocv) || ~isstruct(payload.oocv)
                    payload.oocv = struct('ok',false,'requestedGlobalIndex',requestedOOCVIndex);
                elseif ~isfield(payload.oocv,'requestedGlobalIndex')
                    payload.oocv.requestedGlobalIndex = requestedOOCVIndex;
                end
            else
                payload.sourceKind = 'cv';
            end
        end

        function payload = enforceOOCVPayloadInvariant(payload, source)
            [isOOCVSource, requestedOOCVIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            if ~isOOCVSource, return; end
            % nm2-allow: classification OOCV payload is an optional result family; when written it carries fixed ok status.
            hasOOCV = isfield(payload,'oocv') && logical(payload.oocv.ok);
            % nm2-allow: classification plot mode is present only when the OOCV violin representation is produced.
            hasOOCVPlot = isfield(payload.classPlot,'mode') && strcmp(payload.classPlot.mode, 'oocv_violin');
            if hasOOCV && hasOOCVPlot
                payload.ok = true;
                payload.oocv.requestedGlobalIndex = requestedOOCVIndex;
                payload.oocv.requestedSource = source;
                return;
            end
            payload.ok = false;
            if isempty(payload.message)
                payload.message = sprintf('OOCV source %s was requested, but no display_classplot_oocv-compatible OOCV violin payload was produced.', source);
            else
                payload.message = sprintf('OOCV source %s was requested, but no display_classplot_oocv-compatible OOCV violin payload was produced. %s', source, payload.message);
            end
            payload.classPlot = struct('ok',false,'points',[],'message',payload.message);
            payload.roc = struct('ok',false,'points',[],'auc',NaN,'message','OOCV plot payload was not produced; ROC is unavailable.');
            payload.confusion = struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{{}},'message','OOCV plot payload was not produced; contingency matrix is unavailable.');
            payload.pies = struct('ok',false,'charts',[],'message','OOCV plot payload was not produced; pie charts are unavailable.');
            payload.scoreRows = [];
            payload.oocv = struct('ok',false,'requestedGlobalIndex',requestedOOCVIndex,'requestedSource',source,'message',payload.message);
        end

        function field = oocvRequiredResultField(resultType)
            kind = NMResultsViewerTools.normalizeResultType(resultType);
            switch kind
                case 'regression'
                    field = 'RegrResults';
                case 'multiclass'
                    field = 'MultiResults';
                case 'mli'
                    field = 'MLI';
                otherwise
                    field = 'BinResults';
            end
        end

        function label = oocvRequiredResultLabel(resultType)
            kind = NMResultsViewerTools.normalizeResultType(resultType);
            switch kind
                case 'classification'
                    label = 'BinResults or binary fields in MultiResults';
                case 'regression'
                    label = 'RegrResults';
                case 'multiclass'
                    label = 'MultiResults';
                otherwise
                    label = NMResultsViewerTools.oocvRequiredResultField(kind);
            end
        end

        function tf = oocvHasResultForKind(entry, resultType)
            if isempty(entry)
                tf = false;
                return;
            end
            kind = NMResultsViewerTools.normalizeResultType(resultType);
            switch kind
                case 'classification'
                    hasBin = isfield(entry,'BinResults') && ~isempty(entry.BinResults); % nm2-allow: nk_OOCVPrep classification writer may produce binary results
                    hasMulti = isfield(entry,'MultiResults') && ~isempty(entry.MultiResults); % nm2-allow: nk_OOCVPrep classification writer may produce multi-group results
                    tf = hasBin || hasMulti;
                case 'regression'
                    % nm2-allow: nk_OOCVPrep writes RegrResults only for regression application
                    tf = isfield(entry,'RegrResults') && ~isempty(entry.RegrResults);
                case 'multiclass'
                    % nm2-allow: nk_OOCVPrep writes MultiResults only for multi-group classification application
                    tf = isfield(entry,'MultiResults') && ~isempty(entry.MultiResults);
                case 'mli'
                    % nm2-allow: MLI application is a separately produced optional result family
                    tf = isfield(entry,'MLI') && ~isempty(entry.MLI);
                otherwise
                    error('NMResultsViewerTools:UnsupportedOOCVResultType', ...
                        'Unsupported OOCV result type: %s.',kind);
            end
        end
        function tf = oocvHasSourceForDropdown(entry, resultType)
            tf = NMResultsViewerTools.oocvHasResultForKind(entry,resultType);
        end
        function descriptors = oocvSourceDescriptors(NM, idx, resultType)
            resultKind = NMResultsViewerTools.normalizeResultType(resultType);
            tmpl = struct('localIndex',0,'globalIndex',0,'descriptor','','desc','','date','', ...
                'nSubjectsAll',0,'labelsKnown',false,'cases',{{}},'label',[]);
            descriptors = repmat(tmpl,1,0);
            % nm2-allow: public Results Viewer selector permits no-analysis state
            if idx < 1 || idx > numel(NM.analysis), return; end
            A = NM.analysis{idx};
            % nm2-allow: nk_OOCVPrep conditionally creates analysis.OOCV only after model application
            if ~isfield(A,'OOCV') || isempty(A.OOCV), return; end
            valid = false(1,numel(A.OOCV));
            for g = 1:numel(A.OOCV)
                valid(g) = NMResultsViewerTools.oocvHasSourceForDropdown(A.OOCV{g},resultKind);
            end
            applied = find(valid);
            if isempty(applied), return; end
            descriptors = repmat(tmpl,1,numel(applied));
            for ii = 1:numel(applied)
                g = applied(ii);
                D = NM.OOCV{g};
                cases = D.cases(:);
                lbl = [];
                labelsKnown = false;
                if logical(A.params.label.altlabelflag)
                    labelName = A.params.label.labelname;
                    % nm2-allow: nk_ManageDataContainers/nk_OOCVPrep conditionally persist and consume the analysis-matched alternative OOCV target
                    if isfield(D,'altlabels') && isfield(D.altlabels,labelName) && ~isempty(D.altlabels.(labelName))
                        lbl = D.altlabels.(labelName);
                        labelsKnown = true;
                    end
                elseif logical(D.labels_known)
                    lbl = D.label;
                    labelsKnown = true;
                end
                if labelsKnown
                    lbl = lbl(:);
                    if numel(lbl) ~= numel(cases)
                        error('NMResultsViewerTools:OOCVEffectiveLabelAxisMismatch', ...
                            'The effective OOCV target must match the committed OOCV case axis.');
                    end
                    lblstr = ', labels known';
                else
                    lblstr = '';
                end
                descriptor = sprintf('%s (<-%s): %g cases%s',D.desc,D.date,double(D.n_subjects_all),lblstr);
                descriptors(ii) = struct('localIndex',ii,'globalIndex',g,'descriptor',descriptor, ...
                    'desc',D.desc,'date',D.date,'nSubjectsAll',double(D.n_subjects_all), ...
                    'labelsKnown',labelsKnown,'cases',{cases},'label',lbl);
            end
        end

        function info = oocvInfoForAnalysis(NM, idx, resultType)
            descriptors = NMResultsViewerTools.oocvSourceDescriptors(NM,idx,resultType);
            info = struct();
            info.searchmode = 'analysis';
            info.AnalVec = idx;
            info.n_AnalCompl = 1;
            info.n_OOCV = numel(descriptors);
            entry = struct();
            entry.num = idx;
            entry.OOCVdone = ~isempty(descriptors);
            entry.OOCVvec = zeros(1,numel(descriptors));
            entry.desc = cell(1,numel(descriptors));
            entry.date = cell(1,numel(descriptors));
            entry.n_subjects_all = zeros(1,numel(descriptors));
            entry.labels_known = false(1,numel(descriptors));
            entry.n_subjects = cell(1,numel(descriptors));
            entry.label = cell(1,numel(descriptors));
            entry.cases = cell(1,numel(descriptors));
            entry.descriptor = cell(1,numel(descriptors));
            for ii = 1:numel(descriptors)
                entry.OOCVvec(ii) = descriptors(ii).globalIndex;
                entry.desc{ii} = descriptors(ii).desc;
                entry.date{ii} = descriptors(ii).date;
                entry.n_subjects_all(ii) = descriptors(ii).nSubjectsAll;
                entry.labels_known(ii) = descriptors(ii).labelsKnown;
                if descriptors(ii).labelsKnown
                    entry.label{ii} = descriptors(ii).label;
                    if strcmp(NM.analysis{idx}.params.label.modeflag,'classification')
                        names = NMResultsViewerTools.groupNamesForAnalysis(NM,idx);
                        entry.n_subjects{ii} = arrayfun(@(g)nnz(descriptors(ii).label == g),1:numel(names));
                    else
                        entry.n_subjects{ii} = nnz(isfinite(descriptors(ii).label));
                    end
                else
                    entry.n_subjects{ii} = [];
                    entry.label{ii} = [];
                end
                entry.cases{ii} = descriptors(ii).cases;
                entry.descriptor{ii} = descriptors(ii).descriptor;
            end
            info.Analyses = cell(1,max(1,idx));
            info.Analyses{idx} = entry;
        end
        function [state,payloads] = scientificStateForAnalysis(NM,idx,spec)
            % scientificStateForAnalysis  Lazily construct the selected analysis/target scientific space.
            doProfile=NMResultsViewerTools.profileEnabled(spec);
            tScientificTotal=tic;
            payloads=struct('performance',struct(),'optimization',struct(),'feature',struct(),'mli',struct());
            % nm2-allow: public Scientific State selector permits the no-analysis state and validates the requested analysis index.
            if idx<1||idx>numel(NM.analysis),state=NMResultsViewerScientificState.fromPayloads({},spec);return;end
            tScientificPhase=tic;
            targets=NMResultsViewerTools.targetOptions(NM,idx);
            targetNativeIdx=NMResultsViewerTools.selectedTargetIndex(targets,spec);
            targetIdx=NMResultsViewerTools.selectedTargetResultIndex(targets,targetNativeIdx);
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]         scientific state target resolution:          %.3fs\n',toc(tScientificPhase));
            tScientificPhase=tic;
            A=NM.analysis{idx};GD=NMResultsViewerTools.primaryGDdims(A);[~,modeflag]=NMResultsViewerTools.analysisLabelAndMode(NM,A);
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]         scientific state analysis/mode resolution:   %.3fs\n',toc(tScientificPhase));
            base=struct('analysisIndex',idx,'targetIndex',targetIdx,'targetNativeIndex',targetNativeIdx,'classifierIndex',1,'source','cv');
            roots={};isRegression=strcmp(modeflag,'regression');
            [hasRegression,~]=NMResultsViewerTools.performanceModelSourceAvailable(GD,'regression');
            [hasBinary,~]=NMResultsViewerTools.performanceModelSourceAvailable(GD,'classification');
            [hasMulticlass,~]=NMResultsViewerTools.performanceModelSourceAvailable(GD,'multiclass');
            tScientificPhase=tic;
            if isRegression
                if hasRegression,perfSpec=base;perfSpec.resultType='regression';payloads.performance=NMResultsViewerTools.getPayload(NM,perfSpec);roots{end+1}=payloads.performance;end %#ok<AGROW>
            else
                assignedPerformance=false;
                if hasBinary
                    perfSpec=base;perfSpec.resultType='classification';payloads.performance=NMResultsViewerTools.getPayload(NM,perfSpec);roots{end+1}=payloads.performance;assignedPerformance=true; %#ok<AGROW>
                end
                if hasMulticlass
                    multiSpec=base;multiSpec.resultType='multiclass';multi=NMResultsViewerTools.getPayload(NM,multiSpec);roots{end+1}=multi; %#ok<AGROW>
                    if ~assignedPerformance,payloads.performance=multi;end
                end
            end
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]         scientific state performance payload(s):     %.3fs\n',toc(tScientificPhase));
            tScientificPhase=tic;
            optSpec=base;optSpec.resultType='model_optimization';payloads.optimization=NMResultsViewerTools.getModelOptimizationPayload(NM,optSpec);roots{end+1}=payloads.optimization;
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]         scientific state optimization payload:       %.3fs\n',toc(tScientificPhase));
            tScientificPhase=tic;
            featureSpec=base;featureSpec.resultType='model_feature_inspection';featureSpec.featureInspectionPayloadScope='metadata';
            payloads.feature=NMResultsViewerTools.getModelFeatureInspectionPayload(NM,featureSpec);roots{end+1}=payloads.feature;
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]         scientific state feature metadata payload:   %.3fs\n',toc(tScientificPhase));
            tScientificPhase=tic;
            state=NMResultsViewerScientificState.fromPayloads(roots,base);
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]         scientific state fromPayloads boundary:      %.3fs\n',toc(tScientificPhase));
            tScientificPhase=tic;
            state.featureNamespace=NMResultsViewerScientificState.featureNamespaceForAnalysis(NM,idx,payloads.feature);
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]         scientific state feature namespace boundary: %.3fs\n',toc(tScientificPhase));
            NMResultsViewerTools.profileLog(doProfile,'[nm-prof]       scientific state construction TOTAL:          %.3fs\n',toc(tScientificTotal));
        end

        function idx = selectedTargetIndex(opts, spec)
            % selectedTargetIndex  Resolve native scientific target identity from the fixed target catalogue.
            idx=1;
            if isempty(opts),return;end
            enabled=[opts.enabled];nativeValues=[opts.index];resultValues=[opts.resultIndex];
            nativeCandidate=spec.targetNativeIndex;
            resultCandidate=spec.targetIndex;
            if ~isnan(nativeCandidate)
                cand=double(nativeCandidate);
                if ~isscalar(cand)||~isfinite(cand)||cand<1||cand~=round(cand),error('NMResultsViewerTools:InvalidTargetSelection','targetNativeIndex must be one finite positive integer.');end
                hit=find(nativeValues==cand&enabled,1,'first');
                if isempty(hit),error('NMResultsViewerTools:InvalidTargetSelection','Native target %d is not enabled for the selected analysis.',cand);end
                idx=nativeValues(hit);return;
            end
            if ~isnan(resultCandidate)
                cand=double(resultCandidate);
                if ~isscalar(cand)||~isfinite(cand)||cand<1||cand~=round(cand),error('NMResultsViewerTools:InvalidTargetSelection','targetIndex must be one finite positive integer.');end
                hit=find(resultValues==cand&enabled,1,'first');
                if isempty(hit),error('NMResultsViewerTools:InvalidTargetSelection','Compact target position %d is not enabled for the selected analysis.',cand);end
                idx=nativeValues(hit);return;
            end
            hit=find(enabled,1,'first');
            if ~isempty(hit),idx=nativeValues(hit);else,idx=nativeValues(1);end
        end

        function idx = selectedTargetResultIndex(opts, nativeIndex)
            % selectedTargetResultIndex  Map scientific/native target identity to compact result position.
            idx = 1;
            if ~isstruct(opts) || isempty(opts), return; end
            cand=double(nativeIndex);
            if ~isscalar(cand)||~isfinite(cand)||cand<1||cand~=round(cand), error('NMResultsViewerTools:InvalidTargetSelection','Native target identity must be one finite positive integer.'); end
            hit = find([opts.index] == cand & [opts.enabled], 1, 'first');
            if isempty(hit), error('NMResultsViewerTools:InvalidTargetSelection','Native target %d has no enabled compact material position.',cand); end
            candidate = double(opts(hit).resultIndex);
            if ~isscalar(candidate)||~isfinite(candidate)||candidate<1||candidate~=round(candidate), error('NMResultsViewerTools:InvalidTargetSelection','Native target %d has an invalid compact material position.',cand); end
            idx = candidate;
        end

        function [names,nativeIdx] = analysisTargetLabelNames(NM,A,n,selectedColumns)
            % analysisTargetLabelNames  Project the writer-defined analysis target name contract.
            n=max(1,round(double(n)));
            nativeIdx=1:n;
            if ~isempty(selectedColumns)
                if numel(selectedColumns)~=n,error('NMResultsViewerTools:InvalidAnalysisLabelContract','Effective target selection has %d native indices for %d material target columns.',numel(selectedColumns),n);end
                nativeIdx=double(selectedColumns(:)).';
            end
            L=A.params.label;
            if logical(L.altlabelflag)
                labs=NMResultsViewerTools.anyToCellstr(L.labelname);
            elseif n>1||~isempty(selectedColumns)
                labs=NMResultsViewerTools.anyToCellstr(NM.labelnames);
                if numel(labs)<max(nativeIdx),error('NMResultsViewerTools:InvalidAnalysisLabelContract','NM.labelnames cannot represent the selected native target indices.');end
                labs=labs(nativeIdx);
            else
                labs=NMResultsViewerTools.anyToCellstr(L.labelname);
            end
            if numel(labs)<n,labs(end+1:n)={''};end
            names=cell(1,n);
            for ii=1:n
                txt=strtrim(labs{ii});
                if isempty(txt),names{ii}=sprintf('Target %d',nativeIdx(ii));else,names{ii}=txt;end
            end
        end

        function [analyzedIdx, resultIdx, disabledReason] = analysisTargetIndexMap(~, GD, label, modeflag)
            % analysisTargetIndexMap  Map effective analysis-local targets to result columns.
            %
            % The caller supplies the effective target matrix solely for selector
            % mapping. Result target dimensions use compact positions 1..N; native
            % label identity is provenance and must not be applied a second time.
            disabledReason = '';
            n = 1;
            if isnumeric(label) && ~isempty(label), n = size(label,2); end
            n = max(1,n);
            analyzedIdx = 1:n;
            resultIdx = 1:n;
            resultKind = NMResultsViewerTools.resultKindFromModeAndGD(modeflag,GD);
            predCols = NMResultsViewerTools.resultTargetColumnCount(GD,resultKind);
            if predCols>0 && predCols<n
                analyzedIdx=1:predCols; resultIdx=1:predCols;
                disabledReason=sprintf('The result container exposes %d target column(s), not all %d effective analysis targets.',predCols,n);
            end
        end

        function [targetLabel, legacyTargetIdx, targetGD, ok, msg] = legacyTargetLabelMatrix(~, GD, label, targetIdx, resultKind, ~)
            % legacyTargetLabelMatrix  Pass the resolved analysis-local target contract to load_GDdims.
            targetLabel=label; targetGD=GD; ok=true; msg='';
            if ~isnumeric(label)||isempty(label)
                ok=false;msg='No numeric label matrix is available for the selected target.';legacyTargetIdx=1;return;
            end
            n=size(label,2); legacyTargetIdx=max(1,min(round(double(targetIdx)),n));
            predCols=NMResultsViewerTools.resultTargetColumnCount(GD,NMResultsViewerTools.normalizeResultType(resultKind));
            if predCols>0 && legacyTargetIdx>predCols
                ok=false;msg=sprintf('Target position %d exceeds the %d target column(s) available in the result container.',legacyTargetIdx,predCols);
            end
        end

        function sel = multiLabelSelection(A,n)
            % multiLabelSelection  Validate the writer-defined native MULTILABEL target selection.
            sel=[];TP=A.params.TrainParam;
            % nm2-allow: nk_TrainClass_config removes TrainParam.MULTILABEL for single-target or active alternative-label analyses.
            if ~isfield(TP,'MULTILABEL')
                if n>1,error('NMResultsViewerTools:MissingMultiLabelSelection','A native multi-target analysis is missing analysis.params.TrainParam.MULTILABEL.');end
                return;
            end
            v=double(TP.MULTILABEL.sel(:)).';
            if any(~isfinite(v)|v<1|v~=round(v)|v>n),error('NMResultsViewerTools:InvalidMultiLabelSelection','analysis.params.TrainParam.MULTILABEL.sel contains invalid native target indices.');end
            if numel(unique(v))~=numel(v),error('NMResultsViewerTools:InvalidMultiLabelSelection','analysis.params.TrainParam.MULTILABEL.sel contains duplicate native target indices.');end
            sel=v;
        end

        function kind = resultKindFromModeAndGD(modeflag, GD)
            % resultKindFromModeAndGD  Infer the active result family for target mapping.
            kind = 'classification';
            if isstruct(GD) && isfield(GD,'Regr') && ~isempty(GD.Regr)
                if strcmpi(char(string(modeflag)), 'regression') || ~isfield(GD,'BinClass')
                    kind = 'regression';
                    return;
                end
            end
            if isstruct(GD) && isfield(GD,'MultiClass') && ~isempty(GD.MultiClass)
                kind = 'multiclass';
            end
        end

        function n = resultTargetColumnCount(GD, resultKind)
            % resultTargetColumnCount  Count target columns available in a GDdims result container.
            n = 0;
            if ~isstruct(GD), return; end
            switch resultKind
                case 'regression'
                    if isfield(GD,'Regr') % nm2-allow: nk_MLOptimizer writes Regr only for completed regression output.
                        n = NMResultsViewerTools.numericColumnCountFromStruct(GD.Regr, {'mean_predictions','std_predictions','R2','r','p'});
                    end
                case 'multiclass'
                    if isfield(GD,'MultiClass') % nm2-allow: nk_MLOptimizer writes MultiClass only for completed multigroup output.
                        n = NMResultsViewerTools.numericColumnCountFromStruct(GD.MultiClass, {'multi_predictionsCV2','multi_probabilitiesCV2'});
                    end
                otherwise
                    if isfield(GD,'BinClass') && ~isempty(GD.BinClass) % nm2-allow: nk_MLOptimizer writes BinClass only for admitted binary-classifier results.
                        n = NMResultsViewerTools.numericColumnCountFromStruct(GD.BinClass{1}, {'mean_predictions','std_predictions','prob_finalpred'});
                    end
            end
        end

        function n = numericColumnCountFromStruct(S, fieldNames)
            % numericColumnCountFromStruct  Read the admitted optimizer result struct.
            n = 0;
            for ii = 1:numel(fieldNames)
                f = fieldNames{ii};
                if ~isfield(S, f) || isempty(S.(f)) || ~(isnumeric(S.(f)) || islogical(S.(f))), continue; end
                n = NMResultsViewerTools.numericTargetColumnCount(S.(f));
                if n > 0, return; end
            end
        end

        function n = numericTargetColumnCount(raw)
            % numericTargetColumnCount  Infer the number of target columns in one numeric result array.
            n = 0;
            if isempty(raw) || ~(isnumeric(raw) || islogical(raw)), return; end
            sz = size(raw);
            if numel(sz) >= 3 && sz(3) > 1
                n = sz(3);
            elseif numel(sz) >= 2
                % Legacy subject-level predictions use N-by-target storage. A
                % column vector is therefore one target; a row vector or matrix
                % exposes the second dimension.
                n = sz(2);
            else
                n = numel(raw);
            end
            n = max(0, round(double(n)));
        end

        function x = resultTargetVector(raw, targetIdx)
            % resultTargetVector  Extract one compact target from a legacy result vector/matrix.
            %
            % Legacy result containers may retain all compact targets as N-by-target
            % or N-by-1-by-target arrays, while load_GDdims may already reduce a field
            % to one target. A single-target field is therefore consumed directly;
            % multi-target fields are sliced by the compact material coordinate.
            if isempty(raw), x=[]; return; end
            targetIdx=max(1,round(double(targetIdx))); nTargets=NMResultsViewerTools.numericTargetColumnCount(raw);
            if nTargets>1 && targetIdx>nTargets, error('NMResultsViewerTools:InvalidTargetSelection', ...
                    'Compact target %d exceeds the %d target column(s) in a legacy result field.',targetIdx,nTargets); end
            if nTargets>1
                if ndims(raw)>=3 && size(raw,3)>1, raw=raw(:,:,targetIdx); else, raw=raw(:,targetIdx); end
            end
            x=NMResultsViewerTools.asColumnDouble(raw);
        end

        function info = featureQCReferenceInfo(referenceMode, isOOCVSource, oocvIndex, modIdx)
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end



            if logical(isOOCVSource)
                if isfinite(double(oocvIndex))
                    subjectSource = sprintf('OOCV/application dataset %d', round(double(oocvIndex)));
                else
                    subjectSource = 'OOCV/application dataset';
                end
                modeLabel = 'fixed training/CV reference';
                msg = 'This OOCV/application map is computed against the training/CV QC reference. OOCV subjects are not used to estimate the reference mean or variance.';
            else
                subjectSource = 'training/CV dataset';
                modeLabel = 'leave-one-out training/CV reference';
                msg = 'This training/CV map is computed against the training/CV QC reference after leaving the selected subject out of the reference statistics.';
            end
            if isfinite(double(modIdx))
                referenceSource = sprintf('training/CV QC reference, modality %d', round(double(modIdx)));
            else
                referenceSource = 'training/CV QC reference';
            end
            info = struct('subjectSource',subjectSource, 'referenceSource',referenceSource, ...
                'referenceMode',modeLabel, 'message',msg, 'warning','');
        end

        function [ok, msg, warning] = featureQCReferenceCompatibility(refQC, refDD, subjectDD, isOOCVSource)
            % featureQCReferenceCompatibility  Verify training/OOCV feature-space compatibility from authoritative descriptors.
            %
            % Canonical ROI provenance overrides stale QC-cache feature-space labels on both sides.
            % This is metadata-only and performs no source, atlas, annotation, or feature materialization.
            ok = true;
            msg = '';
            warning = '';
            if ~logical(isOOCVSource), return; end
            targetQC = NMResultsViewerTools.qcPayloadFromDescriptor(subjectDD);
            if ~isstruct(targetQC) || isempty(fieldnames(targetQC))
                warning = ['No persisted OOCV/application QC payload was found for this modality. ' ...
                    'The selected subject can still be scored from its data file against the training/CV reference, but OOCV QC sidecar status could not be verified.'];
                return;
            end
            refSpace = NMResultsViewerTools.featureQCFeatureSpace(refQC, refDD);
            targetSpace = NMResultsViewerTools.featureQCFeatureSpace(targetQC, subjectDD);
            if ~isempty(refSpace) && ~isempty(targetSpace) && ~strcmpi(refSpace, targetSpace)
                ok = false;
                msg = sprintf(['Feature-level QC cannot be shown because the OOCV/application QC sidecar describes feature space "%s", ' ...
                    'whereas the training/CV QC reference describes "%s". Export QC for matching training and OOCV modalities.'], targetSpace, refSpace);
                return;
            end
            refN = NMResultsViewerTools.featureQCNFeatures(refQC);
            targetN = NMResultsViewerTools.featureQCNFeatures(targetQC);
            if isfinite(refN) && isfinite(targetN) && refN > 0 && targetN > 0 && round(refN) ~= round(targetN)
                ok = false;
                msg = sprintf(['Feature-level QC cannot be shown because the OOCV/application QC sidecar has %d features, ' ...
                    'whereas the training/CV QC reference has %d features. The training and OOCV modalities must use the same feature space.'], round(targetN), round(refN));
                return;
            end
        end

        function qc = qcPayloadFromDescriptor(dd)
            qc = struct();
            % nm2-allow: NMDataIOUI.saveInspectionArtifactsToNM writes QC.payload only when QC was saved; report-only QC is legitimate.
            if isstruct(dd) && isfield(dd,'QC') && isstruct(dd.QC) && ...
                    isfield(dd.QC,'payload') && isstruct(dd.QC.payload) % nm2-allow: NMDataIOUI persists QC.payload only when a QC run was saved; report-only QC is valid.
                qc = dd.QC.payload;
                if strcmp(qc.sourceType, 'connectivity')
                    % A browser-only reference is not a materialized scientific QC array.
                    c = qc.connectivity;
                    if NMConfigTools.isArrayRef(c.edgeIndex) || ...
                            NMConfigTools.isArrayRef(c.edgeMean) || ...
                            NMConfigTools.isArrayRef(c.edgeSD) || ...
                            NMConfigTools.isArrayRef(c.edgeMissingRate)
                        error('NMResultsViewerTools:UnmaterializedConnectivityQC', ...
                            ['Saved connectivity QC contains browser-only array references rather than numeric edge data. ' ...
                             'Recompute and save connectivity QC with the corrected DataIO persistence path.']);
                    end
                end
            end
        end

        function fs = featureQCFeatureSpace(qc, dd)
            % Declared ROI provenance owns feature-domain identity even when
            % its spatial materialization later fails validation. All other
            % admitted QC payloads use the DataIO producer's featureSpace.
            if NMDataIOROIProvenanceTools.declaredInDescriptor(dd)
                fs = 'roi_field';
            else
                fs = qc.featureSpace;
            end
        end

        function n = featureQCNFeatures(qc)
            % An admitted DataIO QC payload always has its canonical feature count.
            n = double(qc.nFeatures);
        end

        function [subjectNM, subjectDD, rowIdx, msg] = resolveOOCVSubjectFeatureQCTarget(NM, modIdx, oocvIndex, caseId)
            subjectNM = struct();
            subjectDD = struct();
            rowIdx = NaN;
            msg = '';
            [subjectNM, subjectDD, containerMsg] = NMResultsViewerTools.oocvContainerModalityDescriptor(NM, modIdx, oocvIndex);
            if ~isempty(containerMsg)
                msg = containerMsg;
                return;
            end
            [rowIdx, matchedBy, duplicateMsg] = NMResultsViewerTools.caseIndexInContainerByUniqueId(subjectNM, caseId);
            if isempty(rowIdx) || ~isfinite(double(rowIdx)) || rowIdx < 1
                rowIdx = NaN;
                if ~isempty(duplicateMsg)
                    msg = duplicateMsg;
                else
                    msg = sprintf(['The selected OOCV/application subject (%s) could not be matched to the OOCV QC data or subject file list. ' ...
                        'Matching uses the unique subject ID; no visual-order fallback was used.'], char(string(caseId)));
                end
                return;
            end
            msg = sprintf('OOCV/application subject matched by %s. Feature-level QC z-scores use the training/CV reference.', matchedBy);
        end

        function [D, dd, msg] = oocvContainerModalityDescriptor(NM, modIdx, oocvIndex)
            D = struct();
            dd = struct();
            msg = '';
            if ~isstruct(NM) || ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || ...
                    oocvIndex < 1 || oocvIndex > numel(NM.OOCV) || ~isstruct(NM.OOCV{oocvIndex})
                msg = sprintf('The selected OOCV/application dataset could not be resolved for feature-level QC.');
                return;
            end
            D = NM.OOCV{oocvIndex};
            if isfield(D,'datadescriptor') && iscell(D.datadescriptor) && modIdx >= 1 && modIdx <= numel(D.datadescriptor) && isstruct(D.datadescriptor{modIdx})
                dd = D.datadescriptor{modIdx};
            elseif isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && modIdx >= 1 && modIdx <= numel(NM.datadescriptor) && isstruct(NM.datadescriptor{modIdx})
                dd = NM.datadescriptor{modIdx};
            else
                msg = sprintf('The selected OOCV/application dataset has no matching modality descriptor for the analysis-bound modality.');
            end
        end

        function ids = canonicalQCCaseIdsForContainer(D, modIdx, qc)
            ids = {};
            qcIds = NMResultsViewerTools.qcCaseIds(qc);
            n = numel(qcIds);
            if n == 0
                n = NMResultsViewerTools.containerCaseCount(D, modIdx);
            end
            canonical = NMResultsViewerTools.containerCanonicalCases(D);
            if ~isempty(canonical) && (n == 0 || numel(canonical) == n) && numel(unique(canonical)) == numel(canonical)
                ids = canonical(:);
                return;
            end
            if ~isempty(qcIds)
                ids = qcIds(:);
            end
        end

        function n = containerCaseCount(D, modIdx)
            n = 0;
            if ~isstruct(D), return; end
            if isfield(D,'cases') && ~isempty(D.cases)
                ids = NMResultsViewerTools.anyToCellstr(D.cases);
                n = numel(ids);
                if n > 0, return; end
            end
            files = NMResultsViewerTools.modalityAllSubjectFiles(D, struct(), modIdx, {'files','imageFiles','surfaceFiles','P','PP'});
            n = numel(files);
        end

        function ids = containerCanonicalCases(D)
            ids = {};
            if isstruct(D) && isfield(D,'cases') && ~isempty(D.cases)
                ids = NMResultsViewerTools.anyToCellstr(D.cases);
                ids = ids(:);
            end
        end

        function [rowIdx, matchedBy, duplicateMsg] = caseIndexInContainerByUniqueId(D, caseId)
            % NMDataIOImportTools commits NM.OOCV{o}.cases as the canonical OOCV subject axis.
            % Never select another scientific row from descriptor aliases or file basenames.
            rowIdx = NaN;
            matchedBy = '';
            duplicateMsg = '';
            id = char(string(caseId));
            if isempty(id), return; end
            ids = NMResultsViewerTools.containerCanonicalCases(D);
            matches = find(strcmp(ids(:), id));
            if numel(matches) == 1
                rowIdx = matches;
                matchedBy = 'NM.OOCV canonical subject ID';
            elseif numel(matches) > 1
                duplicateMsg = sprintf('Subject ID %s matched %d rows in NM.OOCV canonical subject ID; strict unique-ID matching was aborted.', id, numel(matches));
            end
        end

        function files = modalityAllSubjectFiles(NM, dd, modIdx, fieldNames)
            files = {};
            candidates = NMResultsViewerTools.modalityFileCandidates(NM, dd, modIdx, fieldNames);
            for ii = 1:numel(candidates)
                files = NMResultsViewerTools.pathListCellstr(candidates{ii});
                if ~isempty(files), return; end
            end
        end

        function [qc, message] = rehydrateSubjectSpatialQC(qc, tmpDir, failurePrefix)
            % DataIO owns QC-cache rehydration; each admitted spatial view consumes the same operation.
            try
                [qc, messages] = NMDataIOFeatureQCTools.rehydrateViewerOverlayCache(qc, tmpDir);
                message = NMResultsViewerTools.messageArrayText(messages);
            catch ME
                message = sprintf('%s: %s', failurePrefix, ME.message);
            end
        end

        function out = subjectROIFeatureQCOverlay(NM, qc, modIdx, rowIdx, spec, tmpDir, referenceMode)
            % subjectROIFeatureQCOverlay  Prepare spatial and numerical ROI QC from resident canonical state.
            %
            % Purpose:
            %   Serve the existing Results Viewer subject Feature-level deviations workspace for an
            %   ROI modality by expanding one canonical ROI z-score vector through its resident volumetric
            %   atlas or surface annotation and attaching an exact ranked numerical ROI table.
            %
            % Authority and flow:
            %   Analysis-bound NM.Y supplies the selected subject ROI vector. Persisted training/CV
            %   QC moments supply the reference distribution. The DataIO ROI-QC sidecar supplies canonical
            %   ROI identity plus the resident labelled atlas or annotation-labelled surface. No raw ROI source is reopened here.
            %
            % Scientific/state contract:
            %   Training/CV subjects use leave-one-out reference moments; OOCV subjects use the fixed
            %   training/CV reference. ROI IDs and names are those of the canonical training feature
            %   space, preserving the trained column order for OOCV/application data.
            %
            % Materialization and performance:
            %   Interactive-safe. May rehydrate/copy one already persisted QC sidecar into the active
            %   browser session, then performs only in-memory ROI z-scoring and exact atlas/annotation
            %   expansion. Volumetric anatomy is the display-only structural field sampled during
            %   explicit QC materialization. It does not parse CAT12/XML, reopen atlas/annotation, load
            %   the structural template, call prepareROIImportState, atlasNodeCoordinates, or CheckTabFile.
            %
            % Inputs/outputs and consumers:
            %   NM/qc identify the selected analysis subject and persisted QC reference; spec supplies
            %   metric/slice controls. Returns the existing image_qc_overlay or surface_qc_overlay contract
            %   plus a ranked numerical ROI table for the Feature-level deviations workspace.
            %
            % Failure semantics and side effects:
            %   Missing/incompatible resident QC state is explicit; no spatial identity is guessed or
            %   reconstructed from feature names. Only ephemeral browser overlay transport is written.
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            emptyStruct = struct();
            out = struct('ok',false,'message','ROI feature-level QC overlay was not prepared.', ...
                'viewerKind','','featureSpace','roi_field','metricKey','subject_z', ...
                'metricLabel','Subject ROI z-score','metricOptions',[],'source','', ...
                'referenceMode',referenceMode,'volume',emptyStruct,'mesh',emptyStruct,'overlay',emptyStruct, ...
                'rows',[],'columns',[],'nReturned',0);
            if exist('NMDataIOFeatureQCTools','class') ~= 8
                out.message = 'ROI feature-level QC cannot be shown because NMDataIOFeatureQCTools is unavailable on the MATLAB path.';
                return;
            end
            [qc, rehydrateMessage] = NMResultsViewerTools.rehydrateSubjectSpatialQC( ...
                qc, tmpDir, 'ROI feature-level QC sidecar could not be prepared for viewing');
            cacheToken = qc.viewerOverlay.cacheToken;
            if isempty(cacheToken)
                out.message = 'ROI feature-level QC viewer materialization has no cache token. Recompute and save ROI QC in DataIO first.';
                return;
            end
            [z, rawVec, vectorSource, vectorMessage] = NMResultsViewerTools.subjectFeatureQCVectorFromModality(NM, qc, modIdx, rowIdx, tmpDir, referenceMode);
            if isempty(z)
                out.message = vectorMessage;
                if ~isempty(rehydrateMessage), out.message = strtrim([out.message ' ' rehydrateMessage]); end
                return;
            end
            metricKey = spec.metricKey;
            if ~strcmpi(metricKey,'subject_z')
                out.message = sprintf('ROI spatial QC currently supports the subject_z metric; requested metric was %s.', metricKey);
                return;
            end
            opts = struct('tmpDir',tmpDir,'metricKey','subject_z','metricLabel','Subject ROI z-score', ...
                'overlayKind','subject_z','zThreshold',spec.zThreshold, ...
                'sliceIndex',spec.sliceIndex);
            spatial = NMDataIOFeatureQCTools.prepareROIViewerPayload(cacheToken,z,opts);
            if ~logical(spatial.ok)
                out.message = spatial.message;
                if ~isempty(rehydrateMessage), out.message = strtrim([out.message ' ' rehydrateMessage]); end
                return;
            end
            roiIDs = double(spatial.roiIDs);
            roiNames = spatial.roiNames;
            if numel(roiIDs) ~= numel(z) || numel(roiNames) ~= numel(z)
                out.message = 'Resident ROI atlas expansion returned canonical ROI metadata incompatible with the subject ROI vector.';
                return;
            end
            zColumn = double(z(:));
            rawColumn = double(rawVec(:));
            finite = find(isfinite(zColumn));
            [~,ord] = sortrows([-abs(zColumn(finite)) double(finite)],[1 2]);
            keep = finite(ord);
            maxFeatures = spec.maxFeatures;
            maxFeatures = max(20,min(2000,round(maxFeatures)));
            keep = keep(1:min(numel(keep),maxFeatures));
            rowTmpl = struct('rank',NaN,'roiId',NaN,'roi','','z',NaN,'absZ',NaN,'value',NaN);
            rows = repmat(rowTmpl,1,numel(keep));
            for ii = 1:numel(keep)
                fi = keep(ii);
                rows(ii) = struct('rank',double(ii),'roiId',double(roiIDs(fi)),'roi',roiNames{fi}, ...
                    'z',double(zColumn(fi)),'absZ',double(abs(zColumn(fi))),'value',double(rawColumn(fi)));
            end
            out.ok = true;
            out.metricKey = 'subject_z';
            out.metricLabel = 'Subject ROI z-score';
            out.metricOptions = NMResultsViewerTools.featureQCMetricOptions(qc,'roi_field');
            family = lower(spatial.representationFamily);
            if strcmp(family,'volume')
                out.viewerKind = 'image_qc_overlay';
                out.volume = spatial.volume;
            elseif strcmp(family,'surface')
                out.viewerKind = 'surface_qc_overlay';
                out.mesh = spatial.mesh;
            else
                out.ok = false;
                out.message = 'Resident ROI spatial materialization did not resolve to the volumetric or surface viewer family.';
                return;
            end
            out.overlay = spatial.overlay;
            out.rows = rows;
            out.columns = NMResultsViewerTools.tableColumnStruct({'rank','roiId','roi','z','absZ','value'}, ...
                {'Rank','ROI ID','ROI','z','|z|','Value'});
            out.nReturned = double(numel(keep));
            out.source = vectorSource;
            spatialLabel = 'canonical ROI spatial reference';
            if strcmp(family,'volume'), spatialLabel = 'resident canonical ROI atlas';
            elseif strcmp(family,'surface'), spatialLabel = 'resident canonical surface annotation and mesh'; end
            if strcmpi(referenceMode,'fixed_reference')
                out.source = sprintf('%s with fixed training/CV QC reference',spatialLabel);
            else
                out.source = sprintf('%s with leave-one-out training/CV QC reference',spatialLabel);
            end
            out.message = sprintf('Prepared exact %s spatial ROI QC for %g canonical parcel(s).',family,numel(roiIDs));
            if ~isempty(rehydrateMessage), out.rehydrateMessage = rehydrateMessage; end
        end

        function out = subjectImageFeatureQCOverlay(NM, dd, qc, modIdx, rowIdx, spec, tmpDir, referenceMode)
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            emptyStruct = struct();
            out = struct('ok',false, 'message','Image feature-level QC overlay was not prepared.', ...
                'viewerKind','image_qc_overlay', 'featureSpace','image_voxel', 'metricKey','subject_z', ...
                'source','', 'metricOptions',[], 'metricLabel','', 'volume',emptyStruct, 'overlay',emptyStruct, 'nReturned',0, 'rows',[], 'columns',[]);
            if exist('NMDataIOFeatureQCTools','class') ~= 8 || exist('NMDataIOImagePreviewTools','class') ~= 8
                out.message = 'Image feature-level QC cannot be shown because the required DataIO image/QC utilities are not available on the MATLAB path.';
                return;
            end
            [qc, rehydrateMessage] = NMResultsViewerTools.rehydrateSubjectSpatialQC( ...
                qc, tmpDir, 'Feature-level QC sidecar could not be prepared for viewing');
            cacheToken = qc.viewerOverlay.cacheToken;
            if isempty(cacheToken)
                out.message = 'Image feature-level QC viewer cache has no cache token. Export the QC sidecar from DataIO first.';
                return;
            end
            imageFile = NMResultsViewerTools.modalitySubjectFile(NM, dd, modIdx, rowIdx, {'imageFiles','files','P','PP'});
            if isempty(imageFile)
                out.message = sprintf('Could not resolve the image file for matched subject row %g in modality %d.', rowIdx, modIdx);
                return;
            end
            maskFile = qc.maskFile;
            if isempty(maskFile)
                out.message = sprintf('Could not resolve the brainmask/atlas file for modality %d.', modIdx);
                return;
            end
            metricKey = spec.metricKey;
            zThreshold = spec.zThreshold;
            sliceIndex = spec.sliceIndex;
            opts = struct();
            opts.tmpDir = tmpDir;
            opts.metricKey = metricKey;
            opts.zThreshold = zThreshold;
            opts.sliceIndex = sliceIndex;
            opts.ReferenceMode = referenceMode;
            % NMDataIOImportTools.persistInputSettings writes spaceDefType for current
            % imaging imports; inherited NM1.4 descriptors predate this field.
            opts.spaceDefType = 'brainmask';
            % nm2-allow: DataIO's persisted spaceDefType is the generation marker, inherited TransferModality2NM omits it
            if isfield(dd.input_settings,'spaceDefType')
                opts.spaceDefType = dd.input_settings.spaceDefType;
            end
            try
                vol = NMDataIOImagePreviewTools.prepareAxialVolume(imageFile, maskFile, opts);
                if ~logical(vol.ok)
                    out.message = vol.message;
                    if ~isempty(rehydrateMessage), out.rehydrateMessage = rehydrateMessage; end
                    return;
                end
                if ~isfinite(sliceIndex) && ~isempty(vol.sliceIndex)
                    opts.sliceIndex = double(vol.sliceIndex);
                end
                overlay = NMDataIOFeatureQCTools.prepareImageViewerQCOverlay(imageFile, maskFile, cacheToken, opts);
                if ~logical(overlay.ok)
                    out.message = overlay.message;
                    if ~isempty(rehydrateMessage), out.rehydrateMessage = rehydrateMessage; end
                    return;
                end
                out.ok = true;
                out.metricKey = overlay.metricKey;
                out.metricLabel = overlay.metricLabel;
                out.metricOptions = NMResultsViewerTools.featureQCMetricOptions(qc, 'image_voxel');
                if strcmpi(referenceMode, 'fixed_reference')
                    out.source = 'DataIO imaging QC sidecar, prepared on demand against the training/CV reference';
                    out.referenceMode = 'fixed_reference';
                else
                    out.source = 'DataIO imaging QC sidecar, prepared on demand';
                    out.referenceMode = 'leave_one_out';
                end
                out.volume = vol;
                out.overlay = overlay;
                out.nReturned = double(overlay.validFeatureCount);
                out.message = sprintf('Prepared subject-specific image QC overlay for matched row %g.', rowIdx);
                if ~isempty(rehydrateMessage), out.rehydrateMessage = rehydrateMessage; end
            catch ME
                out.ok = false;
                out.message = sprintf('Feature-level QC could not be prepared: %s', ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
            end
        end

        function out = subjectSurfaceFeatureQCOverlay(NM, dd, qc, modIdx, rowIdx, spec, tmpDir, referenceMode)
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            emptyStruct = struct();
            out = struct('ok',false, 'message','Surface feature-level QC overlay was not prepared.', ...
                'viewerKind','surface_qc_overlay', 'featureSpace','surface_vertex_registered', 'metricKey','subject_z', ...
                'source','', 'referenceMode',referenceMode, 'metricOptions',[], 'metricLabel','', ...
                'mesh',emptyStruct, 'overlay',emptyStruct, 'nReturned',0, 'rows',[], 'columns',[]);
            if exist('NMDataIOFeatureQCTools','class') ~= 8 || exist('NMDataIOSurfaceTools','class') ~= 8
                out.message = 'Surface feature-level QC cannot be shown because the required DataIO surface/QC utilities are not available on the MATLAB path.';
                return;
            end
            [qc, rehydrateMessage] = NMResultsViewerTools.rehydrateSubjectSpatialQC( ...
                qc, tmpDir, 'Feature-level QC sidecar could not be prepared for viewing');
            cacheToken = qc.viewerOverlay.cacheToken;
            if isempty(cacheToken)
                out.message = 'Surface feature-level QC viewer cache has no cache token. Export the QC sidecar from DataIO first.';
                return;
            end
            surfaceFile = NMResultsViewerTools.modalitySubjectFile(NM, dd, modIdx, rowIdx, {'surfaceFiles','surfaceScalarFiles','imageFiles','files','P','PP'});
            if isempty(surfaceFile)
                out.message = sprintf('Could not resolve the surface scalar file for matched subject row %g in modality %d.', rowIdx, modIdx);
                return;
            end
            geometryFile = NMResultsViewerTools.modalitySurfaceGeometryFile(dd, qc, rowIdx);
            metricKey = spec.metricKey;
            zThreshold = spec.zThreshold;
            opts = struct();
            opts.tmpDir = tmpDir;
            opts.metricKey = metricKey;
            opts.zThreshold = zThreshold;
            opts.ReferenceMode = referenceMode;
            opts.rowIndex = rowIdx;
            try
                mesh = NMDataIOSurfaceTools.prepareSurfaceViewerMesh(surfaceFile, geometryFile, opts);
                if ~logical(mesh.ok)
                    out.message = mesh.message;
                    if ~isempty(rehydrateMessage), out.rehydrateMessage = rehydrateMessage; end
                    return;
                end
                overlay = NMDataIOFeatureQCTools.prepareSurfaceViewerQCOverlay(surfaceFile, cacheToken, opts);
                if ~logical(overlay.ok)
                    out.message = overlay.message;
                    if ~isempty(rehydrateMessage), out.rehydrateMessage = rehydrateMessage; end
                    return;
                end
                out.ok = true;
                out.metricKey = overlay.metricKey;
                out.metricLabel = overlay.metricLabel;
                out.metricOptions = NMResultsViewerTools.featureQCMetricOptions(qc, 'surface_vertex_registered');
                out.mesh = mesh;
                out.overlay = overlay;
                out.nReturned = double(overlay.validFeatureCount);
                if strcmpi(referenceMode, 'fixed_reference')
                    out.source = 'DataIO surface QC sidecar, prepared on demand against the training/CV reference';
                    out.referenceMode = 'fixed_reference';
                else
                    out.source = 'DataIO surface QC sidecar, prepared on demand';
                    out.referenceMode = 'leave_one_out';
                end
                out.message = sprintf('Prepared subject-specific surface QC overlay for matched row %g.', rowIdx);
                if ~isempty(rehydrateMessage), out.rehydrateMessage = rehydrateMessage; end
            catch ME
                out.ok = false;
                out.message = sprintf('Feature-level QC could not be prepared: %s', ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
            end
        end

        function out = subjectConnectivityFeatureQCMatrix(NM, dd, qc, modIdx, rowIdx, spec, referenceMode)
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            emptyStruct = struct();
            out = struct('ok',false, 'message','Connectivity feature-level QC matrix was not prepared.', ...
                'viewerKind','connectivity_qc_matrix', 'featureSpace','connectivity_edges', 'metricKey','subject_z', ...
                'metricLabel','Subject edge z-score', 'metricOptions',[], 'source','', 'referenceMode',referenceMode, ...
                'connectivity',emptyStruct, 'rows',[], 'columns',[], 'nReturned',0);
            if ~isstruct(qc) || ~isfield(qc,'connectivity') || ~isstruct(qc.connectivity)
                out.message = 'Connectivity feature-level QC cannot be shown because the persisted QC payload does not contain connectivity edge metadata.';
                return;
            end
            Y = NMResultsViewerTools.modalityMatrix(NM, modIdx);
            rowIdx = round(double(rowIdx));
            if isempty(Y) || ~isnumeric(Y) || rowIdx < 1 || rowIdx > size(Y,1)
                out.message = sprintf('Could not resolve the selected subject row %g in NM.Y{%d} for connectivity QC.', rowIdx, modIdx);
                return;
            end
            conn = qc.connectivity;
            edgeIndex = conn.edgeIndex;
            nNodes = conn.nNodes;
            if isempty(edgeIndex) || size(edgeIndex,2) ~= 2 || nNodes < 1
                out.message = 'Connectivity QC payload does not contain a valid edgeIndex/nNodes definition.';
                return;
            end
            x = double(Y(rowIdx,:));
            if numel(x) ~= size(edgeIndex,1)
                out.message = sprintf('Connectivity subject vector length (%g) does not match retained edge index (%g).', numel(x), size(edgeIndex,1));
                return;
            end
            edgeMean = conn.edgeMean;
            edgeSD = conn.edgeSD;
            edgeMissingRate = conn.edgeMissingRate;
            if numel(edgeMean) ~= numel(x) || numel(edgeSD) ~= numel(x)
                out.message = 'Connectivity QC edge mean/SD vectors are missing or incompatible with the subject edge vector. Recompute/export the persisted QC reference before opening subject-level connectivity QC.';
                return;
            end
            if numel(edgeMissingRate) ~= numel(x)
                error('NMResultsViewerTools:ConnectivityQCMissingRateAxis', 'Saved connectivity missing-rate axis disagrees with subject edge axis.');
            end
            % edgeMatrixStats writes sample SD and finite-observation missing rate on this edge axis.
            % Reconstruct the sufficient M2/count moments without another QC representation.
            countVec = round(qc.nSubjects .* (1 - edgeMissingRate));
            m2Vec = edgeSD.^2 .* max(0, countVec - 1);
            [z, validCount] = NMDataIOFeatureQCTools.computeSubjectZVector( ...
                x, edgeMean, m2Vec, countVec, referenceMode);
            if validCount < 1
                out.message = 'Connectivity QC reference moments produced no finite subject edge z-scores.';
                return;
            end
            matrixType = conn.matrixType;
            opts = struct('matrixType',matrixType, 'includeDiagonal',conn.includeDiagonal);
            metricKey = spec.metricKey;
            metricOptions = NMResultsViewerTools.connectivityFeatureQCMetricOptions();
            out.metricOptions = metricOptions;
            out.metricKey = metricKey;
            out.metricLabel = NMResultsViewerTools.connectivityFeatureQCMetricLabel(metricKey);
            nodeLabels = conn.nodeLabels;
            if numel(nodeLabels) ~= nNodes
                error('NMResultsViewerTools:ConnectivityQCNodeAxis', 'Saved connectivity node labels disagree with the node axis.');
            end
            nodeIDs = conn.nodeIDs;
            if numel(nodeIDs) ~= nNodes
                error('NMResultsViewerTools:ConnectivityQCNodeIDs', 'Saved connectivity node IDs disagree with the node axis.');
            end
            edgeNames = conn.edgeNames;
            if numel(edgeNames) ~= numel(x)
                error('NMResultsViewerTools:ConnectivityQCEdgeNames', 'Saved connectivity edge names disagree with the edge axis.');
            end
            C = struct();
            C.schemaVersion = 1;
            C.mode = 'subject';
            C.nNodes = double(nNodes);
            C.nEdges = double(size(edgeIndex,1));
            C.nodeIDs = num2cell(nodeIDs(:)');
            C.nodeLabels = nodeLabels(:)';
            C.edgeIndex = NMResultsViewerTools.matrixToNestedCell(edgeIndex);
            C.edgeNames = edgeNames(:)';
            C.matrixType = matrixType;
            C.includeDiagonal = logical(opts.includeDiagonal);
            C.groupMeanMatrix = NMResultsViewerTools.matrixToNestedCell(NMDataIOConnectivityTools.edgeVectorToMatrix(edgeMean, edgeIndex, nNodes, opts));
            C.groupSDMatrix = NMResultsViewerTools.matrixToNestedCell(NMDataIOConnectivityTools.edgeVectorToMatrix(edgeSD, edgeIndex, nNodes, opts));
            C.groupMissingRateMatrix = NMResultsViewerTools.matrixToNestedCell(NMDataIOConnectivityTools.edgeVectorToMatrix(edgeMissingRate, edgeIndex, nNodes, opts));
            C.subjectMatrix = NMResultsViewerTools.matrixToNestedCell(NMDataIOConnectivityTools.edgeVectorToMatrix(x, edgeIndex, nNodes, opts));
            C.subjectZMatrix = NMResultsViewerTools.matrixToNestedCell(NMDataIOConnectivityTools.edgeVectorToMatrix(z, edgeIndex, nNodes, opts));
            C.subjectAbsZMatrix = NMResultsViewerTools.matrixToNestedCell(NMDataIOConnectivityTools.edgeVectorToMatrix(abs(z), edgeIndex, nNodes, opts));
            C.subjectMissingMatrix = NMResultsViewerTools.matrixToNestedCell(NMDataIOConnectivityTools.edgeVectorToMatrix(double(~isfinite(x)), edgeIndex, nNodes, opts));
            C.rowIndex = double(rowIdx);
            C.caseId = NMResultsViewerTools.subjectCaseIdFromNM(NM, rowIdx);
            C.metricList = metricOptions;
            out.connectivity = C;
            out.ok = true;
            out.nReturned = double(numel(x));
            out.source = 'Connectivity QC payload reconstructed from the analysis-bound edge feature space';
            if strcmpi(referenceMode, 'fixed_reference')
                out.source = 'Connectivity QC payload reconstructed against the training/CV edge reference';
                out.referenceMode = 'fixed_reference';
            end
            out.message = sprintf('Prepared subject-level connectivity QC matrix for matched row %g.', rowIdx);
        end

        function file = modalitySubjectFile(NM, dd, modIdx, rowIdx, fieldNames)
            file = '';
            candidates = NMResultsViewerTools.modalityFileCandidates(NM, dd, modIdx, fieldNames);
            for ii = 1:numel(candidates)
                files = NMResultsViewerTools.pathListCellstr(candidates{ii});
                if rowIdx >= 1 && rowIdx <= numel(files) && ~isempty(files{rowIdx}) % nm2-allow: DataIO external per-modality file list may omit this selected subject row.
                    file = files{rowIdx};
                    return;
                end
            end
        end

        function candidates = modalityFileCandidates(NM, dd, modIdx, fieldNames)
            % Single source-priority list for on-demand QC subject and cohort reads.
            if isempty(fieldNames), fieldNames = {'files'}; end
            candidates = cell(1, 2 + numel(fieldNames));
            c = 0;
            if isstruct(NM) && isfield(NM,'files') && iscell(NM.files) && modIdx >= 1 && modIdx <= numel(NM.files)
                c = c + 1; candidates{c} = NM.files{modIdx};
            end
            if isstruct(dd) && isfield(dd,'files') && ~isempty(dd.files)
                c = c + 1; candidates{c} = dd.files;
            end
            if isstruct(dd) && isfield(dd,'input_settings') && isstruct(dd.input_settings)
                inp = dd.input_settings;
                for ii = 1:numel(fieldNames)
                    fn = fieldNames{ii};
                    if isfield(inp, fn) && ~isempty(inp.(fn))
                        c = c + 1; candidates{c} = inp.(fn);
                    end
                end
            end
            candidates = candidates(1:c);
        end

        function files = pathListCellstr(v)
            files = {};
            if isempty(v), return; end
            if iscell(v)
                files = cellfun(@(x) strtrim(char(string(x))), v(:), 'UniformOutput', false);
            elseif isstring(v)
                files = cellstr(v(:));
                files = cellfun(@strtrim, files, 'UniformOutput', false);
            elseif ischar(v)
                if size(v,1) > 1
                    files = cellstr(v);
                    files = cellfun(@strtrim, files(:), 'UniformOutput', false);
                else
                    files = {strtrim(v)};
                end
            end
            files = files(:);
        end

        function geometryFile = modalitySurfaceGeometryFile(dd, qc, rowIdx)
            geometryFile = '';
            candidates = {};
            if isfield(qc,'spatialMapping') && isstruct(qc.spatialMapping) % nm2-allow: DataIO surface QC conditionally writes spatialMapping only for non-ROI surfaces
                candidates{end+1} = qc.spatialMapping.surfaceGeometryFile;
            end
            if isfield(dd,'input_settings') % nm2-allow: legacy analysis descriptors can omit NM2 import resource metadata
                candidates{end+1} = NMResultsViewerTools.scalarTextField(dd.input_settings, 'surfaceGeometryFile', '');
            end
            for ii = 1:numel(candidates)
                files = NMResultsViewerTools.pathListCellstr(candidates{ii});
                if isempty(files), continue; end
                idx = round(double(rowIdx));
                if numel(files) > 1 && isfinite(idx) && idx >= 1 && idx <= numel(files) && ~isempty(files{idx})
                    geometryFile = files{idx}; return;
                elseif ~isempty(files{1})
                    geometryFile = files{1}; return;
                end
            end
        end

        function M = modalityMatrix(NM, modIdx)
            M = [];
            if isstruct(NM) && isfield(NM,'Y') && iscell(NM.Y) && modIdx >= 1 && modIdx <= numel(NM.Y) && isnumeric(NM.Y{modIdx})
                M = NM.Y{modIdx};
            end
        end

        function v = structAnyField(s, fieldName, defaultValue)

            v = defaultValue;
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                v = s.(fieldName);
            end
        end

        function C = matrixToNestedCell(M)
            M = double(M);
            C = cell(size(M,1), 1);
            for ii = 1:size(M,1)
                C{ii} = num2cell(M(ii,:));
            end
        end

        function metrics = connectivityFeatureQCMetricOptions()
            tmpl = struct('key','','label','','overlayKind','');
            keys = {'group_mean','group_sd','group_missing_rate','subject_value','subject_z','subject_abs_z','subject_missing'};
            labels = {'Group mean connectivity','Group SD','Group missing-rate','Subject connectivity','Subject edge z-score','Subject |edge z|','Subject missing-edge mask'};
            kinds = {'signed','sequential','rate','signed','subject_z','sequential','rate'};
            metrics = repmat(tmpl, 1, numel(keys));
            for ii = 1:numel(keys)
                metrics(ii) = struct('key',keys{ii}, 'label',labels{ii}, 'overlayKind',kinds{ii});
            end
        end

        function label = connectivityFeatureQCMetricLabel(key)
            opts = NMResultsViewerTools.connectivityFeatureQCMetricOptions();
            label = char(string(key));
            for ii = 1:numel(opts)
                if strcmpi(opts(ii).key, key), label = opts(ii).label; return; end
            end
        end

        function caseId = subjectCaseIdFromNM(NM, rowIdx)
            % TransferModality2NM and NM2 DataIO commit the container-level
            % cases axis. It is not indexed by modality or stored in descriptor aliases.
            idx = round(double(rowIdx));
            caseId = sprintf('S%d', idx);
            ids = NMResultsViewerTools.containerCanonicalCases(NM);
            if idx >= 1 && idx <= numel(ids) && ~isempty(ids{idx})
                caseId = ids{idx};
            end
        end

        function txt = messageArrayText(messages)
            % NMDataIOFeatureQCTools.rehydrateViewerOverlayCache returns
            % NMDataIOMessageTools.emptyMessages/make records with fixed .text.
            parts = cell(1,numel(messages));
            n = 0;
            for ii = 1:numel(messages)
                if ~isempty(messages(ii).text)
                    n = n + 1;
                    parts{n} = messages(ii).text;
                end
            end
            txt = strjoin(parts(1:n), ' ');
        end

        function [rows, columns, msg, source] = subjectFeatureQCRows(qc, rowIdx, maxFeatures, tmpDir, NM, modIdx, referenceMode)
            rowTmpl = struct('rank',NaN,'featureIndex',NaN,'feature','','absZ',NaN,'value',NaN,'note','');
            rows = rowTmpl([]);
            columns = NMResultsViewerTools.tableColumnStruct({'rank','featureIndex','feature','absZ','value','note'}, {'Rank','Feature #','Feature','|z|','Value','Source'});
            msg = 'No subject-specific feature-level QC cache was found.';
            source = '';
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            if isempty(rowIdx) || rowIdx < 1, return; end
            maxFeatures = max(20, min(2000, round(double(maxFeatures))));
            [vec, rawVec, source, msg] = NMResultsViewerTools.subjectFeatureQCVectorFromModality(NM, qc, modIdx, rowIdx, tmpDir, referenceMode);
            if isempty(vec)
                if isempty(msg) || strcmp(msg, 'No subject-specific feature-level QC cache was found.')
                    msg = 'No persisted subject z/|z| vector or compatible QC reference statistics are available for this modality.';
                end
                return;
            end
            vec = double(vec(:)');
            if isempty(rawVec), rawVec = vec; else, rawVec = double(rawVec(:)'); end
            finite = find(isfinite(vec));
            if isempty(finite)
                msg = 'Subject-specific feature-level QC vector contains no finite values.';
                return;
            end
            nKeep=min(numel(finite),maxFeatures);
            scores=abs(vec(finite));
            if nKeep<numel(finite)
                topScores=maxk(scores,nKeep); cutoff=topScores(end);
                strict=finite(scores>cutoff); ties=finite(scores==cutoff);
                tieKeep=ties(1:nKeep-numel(strict)); keep=[strict(:); tieKeep(:)];
            else
                keep=finite(:);
            end
            [~,ord]=sortrows([-abs(vec(keep(:)))' double(keep(:))],[1 2]); keep=keep(ord);
            featureNames=NMResultsViewerTools.modelFeatureInspectionFeatureNames(NM,modIdx,numel(vec),keep);
            rows = repmat(rowTmpl, 1, numel(keep));
            for ii = 1:numel(keep)
                fi = keep(ii);
                rows(ii) = struct('rank',double(ii), 'featureIndex',double(fi), 'feature',char(string(featureNames{ii})), ...
                    'absZ',double(abs(vec(fi))), 'value',double(rawVec(min(fi,numel(rawVec)))), 'note',source);
            end
            msg = '';
        end

        function [vec, rawVec, source, msg] = subjectFeatureQCVectorFromModality(NM, qc, modIdx, rowIdx, tmpDir, referenceMode)
            vec = []; rawVec = []; source = ''; msg = '';

            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            if ~isstruct(NM) || ~isfield(NM,'Y') || ~iscell(NM.Y) || modIdx < 1 || modIdx > numel(NM.Y) || isempty(NM.Y{modIdx}) || ~isnumeric(NM.Y{modIdx})
                msg = 'The analysis-bound modality does not expose an in-memory numeric feature matrix in NM.Y for table-based feature-QC retrieval.';
                return;
            end
            featureSpace = qc.featureSpace;
            if strcmpi(featureSpace, 'image_voxel')
                msg = 'Image-voxel feature tables are intentionally not computed from NM.Y; use the image overlay sidecar path.';
                return;
            end
            M = NM.Y{modIdx};
            rowIdx = round(double(rowIdx));
            if ~isfinite(rowIdx) || rowIdx < 1 || rowIdx > size(M,1)
                msg = sprintf('Matched subject row %g is outside NM.Y{%d} row range 1..%g.', rowIdx, modIdx, size(M,1));
                return;
            end
            rawVec = double(M(rowIdx,:));
            [vec, cacheSource, cacheMsg] = NMResultsViewerTools.featureQCZVectorFromCache(qc, tmpDir, rawVec, referenceMode);
            if isempty(vec)
                msg = cacheMsg;
                if isempty(msg)
                    msg = 'Feature-level QC reference moments are unavailable. Recompute/export QC before opening the subject feature table; Results Viewer will not derive cohort statistics from the complete modality matrix on demand.';
                end
                rawVec = [];
                return;
            end
            source = cacheSource;
            if ~any(isfinite(vec))
                msg = 'No finite subject feature z-scores could be computed from the persisted QC reference.';
                vec = []; rawVec = [];
            end
        end

        function [z, source, msg] = featureQCZVectorFromCache(qc, tmpDir, rawVec, referenceMode)
            z = []; source = ''; msg = '';
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            [cacheFile, cacheMsg] = NMResultsViewerTools.subjectFeatureQCCacheFile(qc, tmpDir);
            if isempty(cacheFile) || exist(cacheFile,'file') ~= 2
                msg = cacheMsg;
                return;
            end
            if exist('NMDataIOFeatureQCTools','class') ~= 8
                msg = 'Feature-level QC cannot be computed because NMDataIOFeatureQCTools is unavailable on the MATLAB path.';
                return;
            end
            S = load(cacheFile, 'meanVec', 'm2Vec', 'countVec');
            if ~isfield(S,'meanVec') || ~isfield(S,'m2Vec') || ~isfield(S,'countVec')
                msg = 'The persisted QC sidecar lacks the mean/M2/count reference moments required for subject-level QC. Recompute/export QC for this modality.';
                return;
            end
            if numel(S.meanVec) ~= numel(rawVec) || numel(S.m2Vec) ~= numel(rawVec) || numel(S.countVec) ~= numel(rawVec)
                msg = 'The persisted QC reference moments do not match the current modality feature count. Recompute/export QC for this modality.';
                return;
            end
            [zTmp, validCount] = NMDataIOFeatureQCTools.computeSubjectZVector(rawVec, S.meanVec, S.m2Vec, S.countVec, referenceMode);
            if validCount > 0
                z = double(zTmp(:)');
                if strcmpi(referenceMode, 'fixed_reference')
                    source = sprintf('QC sidecar fixed training-reference feature statistics: %s', cacheFile);
                else
                    source = sprintf('QC sidecar leave-one-out feature statistics: %s', cacheFile);
                end
            else
                msg = 'The persisted QC reference produced no finite subject feature z-scores for the selected case.';
            end
        end

        function metrics = featureQCMetricOptions(qc, featureSpace)
            % DataIO's viewerOverlay.metrics is a writer-conditioned struct catalogue.
            % The same NMDataIOFeatureQCTools authority owns image/surface defaults.
            fallback = struct('key','subject_z','label','Subject feature z-score','overlayKind','subject_z');
            % Connectivity QC publishes a cell catalogue; image/surface/ROI overlay metrics are structs.
            if ~isempty(qc.viewerOverlay.metrics) && ~strcmp(featureSpace,'connectivity_edges')
                raw = qc.viewerOverlay.metrics;
            elseif strcmpi(featureSpace,'image_voxel')
                raw = NMDataIOFeatureQCTools.imageQCMetricList();
            elseif strcmpi(featureSpace,'surface_vertex_registered') || contains(lower(featureSpace),'surface')
                raw = NMDataIOFeatureQCTools.surfaceQCMetricList();
            elseif strcmpi(featureSpace,'connectivity_edges') || contains(lower(featureSpace),'connectivity')
                raw = NMResultsViewerTools.connectivityFeatureQCMetricOptions();
            else
                raw = fallback;
            end
            if isempty(raw), raw = fallback; end
            metrics = raw;
        end

        function [cacheFile, msg] = subjectFeatureQCCacheFile(qc, tmpDir)
            cacheFile = '';
            msg = '';
                directFields = {'rehydratedCacheFile','persistedCacheFile','sidecarAbsPath'};
                for ii = 1:numel(directFields)
                    if isfield(qc.viewerOverlay,directFields{ii}) && ~isempty(qc.viewerOverlay.(directFields{ii}))
                        candidate = char(string(qc.viewerOverlay.(directFields{ii})));
                        if exist(candidate,'file') == 2, cacheFile = candidate; return; end
                    end
                end
                if ~isempty(qc.viewerOverlay.cacheToken) && ~isempty(tmpDir)
                    try
                        [assetDir, ~, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
                        if isempty(assetErr)
                            candidate = fullfile(assetDir, [char(string(qc.viewerOverlay.cacheToken)) '.mat']);
                            if exist(candidate,'file') == 2, cacheFile = candidate; return; end
                        else
                            msg = assetErr;
                        end
                    catch ME
                        msg = sprintf('Feature-level QC asset directory could not be resolved: %s', ME.message);
                    end
                end
        end

        function c = anyToCellstr(v)
            if iscell(v)
                c = cellfun(@(x) char(string(x)), v(:), 'UniformOutput', false);
            elseif isstring(v)
                c = cellstr(v(:));
            elseif ischar(v)
                c = cellstr(v);
            else
                vals = v(:);
                c = cell(numel(vals),1);
                for ii = 1:numel(vals), c{ii} = char(string(vals(ii))); end
            end
        end

        function out = emptySubjectQCScalarPayload()
            metricTmpl = struct('key','','label','','values',{{}},'unit','','description','');
            out = struct('ok',false, 'message','Scalar QC unavailable.', 'modalityIndex',NaN, ...
                'modalityLabel','', 'source','', 'primaryMetric','rmsZ', 'primaryMetricLabel','RMS leave-one-out feature z-score', ...
                'caseIds',{{}}, 'metrics',metricTmpl([]), 'featureLevelAvailable',false, ...
                'featureLevelMessage','Feature-level QC is not advertised by the bound modality.', ...
                'featureLevelMetrics',metricTmpl([]), 'nSubjects',0, 'nMetrics',0);
        end

        function out = subjectQCScalarPayload(NM, spec)
            out = NMResultsViewerTools.emptySubjectQCScalarPayload();
            [modIdx, modMsg] = NMResultsViewerTools.singleAnalysisBoundModalityIndex(NM, spec);
            if isnan(modIdx)
                out.message = modMsg;
                return;
            end
            source = spec.source;
            [isOOCVSource, oocvIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            D = NM;
            if isOOCVSource
                [D, dd, containerMsg] = NMResultsViewerTools.oocvContainerModalityDescriptor(NM, modIdx, oocvIndex);
                if ~isempty(containerMsg)
                    out.message = containerMsg;
                    out.modalityIndex = double(modIdx);
                    out.modalityLabel = NMResultsViewerTools.modalityLabel(NM, modIdx);
                    return;
                end
            else
                if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || modIdx < 1 || modIdx > numel(NM.datadescriptor)
                    out.message = 'The analysis-bound modality does not resolve to NM.datadescriptor.';
                    return;
                end
                dd = NM.datadescriptor{modIdx};
            end
            out.modalityIndex = double(modIdx);
            out.modalityLabel = NMResultsViewerTools.modalityLabel(NM, modIdx);
            qc = NMResultsViewerTools.qcPayloadFromDescriptor(dd);
            if isempty(fieldnames(qc))
                if isOOCVSource
                    out.message = sprintf('No persisted OOCV DataIO QC object was found for NM.OOCV{%d}.datadescriptor{%d}.', round(double(oocvIndex)), round(double(modIdx)));
                else
                    out.message = sprintf('No persisted DataIO QC object was found for modality %d.', modIdx);
                end
                return;
            end
            caseIds = NMResultsViewerTools.canonicalQCCaseIdsForContainer(D, modIdx, qc);
            if isempty(caseIds)
                out.message = sprintf('Persisted QC for modality %d has no subject IDs; strict subject-ID matching is impossible.', modIdx);
                return;
            end
            metricDefs = { ...
                'rmsZ','RMS leave-one-out feature z-score'; ...
                'meanAbsZ','Mean |feature z|'; ...
                'meanZ','Mean feature z'; ...
                'sdZ','SD of feature z'; ...
                'maxAbsZ','Maximum |feature z|'; ...
                'missingFeatureRateBySubject','Missing-feature rate'; ...
                'zeroFeatureRateBySubject','Zero-feature rate'; ...
                'outlierFeatureRateBySubject','Outlier-feature rate'; ...
                'nValidFeaturesBySubject','Valid feature count'; ...
                'nFiniteFeaturesBySubject','Finite feature count'; ...
                'nMissingFeaturesBySubject','Missing feature count'; ...
                'nZeroFeaturesBySubject','Zero feature count'; ...
                'nOutlierFeaturesBySubject','Outlier feature count'};
            metricTmpl = struct('key','','label','','values',{{}},'unit','','description','');
            metricsAll = repmat(metricTmpl, 1, size(metricDefs,1));
            metricCount = 0;
            nCases = numel(caseIds);
            for ii = 1:size(metricDefs,1)
                key = metricDefs{ii,1};
                vals = qc.(key);
                if isempty(vals) || ~NMResultsViewerTools.qcMetricHasSubjectVariation(vals), continue; end
                metricCount = metricCount + 1;
                metricsAll(metricCount) = struct('key',key, 'label',metricDefs{ii,2}, ...
                    'values',{num2cell(double(vals(:)'))}, 'unit','', 'description','Subject-level scalar metric from persisted DataIO feature QC.');
            end
            metrics = metricsAll(1:metricCount);
            if isempty(metrics)
                out.message = sprintf('No non-constant compact scalar QC vectors were found for modality %d.', modIdx);
                out.caseIds = caseIds(:)';
                out.nSubjects = double(nCases);
                return;
            end
            primary = qc.primaryScore;
            primaryLabel = qc.scoreName;
            featureLevelAvailable = false;
            featureMsg = 'Feature-level QC is not advertised by the bound modality.';
            if isfield(qc,'qcCacheToken') && ~isempty(qc.qcCacheToken)
                featureLevelAvailable = true;
                featureMsg = 'A MATLAB-side full QC cache token is available for lazy feature-level retrieval.';
            elseif logical(qc.viewerOverlay.available)
                featureLevelAvailable = true;
                featureMsg = 'A modality viewer-overlay QC cache is available for lazy feature-level retrieval.';
            elseif ~isempty(fieldnames(qc.featureStats)) && logical(qc.featureStats.fullReturned)
                featureLevelAvailable = true;
                featureMsg = 'Compact full feature statistics are present in the persisted QC payload.';
            end
            out.ok = true;
            if isOOCVSource
                out.message = sprintf('Loaded %d non-constant scalar QC metric(s) for NM.OOCV{%d}.datadescriptor{%d}.', numel(metrics), round(double(oocvIndex)), round(double(modIdx)));
            else
                out.message = sprintf('Loaded %d non-constant scalar QC metric(s) for the single analysis-bound modality.', numel(metrics));
            end
            out.source = qc.sourceType;
            out.primaryMetric = primary;
            out.primaryMetricLabel = primaryLabel;
            out.caseIds = caseIds(:)';
            out.metrics = metrics;
            out.featureLevelAvailable = logical(featureLevelAvailable);
            out.featureLevelMessage = featureMsg;
            out.featureLevelMetrics = NMResultsViewerTools.featureQCMetricOptions(qc, qc.featureSpace);
            out.nSubjects = double(nCases);
            out.nMetrics = double(numel(metrics));
        end

        function [idx, msg] = singleAnalysisBoundModalityIndex(NM, spec)
            idx = NaN;
            msg = 'Scalar QC is only exposed when the selected analysis is bound to exactly one modality.';
            analIdx = spec.analysisIndex;
            if isnan(analIdx) || analIdx < 1 || ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || analIdx > numel(NM.analysis) % nm2-allow: public Subject QC selector validates optional requested analysis identity against NM.analysis.
                msg = 'No valid analysis is selected for modality-QC resolution.';
                return;
            end
            if ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || isempty(NM.datadescriptor) % nm2-allow: DataIO may not have committed any modalities to a draft NM; scalar QC cannot resolve a modality.
                msg = 'NM.datadescriptor is empty; no persisted modality QC can be resolved.';
                return;
            end
            A = NM.analysis{analIdx};

            % Prefer the authoritative analysis fusion contract when it
            % identifies exactly one source modality. This avoids disabling
            % QC panels for legacy analyses that do not store a complete
            % datadescriptor snapshot under A.params.datadescriptor.
            params = NMResultsViewerTools.structAnyField(A, 'params', struct());
            trainParam = NMResultsViewerTools.structAnyField(params, 'TrainParam', struct());
            fusion = NMResultsViewerTools.structAnyField(trainParam, 'FUSION', struct());
            if isstruct(fusion) && isfield(fusion,'M') && ~isempty(fusion.M) % nm2-allow: scalar-QC public admission accepts incomplete analysis state; nk_InitAnalysisPrep snapshots FUSION.M only when configured.
                % nk_TrainClass_config/nk_Fusion_config produce numeric flag/M.
                % Late fusion M selects strategies rather than physical sources.
                if fusion.flag ~= 3
                    vals = double(fusion.M(:));
                    vals = vals(isfinite(vals) & vals >= 1);
                    if ~isempty(vals)
                        vals = unique(round(vals(:)'));
                        if numel(vals) ~= 1
                            msg = sprintf('The selected analysis fusion contract references %d modalities; modality-QC panels are disabled for this first implementation.', numel(vals));
                            return;
                        end
                        if vals(1) <= numel(NM.datadescriptor)
                            idx = vals(1);
                            msg = '';
                            return;
                        end
                        msg = sprintf('The selected analysis fusion contract references modality %d, but NM.datadescriptor has only %d entries.', vals(1), numel(NM.datadescriptor));
                        return;
                    end
                end
            end

            % nk_InitAnalysisPrep persists the complete datadescriptor list,
            % never a single analysis-bound descriptor. Only a one-modality
            % workspace is unambiguous when FUSION.M did not resolve binding.
            if numel(NM.datadescriptor) == 1
                idx = 1;
                msg = '';
            else
                msg = 'No unique analysis-bound modality can be resolved from FUSION.M; scalar QC is disabled.';
            end
        end

        function label = modalityLabel(NM, idx)
            label = sprintf('Modality %d', idx);
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || idx < 1 || idx > numel(NM.datadescriptor), return; end
            dd = NM.datadescriptor{idx};
            if ~isempty(dd.desc), label = dd.desc; end
        end

        function caseIds = qcCaseIds(qc)
            % DataIO's QC writer publishes aligned Case IDs on the top-level axis.
            caseIds = qc.caseIds(:);
        end

        function tf = qcMetricHasSubjectVariation(vals)
            tf = false;
            if isempty(vals), return; end
            x = double(vals(:));
            x = x(isfinite(x));
            if numel(x) < 2, return; end
            tf = max(x) > min(x);
        end

        function txt = scalarTextField(s, fieldName, default)
            txt = default;
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                txt = char(string(s.(fieldName)));
            end
        end

        function version = modelFeatureInspectionScientificContractVersion()
            % modelFeatureInspectionScientificContractVersion  Version of the canonical scientific-selection contract.
            version = 'NM-FEATURE-INSPECTION-SCIENTIFIC-V1';
        end

        function [annotation,resolved] = modelFeatureInspectionScientificAnnotation(NM,payload,selection,requestedMeasureId)
            % modelFeatureInspectionScientificAnnotation  Publish common scientific meaning plus exact NM materialization.
            %
            % Selection and payload builders upstream own the fixed internal schemas.
            % This function serializes those resolved facts; it does not rediscover
            % VIS/GDdims schema or materialize feature values.
            material = NMResultsViewerScientificAnnotation.featureInspectionMaterialTemplate();
            material.analysisIndex = payload.analysisIndex;
            material.targetIndex = payload.targetIndex;
            material.resultTargetIndex = payload.resultTargetIndex;
            material.classifierIndex = payload.classifierIndex;
            material.featureContextId = payload.selectedFeatureContextId;
            [analysisLabel,analysisMode,labelInfo] = NMResultsViewerTools.analysisLabelAndMode(NM,selection.analysis);
            nTargets=1;
            if ~isempty(labelInfo.selectedColumns)
                nTargets=numel(labelInfo.selectedColumns);
            elseif ~isempty(analysisLabel)
                nTargets=max(1,size(analysisLabel,2));
            end
            [targetNames,targetNativeIdx]=NMResultsViewerTools.analysisTargetLabelNames(NM,selection.analysis,nTargets,labelInfo.selectedColumns);
            targetPosition=max(1,round(double(payload.targetIndex)));
            if targetPosition>nTargets
                error('NMResultsViewerTools:InvalidScientificAnnotationPayload', ...
                    'Feature Inspection target position exceeds the effective analysis label count.');
            end
            material.targetNativeIndex=targetNativeIdx(targetPosition);
            material.targetSource=labelInfo.source;
            material.targetLabelName=targetNames{targetPosition};
            material.analysisMode=analysisMode;
            material.fusionMode=NMResultsViewerTools.analysisFusionMode(selection.analysis);
            isStacking=NMResultsViewerTools.analysisStackingActive(selection.analysis);
            material.selectedContextIsCombined=logical(selection.selectedCatalogueEntry.isCombined);

            contexts=selection.selectedContexts;
            if ~isempty(contexts)
                material.physicalContextIds={contexts.contextId};
                material.physicalVisRowIndices=double([contexts.visRowIndex]);
                material.physicalVarinds=double([contexts.varind]);
                material.physicalFeatureCounts=double([contexts.nFeatures]);
                material.modalityVarinds=NMResultsViewerTools.analysisFeatureModalityVarinds( ...
                    selection.analysis,material.physicalVarinds,isStacking);
                nModalities=numel(material.modalityVarinds);
                material.modalityDescriptions=cell(1,nModalities);
                material.modalitySourceTypes=cell(1,nModalities);
                material.modalitySourceTypeLabels=cell(1,nModalities);
                material.modalityDatasources=cell(1,nModalities);
                material.modalitySources=cell(1,nModalities);
                material.modalityTypeCodes=nan(1,nModalities);
                modalityNamesAvailable=false(1,nModalities);
                for modalityPosition=1:nModalities
                    modalityInfo=NMModalityInfoTools.fromNM( ...
                        NM,material.modalityVarinds(modalityPosition),struct('ScanInMemory',false));
                    material.modalityDescriptions{modalityPosition}=modalityInfo.description;
                    material.modalitySourceTypes{modalityPosition}=modalityInfo.sourceType;
                    material.modalitySourceTypeLabels{modalityPosition}=modalityInfo.sourceTypeLabel;
                    material.modalityDatasources{modalityPosition}=modalityInfo.datasource;
                    material.modalitySources{modalityPosition}=modalityInfo.source;
                    material.modalityTypeCodes(modalityPosition)=double(modalityInfo.typeCode);
                    modalityNamesAvailable(modalityPosition)=isequal(modalityInfo.featureNamesAvailable,true);
                end
                if ~isStacking && ismember(material.fusionMode,{'early','intermediate'})
                    material.featureNamesAvailable=true;
                    if material.selectedContextIsCombined
                        material.featureNameSource='analysis.visdata.params.features (fusion projection)';
                    else
                        material.featureNameSource='analysis.visdata.params.features (fusion member)';
                    end
                elseif ~isStacking && numel(contexts)==1 && numel(material.modalityVarinds)==1 && ... % nm2-allow: feature-name authority applies only to one physical modality/context
                        contexts(1).varind==material.modalityVarinds(1) && modalityNamesAvailable(1)
                    material.featureNamesAvailable=true;
                    material.featureNameSource='NM.featnames';
                elseif isStacking
                    if numel(contexts)~=1
                        error('NMResultsViewerTools:InvalidStackingFeatureContext', ...
                            'A stacking Feature Inspection namespace must resolve to exactly one analysis-local VIS feature context.');
                    end
                    stackVis=NMResultsViewerTools.modelFeatureInspectionVisEntry( ...
                        selection.analysis,contexts(1).visRowIndex,contexts(1).resultTargetIndex);
                    if isequal(stackVis.params.features,{[]})
                        material.featureNameSource='analysis.params.TrainParam.STACKING.sel_anal';
                    else
                        material.featureNameSource='analysis.visdata.params.features';
                    end
                end
            end

            selectedContext=selection.selectedCatalogueEntry;
            material.featureKind=selectedContext.featureKind;
            material.fusionMode=selectedContext.fusionMode;
            if strcmpi(material.featureKind,'roi')
                material.roiSpatialDomain=selectedContext.roiSpatialDomain;
                material.roiSpatialSemantics=selectedContext.roiSpatialSemantics;
                material.roiIdentityModel=selectedContext.roiIdentityModel;
                material.roiSpatialReferenceIdentity=selectedContext.roiSpatialReferenceIdentity;
            end
            material.measureId=payload.selectedMeasureId;
            material.requestedMeasureId=requestedMeasureId;
            availableMeasureIds={};
            if ~isempty(payload.measures)
                enabledMask=logical([payload.measures.enabled]);
                availableMeasureIds={payload.measures(enabledMask).measureId};
                measureHit=find(strcmpi({payload.measures.measureId},material.measureId),1,'first');
                if ~isempty(measureHit)
                    material.payloadField=payload.measures(measureHit).sourceField;
                    material.payloadSeField=payload.measures(measureHit).seSourceField;
                end
            end
            selectedAvailable=~isempty(material.measureId)&&any(strcmpi(availableMeasureIds,material.measureId));
            requestedAvailable=~isempty(material.requestedMeasureId)&&any(strcmpi(availableMeasureIds,material.requestedMeasureId));
            if isempty(material.requestedMeasureId)
                material.measureRequestSatisfied=selectedAvailable;
                if selectedAvailable, material.measureSelector='defaultMeasure'; end
            elseif requestedAvailable&&strcmpi(material.measureId,material.requestedMeasureId)
                material.measureRequestSatisfied=true;
                material.measureSelector='measureId';
            elseif selectedAvailable
                material.measureRequestSatisfied=false;
                material.measureSelector='fallbackFromUnavailableMeasureId';
            else
                material.measureRequestSatisfied=false;
                material.measureSelector='unavailableMeasureId';
            end
            material.backprojectionComponentId=payload.selectedBackprojectionComponentId;
            material.componentIndex=payload.selectedBackprojectionComponentIndex;
            material.componentPosition=payload.selectedBackprojectionComponentColumn;
            material.contextSelector=selection.contextSelector;
            material.componentSelector=selection.componentSelector;
            annotation=NMResultsViewerScientificAnnotation.fromFeatureInspection(material);
            resolved=NMResultsViewerScientificAnnotation.legacyResolvedSelection(annotation);
        end
        function modelFeatureInspectionValidateCachedPayload(spec,inspection)
            % modelFeatureInspectionValidateCachedPayload  Validate one canonical cached payload at the cache boundary.
            expectedVersion = NMResultsViewerTools.modelFeatureInspectionScientificContractVersion();
            if ~strcmp(inspection.scientificContractVersion,expectedVersion)
                error('NMResultsViewerTools:InvalidFeatureInspectionScientificContract', ...
                    'Optional Feature Inspection metadata must implement scientific contract %s.', ...
                    expectedVersion);
            end
            NMResultsViewerScientificAnnotation.validate(inspection.scientificAnnotation);
            resolved = inspection.resolvedSelection;
            expectedResolved = NMResultsViewerScientificAnnotation.legacyResolvedSelection( ...
                inspection.scientificAnnotation);
            if ~isequaln(resolved,expectedResolved)
                error('NMResultsViewerTools:InvalidFeatureInspectionResolvedSelection', ...
                    'resolvedSelection disagrees with the canonical scientificAnnotation material.');
            end
            if ~isequaln(double(inspection.analysisIndex),double(resolved.analysisIndex)) || ...
                    ~isequaln(double(inspection.targetIndex),double(resolved.targetIndex)) || ...
                    ~isequaln(double(inspection.resultTargetIndex),double(resolved.resultTargetIndex)) || ...
                    ~isequaln(double(inspection.classifierIndex),double(resolved.classifierIndex))
                error('NMResultsViewerTools:InvalidFeatureInspectionResolvedSelection', ...
                    'Cached scalar selection identity disagrees with resolvedSelection.');
            end
            if ~strcmp(inspection.selectedFeatureContextId,resolved.featureContextId)
                error('NMResultsViewerTools:InvalidFeatureInspectionResolvedSelection', ...
                    'resolvedSelection.featureContextId disagrees with selectedFeatureContextId.');
            end
            if ~isequal({inspection.contexts.contextId},resolved.physicalContextIds) || ...
                    ~isequal(double([inspection.contexts.visRowIndex]),double(resolved.physicalVisRowIndices)) || ...
                    ~isequal(double([inspection.contexts.varind]),double(resolved.physicalVarinds)) || ...
                    ~isequal(double([inspection.contexts.nFeatures]),double(resolved.physicalFeatureCounts))
                error('NMResultsViewerTools:InvalidFeatureInspectionResolvedSelection', ...
                    'resolvedSelection physical-context identity disagrees with payload.contexts.');
            end
            if ~strcmp(inspection.selectedBackprojectionComponentId,resolved.backprojectionComponentId) || ...
                    ~isequaln(double(inspection.selectedBackprojectionComponentIndex),double(resolved.componentIndex)) || ...
                    ~isequaln(double(inspection.selectedBackprojectionComponentColumn),double(resolved.componentPosition))
                error('NMResultsViewerTools:InvalidFeatureInspectionResolvedSelection', ...
                    'resolvedSelection component identity disagrees with the payload component fields.');
            end

            % This public cached-payload API admits a partial selection request.
            % Scientific Annotation owns all omitted coordinates; validate only
            % selectors the caller explicitly requested (never re-normalize State).
            if isfield(spec,'analysisIndex') && ~isempty(spec.analysisIndex) % nm2-allow: Scientific Annotation supplies omitted coordinates, while supplied scalar selections require identity agreement.
                NMResultsViewerTools.modelFeatureInspectionRequireCachedScalar('analysisIndex', ...
                    spec.analysisIndex,resolved.analysisIndex);
            end
            if isfield(spec,'targetIndex') && ~isempty(spec.targetIndex) % nm2-allow: Scientific Annotation supplies omitted coordinates, while supplied scalar selections require identity agreement.
                NMResultsViewerTools.modelFeatureInspectionRequireCachedScalar('targetIndex', ...
                    spec.targetIndex,resolved.targetIndex);
            end
            if isfield(spec,'classifierIndex') && ~isempty(spec.classifierIndex) % nm2-allow: Scientific Annotation supplies omitted coordinates, while supplied scalar selections require identity agreement.
                NMResultsViewerTools.modelFeatureInspectionRequireCachedScalar('classifierIndex', ...
                    spec.classifierIndex,resolved.classifierIndex);
            end
            if isfield(spec,'featureContextId') && ~isempty(spec.featureContextId) && ... % nm2-allow: Scientific Annotation supplies omitted context identity and explicit context must agree.
                    ~strcmp(spec.featureContextId,resolved.featureContextId)
                error('NMResultsViewerTools:FeatureInspectionSelectionMismatch', ...
                    'Cached featureContextId %s does not match requested featureContextId %s.', ...
                    resolved.featureContextId,spec.featureContextId);
            end
            if isfield(spec,'modalityIndex') && isfinite(spec.modalityIndex) && ... % nm2-allow: Scientific Annotation owns default modality identity; an explicit modality must agree.
                    ~any(double(resolved.physicalVisRowIndices)==round(spec.modalityIndex))
                error('NMResultsViewerTools:FeatureInspectionSelectionMismatch', ...
                    'Cached physical VIS rows do not contain requested modalityIndex %g.',spec.modalityIndex);
            end
            if isfield(spec,'backprojectionComponentId') && ~isempty(spec.backprojectionComponentId) && ... % nm2-allow: Scientific Annotation owns component identity, requiring agreement for explicitly specified component.
                    ~strcmp(spec.backprojectionComponentId,resolved.backprojectionComponentId)
                error('NMResultsViewerTools:FeatureInspectionSelectionMismatch', ...
                    'Cached backprojection component does not match the requested component identity.');
            end
            if isfield(spec,'componentIndex') && isfinite(spec.componentIndex) && ... % nm2-allow: Scientific Annotation supplies the omitted component position; explicit component must agree.
                    ~isequaln(double(spec.componentIndex),double(resolved.componentIndex))
                error('NMResultsViewerTools:FeatureInspectionSelectionMismatch', ...
                    'Cached componentIndex %g does not match requested componentIndex %g.', ...
                    resolved.componentIndex,spec.componentIndex);
            end
        end

        function modelFeatureInspectionRequireCachedScalar(fieldName,requested,resolved)
            requested = double(requested(1));
            resolved = double(resolved(1));
            if ~isfinite(requested) || ~isfinite(resolved) || round(requested) ~= round(resolved)
                error('NMResultsViewerTools:FeatureInspectionSelectionMismatch', ...
                    'Cached %s %g does not match requested %s %g.', ...
                    fieldName,resolved,fieldName,requested);
            end
        end

        function payload = emptyModelFeatureInspectionPayload()
            % emptyModelFeatureInspectionPayload  Create fixed-schema model-feature-inspection payload.
            payload = struct('ok',false, 'kind','model_feature_inspection', 'schemaVersion',5, ...
                'scientificContractVersion',NMResultsViewerTools.modelFeatureInspectionScientificContractVersion(), ...
                'scientificAnnotation',NMResultsViewerScientificAnnotation.template(), ...
                'resolvedSelection',NMResultsViewerScientificAnnotation.legacyResolvedSelectionTemplate(), ...
                'featureRelationContractVersion','C17a.1', ...
                'featureRelationServiceVersion','C17b.1', ...
                'featureRelationSourceScopeVersion','C17j5b.1', ...
                'payloadScope','full', ...
                'analysisIndex',0, 'classifierIndex',1, 'targetIndex',1, 'resultTargetIndex',NaN, ...
                'selectedMeasureId','', 'selectedFeatureContextId','', ...
                'selectedFeatureContext',NMResultsViewerTools.modelFeatureInspectionContextTemplate(), ...
                'backprojectionAvailable',false, ...
                'backprojectionComponents',repmat(NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate(),1,0), ...
                'selectedBackprojectionComponentId','', 'selectedBackprojectionComponentIndex',NaN, ...
                'selectedBackprojectionComponentColumn',NaN, 'selectedBackprojectionComponentLabel','', ...
                'combinedViewAvailable',false, ...
                'maxFeaturesPerContext',200, 'maxComponentsPerContext',200, ...
                'title','Model feature inspection', 'subtitle','', 'message','', ...
                'featureContexts',repmat(NMResultsViewerTools.modelFeatureInspectionContextTemplate(),1,0), ...
                'contexts',repmat(NMResultsViewerTools.modelFeatureInspectionContextTemplate(),1,0), ...
                'measures',repmat(NMResultsViewerTools.modelFeatureInspectionMeasureTemplate(),1,0), ...
                'measureAnnotations',repmat(NMResultsViewerTools.modelFeatureInspectionMeasureAnnotationTemplate(),1,0), ...
                'featureTable',repmat(NMResultsViewerTools.modelFeatureInspectionFeatureRowTemplate(),1,0), ...
                'distributionTable',repmat(NMResultsViewerTools.modelFeatureInspectionDistributionTemplate(),1,0), ...
                'matrixPayloads',repmat(NMResultsViewerTools.modelFeatureInspectionMatrixTemplate(),1,0), ...
                'networkPayloads',repmat(NMResultsViewerTools.modelFeatureInspectionNetworkTemplate(),1,0), ...
                'volcanoPayloads',repmat(NMResultsViewerTools.modelFeatureInspectionVolcanoTemplate(),1,0), ...
                'modelPermutation',NMResultsViewerTools.modelFeatureInspectionPermutationPayload(), ...
                'extraLabelGeneralization',NMResultsViewerTools.modelFeatureInspectionExtraLabelPayload(), ...
                'componentAnalysis',NMResultsViewerTools.emptyModelFeatureInspectionComponentAnalysis(), ...
                'spatialMaps',repmat(NMResultsViewerTools.modelFeatureInspectionSpatialTemplate(),1,0), ...
                'diagnostics',repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0), ...
                'summaryRows',[], 'scoreRows',[], 'unsupportedPanels',{{}});
        end

        function [available, message] = modelFeatureInspectionAvailability(NM, idx)
            % modelFeatureInspectionAvailability  Test whether an analysis exposes VIS payloads.
            A = NM.analysis{idx};
            % nm2-allow: nk_VisModelsPrep conditionally creates analysis.visdata only when the VIS pipeline has produced feature-inspection material for the completed analysis.
            if ~isfield(A,'visdata') || isempty(A.visdata)
                available = false;
                message = 'The selected analysis has no analysis.visdata produced by the VIS pipeline.';
                return;
            end
            available = any(~cellfun(@isempty,A.visdata(:)));
            if available
                message = 'Model-feature-inspection VIS payload detected.';
            else
                message = 'analysis.visdata exists, but contains no populated VIS modality entries.';
            end
        end
        function [nModalities, nTargets] = modelFeatureInspectionVisSize(A)
            % nk_VisModelsPrep writes analysis.visdata as a modality-by-target cell matrix.
            nModalities = size(A.visdata,1);
            nTargets = size(A.visdata,2);
        end
        function v = modelFeatureInspectionVisEntry(A, modalityIndex, targetIndex)
            % nk_VisModelsPrep writes analysis.visdata as a modality-by-target cell matrix.
            v = [];
            if modalityIndex >= 1 && modalityIndex <= size(A.visdata,1) && ...
                    targetIndex >= 1 && targetIndex <= size(A.visdata,2)
                v = A.visdata{modalityIndex,targetIndex};
            end
        end
        function entries = modelPerformancePermutationVisEntries(A, resultTargetIndex, modelSource)
            % modelPerformancePermutationVisEntries  Return writer-defined modality replicas for one compact VIS target.
            entries = struct('vis',{},'modalityIndex',{},'targetIndex',{},'path',{});
            % nm2-allow: nk_VisModelsPrep conditionally creates analysis.visdata only when VIS material exists
            if ~isfield(A,'visdata') || isempty(A.visdata), return; end
            if resultTargetIndex < 1 || resultTargetIndex ~= round(resultTargetIndex)
                error('NMResultsViewerTools:InvalidPermutationTarget','Permutation result target must be one positive integer.');
            end
            if resultTargetIndex > size(A.visdata,2), return; end
            isLate = strcmp(NMResultsViewerTools.analysisFusionMode(A),'late');
            if isLate && isempty(modelSource)
                error('NMResultsViewerTools:PermutationModelSourceRequired', ...
                    'Late-fusion permutation extraction requires an explicit model source.');
            end
            for modalityIndex = 1:size(A.visdata,1)
                if isLate && ~strcmp(modelSource,sprintf('modality:%d',modalityIndex))
                    continue;
                end
                v = A.visdata{modalityIndex,resultTargetIndex};
                if isempty(v), continue; end
                if NMResultsViewerTools.modelPerformancePermutationVisEntryAvailable(v)
                    n = numel(entries) + 1;
                    entries(n).vis = v;
                    entries(n).modalityIndex = modalityIndex;
                    entries(n).targetIndex = resultTargetIndex;
                    entries(n).path = sprintf('visdata{%d,%d}',modalityIndex,resultTargetIndex);
                end
            end
        end

        function tf = modelPerformancePermutationVisEntryAvailable(v)
            % modelPerformancePermutationVisEntryAvailable  Writer-conditioned VIS permutation-family gate.
            % nk_VisModelsC writes each admitted family atomically; testing one lead field is sufficient.
            tf = false;
            % nm2-allow: nk_VisModelsC writes the ordinary model-permutation family only when permutation/significance material was produced
            if isfield(v,'PermModel_Crit_Global')
                tf = true;
                return;
            end
            % nm2-allow: nk_VisModelsC writes ExtraL only when extra-label generalization material was produced
            if isfield(v,'ExtraL') && ~isempty(v.ExtraL)
                tf = true;
            end
        end


        function tf = modelFeatureInspectionIsVisStruct(v)
            % Populated nk_VisModelsC entries are scalar VIS structs with a fixed params contract.
            tf = ~isempty(v);
        end
        function defs = modelFeatureInspectionMeasureDefinitions()
            % modelFeatureInspectionMeasureDefinitions  Registry of public VIS measures.
            % MEAN_CV2, SE_CV2 and CVRatio_CV2 are intentionally absent from this
            % public registry. They are internal writer fields and are not public measures.
            tmpl = struct('measureId','','label','','category','','sourceField','','seSourceField','', ...
                'valuePolarity','signed','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN, ...
                'thresholdValue',NaN,'thresholdLabel','');
            defs = repmat(tmpl, 1, 19);
            defs(1) = struct('measureId','feature_weight_mean','label','Mean feature weight','category','weight','sourceField','MEAN','seSourceField','SE','valuePolarity','signed','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN,'thresholdLabel','No threshold');
            defs(2) = struct('measureId','cross_validation_ratio','label','Cross-validation ratio','category','stability','sourceField','CVRatio','seSourceField','','valuePolarity','signed','thresholdMode','outside_interval','thresholdLow',-2,'thresholdHigh',2,'thresholdValue',NaN,'thresholdLabel','|cross-validation ratio| >= 2');
            defs(3) = struct('measureId','feature_selection_probability','label','Feature-selection probability','category','selection','sourceField','FeatProb','seSourceField','','valuePolarity','signed','thresholdMode','outside_interval','thresholdLow',-0.5,'thresholdHigh',0.5,'thresholdValue',NaN,'thresholdLabel','|selection probability| >= 0.5');
            defs(4) = struct('measureId','reliability_probability_95ci','label','Reliability probability','category','stability','sourceField','Prob_CV2','seSourceField','','valuePolarity','signed','thresholdMode','outside_interval','thresholdLow',-0.5,'thresholdHigh',0.5,'thresholdValue',NaN,'thresholdLabel','|reliability probability| >= 0.5');
            defs(5) = struct('measureId','sign_consistency','label','Sign-based consistency','category','stability','sourceField','SignBased_CV2','seSourceField','','valuePolarity','signed','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN,'thresholdLabel','No threshold');
            defs(6) = struct('measureId','sign_consistency_z','label','SBC z score','category','stability','sourceField','SignBased_CV2_z','seSourceField','','valuePolarity','signed','thresholdMode','outside_interval','thresholdLow',-2,'thresholdHigh',2,'thresholdValue',NaN,'thresholdLabel','|z| >= 2');
            defs(7) = struct('measureId','sign_consistency_logp','label','SBC -log10(P)','category','significance','sourceField','SignBased_CV2_p_uncorr','seSourceField','','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(P) >= -log10(0.05)');
            defs(8) = struct('measureId','sign_consistency_logq','label','SBC -log10(q)','category','significance','sourceField','SignBased_CV2_p_fdr','seSourceField','','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(q) >= -log10(0.05)');
            defs(9) = struct('measureId','spearman_association','label','Spearman association','category','association','sourceField','Spearman_CV2','seSourceField','','valuePolarity','signed','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN,'thresholdLabel','No threshold');
            defs(10) = struct('measureId','pearson_association','label','Pearson association','category','association','sourceField','Pearson_CV2','seSourceField','','valuePolarity','signed','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN,'thresholdLabel','No threshold');
            defs(11) = struct('measureId','spearman_logp','label','Spearman -log10(P)','category','significance','sourceField','Spearman_CV2_p_uncorr','seSourceField','Spearman_CV2_p_uncorr_STD','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(P) >= -log10(0.05)');
            defs(12) = struct('measureId','pearson_logp','label','Pearson -log10(P)','category','significance','sourceField','Pearson_CV2_p_uncorr','seSourceField','Pearson_CV2_p_uncorr_STD','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(P) >= -log10(0.05)');
            defs(13) = struct('measureId','spearman_logq','label','Spearman -log10(q)','category','significance','sourceField','Spearman_CV2_p_fdr','seSourceField','Spearman_CV2_p_fdr_STD','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(q) >= -log10(0.05)');
            defs(14) = struct('measureId','pearson_logq','label','Pearson -log10(q)','category','significance','sourceField','Pearson_CV2_p_fdr','seSourceField','Pearson_CV2_p_fdr_STD','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(q) >= -log10(0.05)');
            defs(15) = struct('measureId','permutation_z','label','Permutation z score','category','permutation','sourceField','PermZ_CV2','seSourceField','','valuePolarity','signed','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN,'thresholdLabel','No threshold');
            defs(16) = struct('measureId','permutation_logp','label','Permutation -log10(P)','category','permutation','sourceField','PermProb_CV2','seSourceField','','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(P) >= -log10(0.05)');
            defs(17) = struct('measureId','permutation_logq','label','Permutation -log10(q)','category','permutation','sourceField','PermProb_CV2_FDR','seSourceField','','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(q) >= -log10(0.05)');
            defs(18) = struct('measureId','analytical_logp','label','Analytical -log10(P)','category','significance','sourceField','Analytical_p','seSourceField','','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(P) >= -log10(0.05)');
            defs(19) = struct('measureId','analytical_logq','label','Analytical -log10(q)','category','significance','sourceField','Analyitcal_p_fdr','seSourceField','','valuePolarity','positive','thresholdMode','above','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',-log10(0.05),'thresholdLabel','-log10(q) >= -log10(0.05)');
        end

        function ctx = modelFeatureInspectionContextTemplate()
            tmpl = struct('contextId','','analysisIndex',0,'targetIndex',1,'resultTargetIndex',1, ...
                'targetLabel','Target 1','classIndex',1,'classLabel','Classifier 1','isMultiGroup',false, ...
                'visRowIndex',1,'modalityIndex',1,'modalityLabel','Modality 1','selectionLabel','Modality 1', ...
                'varind',1,'componentIndex',NaN,'componentLabel','', ...
                'backprojectionAvailable',false,'backprojectionComponentCount',0, ...
                'fusionMode','none', ...
                'legacyVisFlag',NaN,'sourceKind','visdata','sourceFamily','unknown', ...
                'featureKind','tabular','rendererFamily','tabular','nFeatures',0, ...
                'roiSidecarAvailable',false,'roiSpatialDomain','','roiSpatialSemantics','', ...
                'roiIdentityModel','','roiSpatialReferenceIdentity','', ...
                'roiAtlasFile','','roiHasAtlasCoordinates',false, ...
                'isCombined',false,'memberContextIds',{{}},'relationFeatureLabels',{{}},'combinedGroupId','', ...
                'enabled',false,'disabledReason','');
            ctx = tmpl;
        end

        function component = modelFeatureInspectionBackprojectionComponentTemplate()
            % modelFeatureInspectionBackprojectionComponentTemplate  Fixed-schema retained-component selector entry.
            % componentIndex is the original component index in CompKept; componentPosition
            % is its 1-based position among retained components and therefore the
            % writer-defined backprojection-column index when feature matrices contain retained columns only.
            tmpl = struct('componentId','','contextId','','componentIndex',NaN, ...
                'componentPosition',NaN,'componentLabel','','selectionLabel','', ...
                'presencePercent',NaN,'nAllComponents',0,'nRetainedComponents',0, ...
                'memberContextIds',{{}},'enabled',false,'disabledReason','');
            component = tmpl;
        end

        function measure = modelFeatureInspectionMeasureTemplate()
            tmpl = struct('contextId','','measureId','','label','','category','','sourceField','', ...
                'legacySourceField','','valuePolarity','signed','thresholdMode','none', ...
                'thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN,'thresholdLabel','', ...
                'hasSE',false,'seSourceField','','enabled',false,'disabledReason','');
            measure = tmpl;
        end

        function entry = modelFeatureInspectionMeasureAnnotationTemplate()
            % modelFeatureInspectionMeasureAnnotationTemplate  Fixed per-measure annotation lookup entry.
            tmpl = struct('measureId','','scientificAnnotation',NMResultsViewerScientificAnnotation.template());
            entry = tmpl;
        end

        function entries = modelFeatureInspectionMeasureAnnotations(measures,baseAnnotation)
            % modelFeatureInspectionMeasureAnnotations  Publish exact annotations for measure panels.
            %
            % Each entry is derived by the scientific-annotation authority from the
            % already-resolved base material. Browser panels can therefore expose
            % exact measure provenance without reconstructing measure identity.
            if isempty(measures)
                entries = repmat(NMResultsViewerTools.modelFeatureInspectionMeasureAnnotationTemplate(),1,0);
                return;
            end
            tmpl = NMResultsViewerTools.modelFeatureInspectionMeasureAnnotationTemplate();
            entries = repmat(tmpl,1,numel(measures));
            for measureIndex = 1:numel(measures)
                measure = measures(measureIndex);
                selector = 'catalogueMeasure';
                if ~measure.enabled, selector = 'catalogueMeasureUnavailable'; end
                entries(measureIndex).measureId = measure.measureId;
                entries(measureIndex).scientificAnnotation = NMResultsViewerScientificAnnotation.updateFeatureMeasure( ...
                    baseAnnotation,measure.measureId,measure.measureId,logical(measure.enabled),selector, ...
                    measure.sourceField,measure.seSourceField);
            end
        end
        function row = modelFeatureInspectionFeatureRowTemplate()
            tmpl = struct('rowId','','contextId','','measureId','','componentId','','componentIndex',NaN,'componentLabel','','featureIndex',NaN,'featureName','', ...
                'displayValue',NaN,'displaySE',NaN,'meanWeight',NaN,'seWeight',NaN, ...
                'crossValidationRatio',NaN,'featureSelectionProbability',NaN, ...
                'reliabilityProbability95CI',NaN,'signConsistency',NaN,'signConsistencyZ',NaN, ...
                'signConsistencyLogP',NaN,'signConsistencyLogQ',NaN, ...
                'spearmanAssociation',NaN,'pearsonAssociation',NaN, ...
                'spearmanLogP',NaN,'pearsonLogP',NaN,'spearmanLogQ',NaN,'pearsonLogQ',NaN, ...
                'permutationZ',NaN,'permutationLogP',NaN,'permutationLogQ',NaN, ...
                'analyticalLogP',NaN,'analyticalLogQ',NaN, ...
                'thresholdPassed',false,'barState','missing','labelState','missing','errorBarState','missing', ...
                'sortSignedRank',NaN,'sortAbsRank',NaN,'featureKind','tabular','provenanceId','', ...
                'tooltipTitle','','tooltipSubtitle','','tooltipMetricPrimary',NaN,'tooltipMetricPrimaryLabel','', ...
                'tooltipMetricSE',NaN,'tooltipMetricSELabel','', 'tooltipThresholdLabel','', ...
                'tooltipThresholdPassed',false,'tooltipRankSigned',NaN,'tooltipRankAbsolute',NaN, ...
                'tooltipSelectionProbability',NaN,'tooltipStabilitySummary','', ...
                'tooltipSourceField','','tooltipProvenanceSummary','');
            row = tmpl;
        end

        function d = modelFeatureInspectionDistributionTemplate()
            tmpl = struct('contextId','','measureId','','label','','binEdges',[],'counts',[], ...
                'sourceField','','enabled',false,'disabledReason','');
            d = tmpl;
        end

        function m = modelFeatureInspectionMatrixTemplate()
            % modelFeatureInspectionMatrixTemplate  Fixed-schema feature-relation descriptor.
            % NMResultsViewerFeatureRelationTools owns the matrix schema.
            m = NMResultsViewerFeatureRelationTools.matrixTemplate();
        end

        function n = modelFeatureInspectionNetworkTemplate()
            % modelFeatureInspectionNetworkTemplate  Fixed-schema graph descriptor bound to an invariant relation matrix.
            tmpl = struct('networkId','','contextId','','componentId','','componentIndex',NaN,'componentLabel','', ...
                'componentApplicability','invariant','componentSelectionAffectsContent',false, ...
                'matrixId','','layoutKind','feature_network','nodeRows',[],'edgeRows',[], ...
                'sourceField','','available',false,'enabled',false,'disabledReason','');
            n = tmpl;
        end

        function v = modelFeatureInspectionVolcanoTemplate()
            tmpl = struct('volcanoId','','contextId','','xMeasureId','cross_validation_ratio', ...
                'yMeasureId','sign_consistency_logp','pointRows',[],'enabled',false,'disabledReason','');
            v = tmpl;
        end

        function s = modelFeatureInspectionSpatialTemplate()
            tmpl = struct('spatialMapId','','contextId','','componentId','','componentIndex',NaN,'componentLabel','','measureId','','mapKind','tabular', ...
                'artifactKind','descriptor_only','artifactPath','','maskFile','','surfaceFile','', ...
                'atlasFile','','atlasDescriptorFile','','hasAtlasCoordinates',false, ...
                'roiSpatialDomain','','roiIdentityModel','','roiSpatialReferenceIdentity','', ...
                'hasIndexedVoxelPositions',false,'hasNodeCoordinates',false, ...
                'nodeCount',0,'edgeCount',0,'coordinateSpace','','coordinateUnits','', ...
                'representationFrontend','tabular','hasPositiveValues',false,'hasNegativeValues',false, ...
                'thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN, ...
                'viewerMode','none','enabled',false,'disabledReason','');
            s = tmpl;
        end

        function p = modelPerformancePermutationPayloadTemplate()
            % modelPerformancePermutationPayloadTemplate  Fixed schema for model-level permutation histograms.
            %
            % The payload is consumed by the browser Model performance viewspace and
            % by report/export code. Rows contain model-level null distributions and
            % observed criteria; no feature-label or feature-subset state is stored.
            row = NMResultsViewerTools.modelPerformancePermutationRowTemplate();
            p = struct('ok',false,'message','No model-permutation histogram payload is available.', ...
                'schemaVersion',2,'analysisIndex',NaN,'targetIndex',NaN,'resultTargetIndex',NaN,'selectedPermutationId','', ...
                'criterionLabel','Optimization criterion','criterionShortLabel','OPT','rows',row([]),'sourceFields',{{}}, ...
                'visContextCount',0,'collapsedDuplicateCount',0,'conflictingDuplicateCount',0, ...
                'diagnosticMessage','');
        end

        function [resultTargetIndex, ok, message] = modelPerformancePermutationResultTargetIndex(NM, analysisIndex, targetIndex)
            % modelPerformancePermutationResultTargetIndex  Map public/native target identity to compact VIS result position.
            resultTargetIndex = NaN;
            ok = false;
            message = '';
            requested = double(targetIndex);
            % nm2-allow: public Results Viewer selector boundary validates the requested native target identity
            if ~isscalar(requested) || ~isfinite(requested) || requested < 1 || requested ~= round(requested)
                message = 'The selected target index is invalid for model-permutation extraction.';
                return;
            end
            opts = NMResultsViewerTools.targetOptions(NM, analysisIndex);
            hit = find([opts.index] == requested, 1, 'first');
            if isempty(hit)
                message = sprintf('Target label %d is not available in the selected analysis.', requested);
                return;
            end
            option = opts(hit);
            if ~option.enabled
                message = sprintf('Target label %d is disabled: %s', requested, option.reason);
                return;
            end
            resultTargetIndex = double(option.resultIndex);
            if ~isscalar(resultTargetIndex) || ~isfinite(resultTargetIndex) || resultTargetIndex < 1 || resultTargetIndex ~= round(resultTargetIndex)
                error('NMResultsViewerTools:InvalidPermutationTargetMap', ...
                    'Enabled native target %d has invalid compact result identity.',requested);
            end
            ok = true;
        end
        function avail = modelPerformancePermutationAvailabilityImpl(NM, analysisIndex, targetIndex, modelSource)
            % modelPerformancePermutationAvailabilityImpl  Probe writer-conditioned VIS permutation material for one target.
            avail = struct('ok',false,'message','No VIS model-permutation fields detected.', ...
                'paths',{{}},'targetIndex',double(targetIndex),'resultTargetIndex',NaN);
            % nm2-allow: public availability boundary validates the requested completed-analysis index
            if ~isscalar(analysisIndex) || ~isfinite(analysisIndex) || analysisIndex < 1 || analysisIndex ~= round(analysisIndex) || analysisIndex > numel(NM.analysis)
                avail.message = 'No valid analysis is available for model-permutation availability checking.';
                return;
            end
            [resultTargetIndex, targetOk, targetMessage] = NMResultsViewerTools.modelPerformancePermutationResultTargetIndex(NM, analysisIndex, targetIndex);
            if ~targetOk
                avail.message = targetMessage;
                return;
            end
            avail.resultTargetIndex = resultTargetIndex;
            entries = NMResultsViewerTools.modelPerformancePermutationVisEntries(NM.analysis{analysisIndex}, resultTargetIndex, modelSource);
            if isempty(entries)
                avail.message = 'The selected analysis has no persisted VIS model-permutation material for this target.';
                return;
            end
            avail.ok = true;
            avail.paths = {entries.path};
            avail.message = sprintf('Model-permutation material detected in %d VIS context(s).', numel(entries));
        end
        function payload = modelPerformancePermutationPayloadImpl(NM, analysisIndex, targetIndex, classIndex, modelSource)
            % modelPerformancePermutationPayloadImpl  Project writer-defined VIS model-permutation arrays into one model-level payload.
            payload = NMResultsViewerTools.modelPerformancePermutationPayloadTemplate();
            payload.analysisIndex = double(analysisIndex);
            payload.targetIndex = double(targetIndex);
            % nm2-allow: public payload boundary validates the requested completed-analysis index
            if ~isscalar(analysisIndex) || ~isfinite(analysisIndex) || analysisIndex < 1 || analysisIndex ~= round(analysisIndex) || analysisIndex > numel(NM.analysis)
                payload.message = 'No valid analysis is available for model-permutation extraction.';
                return;
            end
            [resultTargetIndex, targetOk, targetMessage] = NMResultsViewerTools.modelPerformancePermutationResultTargetIndex(NM, analysisIndex, targetIndex);
            if ~targetOk
                payload.message = targetMessage;
                return;
            end
            payload.resultTargetIndex = resultTargetIndex;
            entries = NMResultsViewerTools.modelPerformancePermutationVisEntries(NM.analysis{analysisIndex}, resultTargetIndex, modelSource);
            if isempty(entries)
                payload.message = 'The selected analysis has no persisted VIS model-permutation material for this target.';
                return;
            end
            criterion = NMResultsViewerTools.modelOptimizationCriterionIdentity(NM,analysisIndex);
            groupNames = NMResultsViewerTools.groupNamesForAnalysis(NM,analysisIndex);
            classLabel = NMResultsViewerTools.classifierLabel(NM.analysis{analysisIndex},classIndex);
            rows = NMResultsViewerTools.modelPerformancePermutationRowsFromVis(entries(1).vis, analysisIndex, targetIndex, classIndex, classLabel, criterion, groupNames);
            for ee = 2:numel(entries)
                replicaRows = NMResultsViewerTools.modelPerformancePermutationRowsFromVis(entries(ee).vis, analysisIndex, targetIndex, classIndex, classLabel, criterion, groupNames);
                if ~isequaln(rows,replicaRows)
                    error('NMResultsViewerTools:PermutationReplicaMismatch', ...
                        'VIS model-permutation replicas differ between %s and %s.',entries(1).path,entries(ee).path);
                end
            end
            payload.rows = rows;
            payload.criterionLabel = criterion.label;
            payload.criterionShortLabel = criterion.shortLabel;
            sourceFields = {};
            for rr = 1:numel(rows)
                sourceFields = [sourceFields rows(rr).sourceFields]; %#ok<AGROW>
            end
            payload.sourceFields = unique(sourceFields,'stable');
            payload.visContextCount = numel(entries);
            payload.collapsedDuplicateCount = max(0,(numel(entries)-1)*numel(rows));
            payload.conflictingDuplicateCount = 0;
            payload.ok = ~isempty(rows);
            if payload.ok
                primaryIndex = find(~strcmp({rows.mode},'extra_label'),1,'first');
                if isempty(primaryIndex), primaryIndex = 1; end
                payload.selectedPermutationId = rows(primaryIndex).permutationId;
                payload.message = sprintf('Model-permutation payload contains %d model-level histogram comparison(s).',numel(rows));
                if payload.collapsedDuplicateCount > 0
                    payload.diagnosticMessage = sprintf('%d identical modality-level VIS replica(s) were collapsed.',payload.collapsedDuplicateCount);
                    payload.message = sprintf('%s %s',payload.message,payload.diagnosticMessage);
                end
            else
                payload.message = 'No persisted model-permutation histogram rows were found for the selected context.';
            end
        end

        function rows = modelPerformancePermutationRowsFromVis(v, analysisIndex, targetIndex, classIndex, classLabel, criterion, groupNames)
            % modelPerformancePermutationRowsFromVis  Project one writer-defined VIS permutation replica.
            cls = double(classIndex);
            % nm2-allow: public classifier selector boundary validates the requested compact classifier position
            if ~isscalar(cls) || ~isfinite(cls) || cls < 1 || cls ~= round(cls)
                error('NMResultsViewerTools:InvalidPermutationClassifier','Permutation classifier index must be one positive integer.');
            end
            template = NMResultsViewerTools.modelPerformancePermutationRowTemplate();
            rows = repmat(template,1,0);
            contextId = sprintf('analysis_%d_target_%d',analysisIndex,targetIndex);
            axisLabel = sprintf('Optimization criterion: %s',criterion.label);

            % nm2-allow: nk_VisModelsC conditionally writes the ordinary model-permutation family as one atomic triplet
            if isfield(v,'PermModel_Crit_Global')
                row = NMResultsViewerTools.modelPerformancePermutationRowTemplate();
                row = NMResultsViewerTools.fillModelPermutationRow(row,v.PermModel_Crit_Global,v.ObsModel_Eval_Global,v.PermModel_Eval_Global,cls);
                row.permutationId = 'model_permutation_global';
                row.contextId = contextId;
                row.label = 'Model permutation';
                row.mode = 'global';
                row.classIndex = cls;
                row.classLabel = classLabel;
                row.criterionLabel = criterion.label;
                row.criterionShortLabel = criterion.shortLabel;
                row.criterionAxisLabel = axisLabel;
                row.sourceFields = {'PermModel_Crit_Global','ObsModel_Eval_Global','PermModel_Eval_Global'};
                rows(end+1) = row; %#ok<AGROW>
            end

            % nm2-allow: nk_VisModelsC writes both multiflag permutation families together.
            hasMulti = isfield(v,'PermModel_Crit_Global_Multi');
            if hasMulti
                row = NMResultsViewerTools.modelPerformancePermutationRowTemplate();
                row = NMResultsViewerTools.fillModelPermutationRow(row,v.PermModel_Crit_Global_Multi,v.ObsModel_Eval_Global_Multi,v.PermModel_Eval_Global_Multi,1);
                row.permutationId = 'model_permutation_multi_group';
                row.contextId = contextId;
                row.label = 'Multi-group model permutation';
                row.mode = 'multi_group';
                row.classIndex = NaN;
                row.classLabel = 'Multi-group';
                row.criterionLabel = criterion.label;
                row.criterionShortLabel = criterion.shortLabel;
                row.criterionAxisLabel = axisLabel;
                row.sourceFields = {'PermModel_Crit_Global_Multi','ObsModel_Eval_Global_Multi','PermModel_Eval_Global_Multi'};
                rows(end+1) = row; %#ok<AGROW>
            end

            if hasMulti
                nRows = size(v.PermModel_Crit_Global_Multi_Bin,1);
                if numel(groupNames) < nRows
                    error('NMResultsViewerTools:PermutationGroupAxisMismatch', ...
                        'Permutation one-vs-rest rows require %d group names; analysis exposes %d.',nRows,numel(groupNames));
                end
                for ii = 1:nRows
                    row = NMResultsViewerTools.modelPerformancePermutationRowTemplate();
                    row = NMResultsViewerTools.fillModelPermutationRow(row,v.PermModel_Crit_Global_Multi_Bin,v.ObsModel_Eval_Global_Multi_Bin,v.PermModel_Eval_Global_Multi_Bin,ii);
                    row.permutationId = sprintf('model_permutation_class_%d_vs_rest',ii);
                    row.contextId = contextId;
                    row.label = sprintf('Class %s vs. rest: model permutation',groupNames{ii});
                    row.mode = 'class_vs_rest';
                    row.classIndex = ii;
                    row.classLabel = groupNames{ii};
                    row.criterionLabel = criterion.label;
                    row.criterionShortLabel = criterion.shortLabel;
                    row.criterionAxisLabel = axisLabel;
                    row.sourceFields = {'PermModel_Crit_Global_Multi_Bin','ObsModel_Eval_Global_Multi_Bin','PermModel_Eval_Global_Multi_Bin'};
                    rows(end+1) = row; %#ok<AGROW>
                end
            end

            % nm2-allow: nk_VisModelsC writes ExtraL only when extra-label generalization material was produced
            if isfield(v,'ExtraL') && ~isempty(v.ExtraL)
                for ii = 1:numel(v.ExtraL)
                    e = v.ExtraL(ii);
                    row = NMResultsViewerTools.modelPerformancePermutationRowTemplate();
                    row = NMResultsViewerTools.fillModelPermutationRow(row,e.VCV2MPERM_EVALFUNC_GLOBAL,e.VCV2MORIG_EVALFUNC_GLOBAL,e.VCV2MPERM_GLOBAL,cls);
                    row.permutationId = sprintf('model_permutation_extra_label_%d',ii);
                    row.contextId = contextId;
                    row.label = sprintf('Extra-label generalization: %s',e.LABEL_NAME);
                    row.mode = 'extra_label';
                    row.classIndex = cls;
                    row.classLabel = classLabel;
                    row.extraLabelIndex = ii;
                    row.extraLabel = e.LABEL_NAME;
                    row.criterionLabel = criterion.label;
                    row.criterionShortLabel = criterion.shortLabel;
                    row.criterionAxisLabel = axisLabel;
                    row.histogramFaceColor = '#fde68a';
                    row.densityColor = '#a16207';
                    row.sourceFields = {'ExtraL.VCV2MPERM_EVALFUNC_GLOBAL','ExtraL.VCV2MORIG_EVALFUNC_GLOBAL','ExtraL.VCV2MPERM_GLOBAL'};
                    rows(end+1) = row; %#ok<AGROW>
                end
            end
        end

        function row = modelPerformancePermutationRowTemplate()
            row = struct('permutationId','','contextId','','label','','mode','global', ...
                'modalityIndex',NaN,'modalityLabel','','classIndex',NaN,'classLabel','', ...
                'extraLabelIndex',NaN,'extraLabel','','criterionLabel','Optimization criterion','criterionShortLabel','OPT','criterionAxisLabel','Optimization criterion', ...
                'observedValue',NaN,'nullValues',[],'permutationEvalValues',[], ...
                'nPermutations',NaN,'exceedanceCount',NaN,'legacyPValue',NaN,'minimumPValue',NaN, ...
                'pValue',NaN,'pValueDisplay','', ...
                'histogramFaceColor','#93c5fd','densityColor','#0284c7','observedColor','#dc2626', ...
                'sourceFields',{{}});
        end

        function row = fillModelPermutationRow(row, nullRaw, observedRaw, evalRaw, rowIndex)
            % fillModelPermutationRow  Read one writer-defined classifier row from model-permutation arrays.
            % nm2-allow: persisted permutation arrays use classifier rows; selector position must address that fixed axis
            if rowIndex > size(nullRaw,1) || rowIndex > size(evalRaw,1) || rowIndex > numel(observedRaw)
                error('NMResultsViewerTools:PermutationClassifierAxisMismatch', ...
                    'Requested classifier %d exceeds a persisted model-permutation classifier axis.',rowIndex);
            end
            nullVals = double(nullRaw(rowIndex,:));
            evalVals = double(evalRaw(rowIndex,:));
            row.nullValues = nullVals(isfinite(nullVals));
            row.permutationEvalValues = evalVals(isfinite(evalVals));
            row.observedValue = double(observedRaw(rowIndex));
            finiteEval = evalVals(isfinite(evalVals));
            row.nPermutations = numel(finiteEval);
            if row.nPermutations > 0
                row.exceedanceCount = sum(finiteEval ~= 0);
                row.legacyPValue = row.exceedanceCount / row.nPermutations;
                row.minimumPValue = 1 / (row.nPermutations + 1);
                row.pValue = (row.exceedanceCount + 1) / (row.nPermutations + 1);
                if row.exceedanceCount == 0
                    row.pValueDisplay = sprintf('P = %.4g (minimum; 0/%d exceedances)',row.pValue,row.nPermutations);
                else
                    row.pValueDisplay = sprintf('P = %.4g (%d/%d exceedances; corrected)',row.pValue,row.exceedanceCount,row.nPermutations);
                end
            else
                row.pValueDisplay = 'P unavailable';
            end
        end

        function p = modelFeatureInspectionPermutationPayload()
            p = struct('ok',false,'message','Model-permutation histogram payload is not extracted in Stage 10A.1.', ...
                'contextId','','sourceFields',{{}},'rows',[]);
        end

        function p = modelFeatureInspectionExtraLabelPayload()
            p = struct('ok',false,'message','Extra-label generalization payload is not extracted in Stage 10A.1.', ...
                'contextId','','sourceFields',{{}},'rows',[]);
        end

        function c = emptyModelFeatureInspectionComponentAnalysis()
            c = struct('ok',false,'message','No component-wise VIS stream detected.', ...
                'componentTable',repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,0), ...
                'modalityComponentTable',repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,0), ...
                'modalityShareTable',repmat(NMResultsViewerTools.modelFeatureInspectionModalityShareTemplate(),1,0), ...
                'componentModalityTable',repmat(NMResultsViewerTools.modelFeatureInspectionComponentModalityTemplate(),1,0), ...
                'fractionatedDecisionTable',repmat(NMResultsViewerTools.modelFeatureInspectionFractionatedDecisionTemplate(),1,0), ...
                'fractionatedDecisionAvailable',false, ...
                'diagnostics',repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0));
        end

        function row = modelFeatureInspectionComponentRowTemplate()
            tmpl = struct('contextId','','drSourceIndex',NaN,'drSourceModalityIndex',NaN,'drSourceLabel','', ...
                'componentIndex',NaN,'componentLabel','','kept',false,'selectionRatio',NaN,'presencePercent',NaN, ...
                'rawPresencePercent',NaN,'observedExpectedPresenceRatio',NaN, ...
                'adjustedExcessPresencePercent',NaN,'presenceZScore',NaN, ...
                'meanReferenceCorrelation',NaN,'referenceCorrelationLo95',NaN,'referenceCorrelationHi95',NaN, ...
                'meanPermutationLogP',NaN,'permutationLogPLo95',NaN,'permutationLogPHi95',NaN, ...
                'medianL2Share',NaN,'meanL2Share',NaN,'l2ShareLo95',NaN,'l2ShareHi95',NaN, ...
                'coverageN',NaN,'coverageTotal',NaN,'thresholdPassed',true, ...
                'barState','active','labelState','active','sourceFields',{{}});
            row = tmpl;
        end

        function row = modelFeatureInspectionModalityShareTemplate()
            tmpl = struct('contextId','','modalityIndex',NaN,'modalityLabel','', ...
                'medianShare',NaN,'meanShare',NaN,'lo95',NaN,'hi95',NaN, ...
                'coverageN',NaN,'coverageTotal',NaN,'sourceField','');
            row = tmpl;
        end

        function row = modelFeatureInspectionComponentModalityTemplate()
            tmpl = struct('contextId','','componentIndex',NaN,'componentLabel','', ...
                'modalityIndex',NaN,'modalityLabel','','medianShare',NaN,'meanShare',NaN, ...
                'coverageN',NaN,'coverageTotal',NaN,'sourceField','');
            row = tmpl;
        end

        function available = modelFeatureInspectionFractionatedAvailable(A,selectedContexts,targetIndex,classIndex)
            % nk_VisModelsC writes the three fractionated moment families atomically
            % only for eligible component-wise permutation/significance runs.
            available = false;
            if isempty(selectedContexts), return; end
            % nm2-allow: feature-context producer permits multiple sources only for a shared early-fusion component axis
            if numel(selectedContexts) > 1 && ~strcmp(selectedContexts(1).fusionMode,'early')
                return; % Intermediate-fusion components require a physical feature source.
            end
            v = NMResultsViewerTools.modelFeatureInspectionVisEntry(A, ...
                selectedContexts(1).visRowIndex,targetIndex);
            % nm2-allow: nk_VisModelsC conditionally persists fractionated decision moments
            if ~isfield(v,'FracDec_CV2_mean'), return; end
            % nm2-allow: persisted VIS classifier cell axis is conditional on decomposition count
            available = classIndex <= numel(v.FracDec_CV2_mean) && ...
                ~isempty(v.FracDec_CV2_mean{classIndex});
        end

    end

    methods (Static)
        function result = getModelFeatureInspectionFractionatedClusters(NM,inspection,spec,mode,clusterCount,autoOptions)
            % Descriptive clustering of canonical CV Dx; complete shared-component
            % policy retains every subject without imputing structural missingness.
            subjectTemplate=struct('caseId','','cluster',0,'score',NaN,'observed','','predicted','','error',NaN);
            groupTemplate=struct('cluster',0,'subjects',0,'performanceN',0,'meanScore',NaN,'errorMetric',NaN);
            profileTemplate=struct('cluster',0,'componentIndex',0,'componentLabel','','finiteN',0,'signedMean',NaN,'absoluteMean',NaN,'populationMean',NaN,'difference',NaN);
            result=struct('ok',false,'message','','mode',mode,'clusterCount',0, ...
                'caseIds',{{}},'orderedCaseIds',{{}},'orderedClusters',[], ...
                'componentIndices',[],'subjectRows',subjectTemplate([]), ...
                'groups',groupTemplate([]),'componentProfiles',profileTemplate([]), ...
                'profileComponentOrder',[],'profileMetricRanges',struct('signedMean',0,'difference',0,'absoluteMean',0), ...
                'optimization',struct('criterion','','testedClusters',[],'values',[],'selectedClusters',0,'replicates',0,'direction',''), ...
                'consensusHeatmap',struct('values',[],'subjectCount',0,'binEdges',[]), ...
                'performanceMetric','', ...
                'distanceDefinition','Root mean squared signed Dx difference on components finite for every subject.');
            scores=NMResultsViewerTools.getModelFeatureInspectionFractionatedDecisionPayload(NM,inspection,'all');
            if ~scores.ok
                result.message=scores.message;
                return;
            end
            X=scores.mean;
            retained=all(isfinite(X),1);
            n=size(X,1);
            requiredSubjects=clusterCount;
            if ~isempty(autoOptions),requiredSubjects=autoOptions.maxClusters;end
            if n<requiredSubjects || nnz(retained)<2
                result.message=sprintf(['Clustering requires at least %d subjects and two retained components ' ...
                    'with finite Dx for every subject. Found %d such components among %d. ' ...
                    'Missing contributions are not imputed.'],requiredSubjects,nnz(retained),size(X,2));
                return;
            end
            X=X(:,retained);
            if strcmp(mode,'relative')
                denominator=sum(abs(X),2);
                if any(denominator==0)
                    result.message='Relative profiles are undefined for subjects with zero total absolute Dx on the common components.';
                    return;
                end
                X=X./denominator;
                result.distanceDefinition='Root mean squared difference between within-subject L1-normalized signed Dx profiles on complete components.';
            end
            dist=NMHierarchicalClusteringTools.rmsDistances(X);
            [linkage,order]=NMHierarchicalClusteringTools.averageLinkageOptimalOrder(dist,(1:n)');
            if ~isempty(autoOptions)
                [result.optimization,consensus]=NMHierarchicalClusteringTools.selectCount(dist,X,linkage, ...
                    autoOptions.minClusters,autoOptions.maxClusters,autoOptions.criterion,autoOptions.bootstrapIterations);
                clusterCount=result.optimization.selectedClusters;
                if ~isempty(consensus)
                    % Display projection of the selected-k consensus, never a second bootstrap fit.
                    % Each displayed cell is the exact mean co-assignment frequency
                    % of the corresponding contiguous optimal-leaf-order subject blocks.
                    nBins=min(n,72);
                    edges=floor((0:nBins)*n/nBins);
                    orderedConsensus=consensus(order,order);
                    heat=zeros(nBins,nBins);
                    for rr=1:nBins
                        rows=(edges(rr)+1):edges(rr+1);
                        for cc=1:nBins
                            cols=(edges(cc)+1):edges(cc+1);
                            block=orderedConsensus(rows,cols);
                            heat(rr,cc)=mean(block(:));
                        end
                    end
                    result.consensusHeatmap=struct('values',heat,'subjectCount',n,'binEdges',edges);
                end
            end
            [orderedAssignments,k]=NMHierarchicalClusteringTools.extractClusters(linkage,order,'fixed_count',clusterCount,0);
            result.ok=true;
            result.message='Exploratory average-linkage clusters; no subgroup validation or inferential test.';
            result.caseIds=scores.caseIds;
            result.orderedCaseIds=scores.caseIds(order);
            result.orderedClusters=orderedAssignments;
            result.componentIndices=scores.componentIndices(retained);
            result.clusterCount=k;
            perf=NMResultsViewerTools.modelInterpretationSubjectScores(NM,spec);
            if perf.ok
                if strcmp(perf.modelKind,'regression')
                    result.performanceMetric='Mean absolute prediction error';
                else
                    result.performanceMetric='Misclassification rate (%)';
                end
            else
                result.performanceMetric='Performance unavailable';
            end
            subjectRows=repmat(subjectTemplate,1,n);
            for jj=1:n
                caseId=scores.caseIds{order(jj)};
                subjectRows(jj).caseId=caseId;
                subjectRows(jj).cluster=orderedAssignments(jj);
                if perf.ok
                    matches=find(strcmp({perf.rows.caseId},caseId));
                    if numel(matches)==1
                        matched=perf.rows(matches);
                        subjectRows(jj).score=matched.score;
                        subjectRows(jj).observed=matched.expected;
                        subjectRows(jj).predicted=matched.predicted;
                        if strcmp(perf.modelKind,'regression')
                            observed=matched.observedNumeric;
                            if isfinite(observed)&&isfinite(matched.score)
                                subjectRows(jj).error=abs(matched.score-observed);
                            end
                        elseif ~isempty(matched.expected)&&~isempty(matched.predicted)
                            subjectRows(jj).error=double(~strcmp(matched.expected,matched.predicted))*100;
                        end
                    end
                end
            end
            result.subjectRows=subjectRows;
            groups=repmat(groupTemplate,1,k);
            for jj=1:k
                member=orderedAssignments==jj;
                groupScores=[subjectRows(member).score];
                groupErrors=[subjectRows(member).error];
                groups(jj).cluster=jj;
                groups(jj).subjects=nnz(member);
                groups(jj).performanceN=nnz(isfinite(groupErrors));
                if any(isfinite(groupScores)),groups(jj).meanScore=mean(groupScores(isfinite(groupScores)));end
                if any(isfinite(groupErrors)),groups(jj).errorMetric=mean(groupErrors(isfinite(groupErrors)));end
            end
            result.groups=groups;
            allDx=scores.mean;
            indices=scores.componentIndices;
            profile=repmat(profileTemplate,1,k*numel(indices));
            for cc=1:numel(indices)
                values=allDx(:,cc);
                available=isfinite(values);
                populationMean=NaN;
                if any(available),populationMean=mean(values(available));end
                for gg=1:k
                    members=order(orderedAssignments(:)==gg);
                    groupValues=values(members);
                    finite=isfinite(groupValues);
                    pos=(gg-1)*numel(indices)+cc;
                    profile(pos).cluster=gg;
                    profile(pos).componentIndex=indices(cc);
                    profile(pos).componentLabel=scores.componentLabels{cc};
                    profile(pos).finiteN=nnz(finite);
                    profile(pos).populationMean=populationMean;
                    if any(finite)
                        profile(pos).signedMean=mean(groupValues(finite));
                        profile(pos).absoluteMean=mean(abs(groupValues(finite)));
                        profile(pos).difference=profile(pos).signedMean-populationMean;
                    end
                end
            end
            result.componentProfiles=profile;
            % Cluster-major rows preserve the retained component axis.
            importance=reshape([profile.signedMean],numel(indices),k);
            importance=max(abs(importance),[],2,'omitnan');importance(~isfinite(importance))=0;
            [~,ranking]=sortrows([-importance(:),double(indices(:))]);
            result.profileComponentOrder=indices(ranking);
            for metric={'signedMean','difference','absoluteMean'}
                field=metric{1};result.profileMetricRanges.(field)=max([1e-6,abs([profile.(field)])],[],'omitnan');
            end
        end

        function scores = getModelFeatureInspectionFractionatedDecisionPayload(NM,inspection,scope)
            % Public API: project the persisted subject-by-component Dx statistics
            % using the already resolved Feature Inspection selection and case axis.
            % scope = 'selected' for one retained component, or 'all' for the
            % complete subject-by-retained-component matrix (API callers).
            % Does not retrain, recompute, normalize or impute missing contributions.
            scores = struct('ok',false,'message','Fractionated decision scores are not available.', ...
                'contextId',inspection.selectedFeatureContextId, ...
                'componentIndices',[],'componentLabels',{{}},'caseIds',{{}}, ...
                'mean',[],'sd',[],'se',[],'nValid',[], ...
                'coverageAvailable',false,'selectedColumn',NaN,'populationRows',struct([]));
            if ~inspection.componentAnalysis.fractionatedDecisionAvailable, return; end
            selected = inspection.selectedFeatureContext;
            if selected.isCombined && ~strcmp(selected.fusionMode,'early')
                scores.message = 'Select a physical feature source for intermediate-fusion decision contributions.';
                return;
            end
            if selected.isCombined
                source = inspection.contexts(1);
            else
                source = selected;
            end
            v = NMResultsViewerTools.modelFeatureInspectionVisEntry( ...
                NM.analysis{inspection.analysisIndex},source.visRowIndex,inspection.resultTargetIndex);
            h = inspection.classifierIndex;
            meanDx = double(v.FracDec_CV2_mean{h});
            sdDx = double(v.FracDec_CV2_sd{h});
            seDx = double(v.FracDec_CV2_se{h});
            % CompKept is the writer-owned original component axis; the matrices
            % use its retained-column ordering, not original component indices.
            kept = v.CompKept{h};
            componentIndices = find(kept(:) ~= 0)';
            nCases = numel(NMResultsViewerTools.containerCanonicalCases(NM));
            % nm2-allow: persisted VIS matrix axes must match authoritative case and CompKept coordinates
            if size(meanDx,1) ~= nCases || size(meanDx,2) ~= numel(componentIndices) || ...
                    ~isequal(size(meanDx),size(sdDx),size(seDx))
                error('NMResultsViewerTools:FractionatedDecisionAxisMismatch', ...
                    'Persisted fractionated decision moments disagree with the case or retained-component axis.');
            end
            switch scope
                case 'selected'
                    columns = inspection.selectedBackprojectionComponentColumn;
                    selectedColumn = 1;
                case 'all'
                    columns = 1:numel(componentIndices);
                    selectedColumn = inspection.selectedBackprojectionComponentColumn;
                otherwise
                    error('NMResultsViewerTools:UnknownFractionatedDecisionScope', ...
                        'Fractionated decision score scope must be selected or all.');
            end
            scores.ok = true;
            scores.message = '';
            scores.contextId = source.contextId;
            scores.componentIndices = componentIndices(columns);
            scores.componentLabels = arrayfun(@(k)sprintf('Component %d',k), ...
                scores.componentIndices,'UniformOutput',false);
            scores.caseIds = NMResultsViewerTools.containerCanonicalCases(NM);
            scores.mean = meanDx(:,columns);
            scores.sd = sdDx(:,columns);
            scores.se = seDx(:,columns);
            scores.selectedColumn = selectedColumn;
            % nm2-allow: FracDec_CV2_n is added by the current writer; pre-existing saved VIS results have no persisted counts
            if isfield(v,'FracDec_CV2_n')
                counts = v.FracDec_CV2_n{h};
                if ~isequal(size(counts),size(meanDx))
                    error('NMResultsViewerTools:FractionatedDecisionCountAxisMismatch', ...
                        'Persisted fractionated model counts disagree with the decision-score axis.');
                end
                scores.nValid = double(counts(:,columns));
                scores.coverageAvailable = true;
            end
            if strcmp(scope,'all')
                [scores.populationRows,scores.absoluteMean,scores.subjectMagnitudeOrder, ...
                    scores.componentMagnitudeOrder,scores.populationOrder,scores.maxAbsoluteDx] = ...
                    NMResultsViewerTools.fractionatedPopulationRows(scores);
                signed=scores.mean;signed(~isfinite(signed))=NaN;
                [~,scores.profileOrder.signed_desc]=sort(signed,2,'descend','MissingPlacement','last');
                [~,scores.profileOrder.signed_asc]=sort(signed,2,'ascend','MissingPlacement','last');
                [~,scores.profileOrder.absolute_desc]=sort(scores.absoluteMean,2,'descend','MissingPlacement','last');
                [~,scores.profileOrder.absolute_asc]=sort(scores.absoluteMean,2,'ascend','MissingPlacement','last');
            end
        end

        function [rows,absolute,subjectOrder,componentOrder,ranking,maxAbsolute] = fractionatedPopulationRows(scores)
            % Finite zeros contribute to N; NaNs and infinities do not.
            X=scores.mean;finite=isfinite(X);absolute=abs(X);absolute(~finite)=0;
            mass=sum(absolute,1);n=sum(finite,1);q=sum(absolute.^2,1);
            [~,subjectOrder]=sortrows([-sum(absolute,2),(1:size(X,1))']);
            [~,componentOrder]=sortrows([-mass(:),(1:size(X,2))']);
            subjectOrder=subjectOrder';componentOrder=componentOrder';
            maxAbsolute=max([0;absolute(:)]);
            effective=mass.^2./q;meanAbsolute=mass./n;
            metrics={'concentration','effectiveSubjects','meanAbsoluteDx','positivePct', ...
                'negativePct','zeroPct','observed','coveragePct'};
            values=[(1-effective./n)',effective',meanAbsolute', ...
                (100*sum(X>0 & finite,1)./n)',(100*sum(X<0 & finite,1)./n)', ...
                (100*sum(X==0 & finite,1)./n)',n',(100*n/numel(scores.caseIds))'];
            indices=scores.componentIndices(:);
            rows=cell2struct([num2cell(indices),scores.componentLabels(:),num2cell(values)], ...
                [{'index','component'},metrics],2);
            absolute(~finite)=NaN;
            ranking=struct();
            for j=1:numel(metrics)
                v=values(:,j);missing=~isfinite(v);v(missing)=0;
                [~,up]=sortrows([double(missing),v,indices]);
                [~,down]=sortrows([double(missing),-v,indices]);
                ranking.(metrics{j})=struct('ascending',up','descending',down');
            end
            ordinal=(1:numel(indices))';
            ranking.index=struct('ascending',ordinal','descending',flipud(ordinal)');
            ranking.component=ranking.index;
        end

    end

    methods (Static, Access = private)
        function row = modelFeatureInspectionFractionatedDecisionTemplate()
            tmpl = struct('contextId','','componentIndex',NaN,'classIndex',NaN, ...
                'meanDecisionFraction',NaN,'seDecisionFraction',NaN,'sdDecisionFraction',NaN,'sourceField','');
            row = tmpl;
        end

        function d = modelFeatureInspectionDiagnosticTemplate()
            tmpl = struct('severity','','source','','message','','legacyField','','contextId','', ...
                'stackFunction1','','stackFunction2','','stackFunction3','');
            d = tmpl;
        end

        function d = modelFeatureInspectionDiagnostic(severity, source, message, legacyField, contextId, stack1, stack2, stack3)
            d = NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate();
            d.severity = severity;
            d.source = source;
            d.message = message;
            d.legacyField = legacyField;
            d.contextId = contextId;
            d.stackFunction1 = stack1;
            d.stackFunction2 = stack2;
            d.stackFunction3 = stack3;
        end
        function [payload,selection] = modelFeatureInspectionResolveScientificSelection(NM,spec,payload,payloadScope,catalogueScope)
            % modelFeatureInspectionResolveScientificSelection  Resolve the authoritative Feature Inspection selection.
            %
            % This function owns analysis, public-target, VIS-result-target,
            % classifier, feature-context, physical-context, and retained-component
            % selection. Payload materialisation consumes the returned selection and
            % does not repeat these decisions.
            selection = struct( ...
                'ok',false,'analysis',struct(), ...
                'contextSelector','','componentSelector','none', ...
                'catalogue',repmat(NMResultsViewerTools.modelFeatureInspectionContextTemplate(),1,0), ...
                'selectedCatalogueEntry',NMResultsViewerTools.modelFeatureInspectionContextTemplate(), ...
                'selectedContexts',repmat(NMResultsViewerTools.modelFeatureInspectionContextTemplate(),1,0), ...
                'selectedComponent',NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate(), ...
                'catalogueDiagnostics',repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0), ...
                'componentCatalogueDiagnostics',repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0));

            idx = round(double(payload.analysisIndex));
            % nm2-allow: Results Viewer request boundary validates the browser/user-selected analysisIndex before indexing the canonical NM.analysis cell array.
            if idx < 1 || idx > numel(NM.analysis)
                payload.message = 'Model feature inspection requires a valid analysis index with VIS results.';
                payload.diagnostics = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'error','getModelFeatureInspectionPayload',payload.message,'','','','','');
                return;
            end
            A = NM.analysis{idx};
            [available,availabilityMessage] = ...
                NMResultsViewerTools.modelFeatureInspectionAvailability(NM,idx);
            if ~available
                payload.message = availabilityMessage;
                payload.unsupportedPanels = {availabilityMessage};
                payload.diagnostics = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'warning','getModelFeatureInspectionPayload',availabilityMessage,'','','','','');
                return;
            end

            targets = NMResultsViewerTools.targetOptions(NM,idx);
            targetNativeIndex = NMResultsViewerTools.analysisLocalTargetIndex(NM,idx,targets,spec);
            resultTargetIndex = NMResultsViewerTools.selectedTargetResultIndex(targets,targetNativeIndex);
            payload.targetIndex = resultTargetIndex;
            payload.resultTargetIndex = resultTargetIndex;

            requestedContextId = strtrim(spec.featureContextId);
            legacyModalityIndex = spec.modalityIndex;
            contextSelector = '';
            if ~isempty(requestedContextId)
                contextSelector = 'featureContextId';
            end
            metadataOnly = strcmp(payloadScope,'metadata') || strcmp(catalogueScope,'selected');
            [catalogue,catalogueDiagnostics] = ...
                NMResultsViewerTools.modelFeatureInspectionContextCatalogue( ...
                NM,idx,targetNativeIndex,resultTargetIndex,payload.classifierIndex, ...
                metadataOnly,catalogueScope,requestedContextId,legacyModalityIndex);
            payload.featureContexts = catalogue;
            if isempty(catalogue)
                payload.message = 'The selected VIS result target contains no inspectable feature contexts.';
                payload.unsupportedPanels = {payload.message};
                payload.diagnostics = [catalogueDiagnostics ...
                    NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'warning','context_catalogue',payload.message,'','','','','')];
                return;
            end
            payload.combinedViewAvailable = any([catalogue.isCombined] & [catalogue.enabled]);

            % nm2-allow: NMResultsViewerUI_main.stateRequestSpecForChange alone marks selector transitions; direct specs retain explicit invalid-context diagnostics.
            if isfield(spec,'selectionTransition') && ~isempty(spec.selectionTransition) && ~isempty(requestedContextId)
                priorHit = find(strcmp({catalogue.contextId},requestedContextId) & [catalogue.enabled],1,'first');
                if isempty(priorHit)
                    requestedContextId = '';
                    contextSelector = '';
                end
            end
            if isempty(requestedContextId) && isfinite(double(legacyModalityIndex)) && legacyModalityIndex >= 1
                hit = find(~[catalogue.isCombined] & ...
                    [catalogue.visRowIndex] == round(double(legacyModalityIndex)) & ...
                    [catalogue.enabled],1,'first');
                if ~isempty(hit)
                    requestedContextId = catalogue(hit).contextId;
                    contextSelector = 'modalityIndex';
                end
            end
            if isempty(requestedContextId)
                hit = find([catalogue.isCombined] & [catalogue.enabled],1,'first');
                if ~isempty(hit)
                    contextSelector = 'defaultCombinedContext';
                else
                    hit = find(~[catalogue.isCombined] & [catalogue.enabled],1,'first');
                    if ~isempty(hit)
                        contextSelector = 'defaultPhysicalContext';
                    else
                        hit = find([catalogue.enabled],1,'first');
                        if ~isempty(hit)
                            contextSelector = 'defaultEnabledContext';
                        end
                    end
                end
                if ~isempty(hit)
                    requestedContextId = catalogue(hit).contextId;
                end
            end

            selectedIndex = find(strcmp({catalogue.contextId},requestedContextId),1,'first');
            if isempty(selectedIndex) || ~catalogue(selectedIndex).enabled
                payload.message = sprintf( ...
                    'Feature context "%s" is not available for the selected analysis and target.', ...
                    requestedContextId);
                payload.unsupportedPanels = {payload.message};
                payload.diagnostics = [catalogueDiagnostics ...
                    NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'error','context_selection',payload.message,'',requestedContextId,'','','')];
                return;
            end
            selectedCatalogueEntry = catalogue(selectedIndex);
            payload.selectedFeatureContextId = selectedCatalogueEntry.contextId;
            payload.selectedFeatureContext = selectedCatalogueEntry;

            if selectedCatalogueEntry.isCombined
                selectedContextIds = selectedCatalogueEntry.memberContextIds;
            else
                selectedContextIds = {selectedCatalogueEntry.contextId};
            end
            physicalMask = ~[catalogue.isCombined] & ...
                ismember({catalogue.contextId},selectedContextIds);
            selectedContexts = catalogue(physicalMask);
            if isempty(selectedContexts)
                payload.message = 'The selected feature context does not resolve to any physical VIS row.';
                payload.unsupportedPanels = {payload.message};
                payload.diagnostics = [catalogueDiagnostics ...
                    NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'error','context_selection',payload.message,'', ...
                    selectedCatalogueEntry.contextId,'','','')];
                return;
            end

            requestedComponentId = strtrim(spec.backprojectionComponentId);
            requestedComponentIndex = spec.componentIndex;
            componentSelector = 'none';
            if ~isempty(requestedComponentId)
                componentSelector = 'backprojectionComponentId';
            elseif isfinite(double(requestedComponentIndex))
                componentSelector = 'componentIndex';
            end
            [components,selectedComponent,componentDiagnostics,componentSelectionOk,componentSelectionMessage] = ...
                NMResultsViewerTools.modelFeatureInspectionBackprojectionCatalogue( ...
                A,selectedContexts,resultTargetIndex,payload.classifierIndex, ...
                selectedCatalogueEntry,requestedComponentId,requestedComponentIndex);
            % An unavailable retained-component identity is dropped only during
            % an explicit navigation transition; a direct invalid selection still fails.
            if ~componentSelectionOk && ~isempty(requestedComponentId) && ~isempty(components) && ...
                    ~any(strcmp({components.componentId},requestedComponentId))
                % nm2-allow: NMResultsViewerUI_main.stateRequestSpecForChange is the only producer of optional selector-transition metadata.
                if isfield(spec,'selectionTransition') && ~isempty(spec.selectionTransition)
                    [components,selectedComponent,componentDiagnostics,componentSelectionOk,componentSelectionMessage] = ...
                        NMResultsViewerTools.modelFeatureInspectionBackprojectionCatalogue( ...
                        A,selectedContexts,resultTargetIndex,payload.classifierIndex, ...
                        selectedCatalogueEntry,'',NaN);
                    componentSelector = 'defaultFirstRetainedComponent';
                end
            end
            payload.backprojectionComponents = components;
            payload.backprojectionAvailable = ~isempty(components);
            payload.selectedFeatureContext.backprojectionAvailable = payload.backprojectionAvailable;
            payload.selectedFeatureContext.backprojectionComponentCount = double(numel(components));
            payload.featureContexts(selectedIndex).backprojectionAvailable = payload.backprojectionAvailable;
            payload.featureContexts(selectedIndex).backprojectionComponentCount = double(numel(components));
            if payload.backprojectionAvailable && componentSelectionOk
                if strcmp(componentSelector,'none')
                    componentSelector = 'defaultFirstRetainedComponent';
                end
                payload.selectedBackprojectionComponentId = selectedComponent.componentId;
                payload.selectedBackprojectionComponentIndex = selectedComponent.componentIndex;
                payload.selectedBackprojectionComponentColumn = selectedComponent.componentPosition;
                payload.selectedBackprojectionComponentLabel = selectedComponent.componentLabel;
                for contextIndex = 1:numel(selectedContexts)
                    selectedContexts(contextIndex).componentIndex = selectedComponent.componentIndex;
                    selectedContexts(contextIndex).componentLabel = selectedComponent.componentLabel;
                end
                payload.selectedFeatureContext.componentIndex = selectedComponent.componentIndex;
                payload.selectedFeatureContext.componentLabel = selectedComponent.componentLabel;
            elseif ~componentSelectionOk
                payload.message = componentSelectionMessage;
                payload.unsupportedPanels = {componentSelectionMessage};
                payload.diagnostics = [catalogueDiagnostics componentDiagnostics];
                return;
            end

            selection.analysis = A;
            selection.contextSelector = contextSelector;
            selection.componentSelector = componentSelector;
            selection.catalogue = payload.featureContexts;
            selection.selectedCatalogueEntry = payload.selectedFeatureContext;
            selection.selectedContexts = selectedContexts;
            selection.selectedComponent = selectedComponent;
            selection.catalogueDiagnostics = catalogueDiagnostics;
            selection.componentCatalogueDiagnostics = componentDiagnostics;
            selection.ok = true;
        end

        function [catalogue, diagnostics] = modelFeatureInspectionContextCatalogue(NM, analysisIndex, targetIndex, resultTargetIndex, classIndex, metadataOnly, catalogueScope, requestedContextId, legacyModalityIndex)
            % modelFeatureInspectionContextCatalogue  Build analysis-specific stable VIS feature contexts.
            %
            % Physical contexts are keyed by VIS row and varind. Combined feature
            % inspection retains the selected physical members; relation matrices
            % additionally require the persisted CombinedRelation contract.
            catalogue = repmat(NMResultsViewerTools.modelFeatureInspectionContextTemplate(),1,0);
            diagnostics = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            A = NM.analysis{analysisIndex};
            [nModalities, nTargets] = NMResultsViewerTools.modelFeatureInspectionVisSize(A);
            if resultTargetIndex < 1 || resultTargetIndex > nTargets
                diagnostics = NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', 'context_catalogue', sprintf('Resolved VIS result target %d is outside the available target dimension %d.', resultTargetIndex, nTargets), 'analysis.visdata', '', '', '', '');
                return;
            end
            if strcmp(catalogueScope,'selected')
                selectedVisRow = NaN;
                physicalToken = regexp(requestedContextId, ...
                    '^a[0-9]+_t[0-9]+_r[0-9]+_v([0-9]+)_m[0-9]+_c[0-9]+$', ...
                    'tokens','once');
                if ~isempty(physicalToken)
                    selectedVisRow = str2double(physicalToken{1});
                elseif isempty(requestedContextId) && isfinite(double(legacyModalityIndex))
                    selectedVisRow = round(double(legacyModalityIndex));
                end
                if isfinite(selectedVisRow) && selectedVisRow >= 1 && selectedVisRow <= nModalities
                    v = NMResultsViewerTools.modelFeatureInspectionVisEntry(A,selectedVisRow,resultTargetIndex);
                    if NMResultsViewerTools.modelFeatureInspectionIsVisStruct(v)
                        selectedContext = NMResultsViewerTools.modelFeatureInspectionContextFromVis( ...
                            NM,analysisIndex,targetIndex,classIndex,selectedVisRow,v,resultTargetIndex);
                        catalogue = selectedContext;
                        if ~metadataOnly
                            catalogue = NMResultsViewerTools.modelFeatureInspectionAnnotateBackprojectionAvailability( ...
                                A,catalogue,resultTargetIndex,classIndex);
                        end
                    end
                    return;
                end
            end
            tmp = repmat(NMResultsViewerTools.modelFeatureInspectionContextTemplate(), 1, nModalities + 1);
            count = 0;
            for visRow = 1:nModalities
                v = NMResultsViewerTools.modelFeatureInspectionVisEntry(A, visRow, resultTargetIndex);
                if ~NMResultsViewerTools.modelFeatureInspectionIsVisStruct(v), continue; end
                count = count + 1;
                tmp(count) = NMResultsViewerTools.modelFeatureInspectionContextFromVis( ...
                    NM,analysisIndex,targetIndex,classIndex,visRow,v,resultTargetIndex);
            end
            if count < 1, return; end
            physical = tmp(1:count);
            [combined, combinedOk, combinedDiagnostic] = NMResultsViewerTools.modelFeatureInspectionCombinedContext(NM, A, physical, analysisIndex, targetIndex, resultTargetIndex, classIndex);
            if combinedOk
                count = count + 1;
                tmp(count) = combined;
            elseif ~isempty(combinedDiagnostic)
                diagnostics = combinedDiagnostic;
            end
            catalogue = tmp(1:count);
            if ~metadataOnly
                catalogue = NMResultsViewerTools.modelFeatureInspectionAnnotateBackprojectionAvailability( ...
                    A,catalogue,resultTargetIndex,classIndex);
            end
        end
        function catalogue = modelFeatureInspectionAnnotateBackprojectionAvailability(A,catalogue,resultTargetIndex,classIndex)
            % modelFeatureInspectionAnnotateBackprojectionAvailability  Annotate each feature source with its retained-component axis.
            %
            % The annotation is derived from the same exact CompKept/feature-matrix
            % contract used by the selected feature payload. It is therefore safe for
            % Report Builder availability controls and does not infer component axes
            % from modality count, fusion mode or feature dimensionality.
            if isempty(catalogue), return; end
            physicalMask = ~[catalogue.isCombined];
            for contextPosition = 1:numel(catalogue)
                if ~catalogue(contextPosition).enabled, continue; end
                selectedContext = catalogue(contextPosition);
                if selectedContext.isCombined
                    memberIds = selectedContext.memberContextIds;
                    selectedContexts = catalogue(physicalMask & ismember({catalogue.contextId},memberIds));
                else
                    selectedContexts = selectedContext;
                end
                [components,~,~,componentAxisOk,~] = ...
                    NMResultsViewerTools.modelFeatureInspectionBackprojectionCatalogue( ...
                    A,selectedContexts,resultTargetIndex,classIndex,selectedContext,'',NaN);
                if ~componentAxisOk || isempty(components), continue; end
                enabledMask = arrayfun(@(component)logical(component.enabled),components);
                catalogue(contextPosition).backprojectionComponentCount = double(sum(enabledMask));
                catalogue(contextPosition).backprojectionAvailable = any(enabledMask);
            end
        end

        function [combined, ok, diagnostic] = modelFeatureInspectionCombinedContext(NM, A, physical, analysisIndex, targetIndex, resultTargetIndex, classIndex)
            % modelFeatureInspectionCombinedContext  Certify one combined fusion feature context.
            %
            % Feature-wise inspection is independent of the optional persisted
            % CombinedRelation matrix. The existing member renderers serve both
            % fusion modes; relation matrices still require their own contract.
            combined = NMResultsViewerTools.modelFeatureInspectionContextTemplate();
            ok = false;
            diagnostic = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            fusionMode = NMResultsViewerTools.analysisFusionMode(A);
            if numel(physical) < 2 || ~ismember(fusionMode, {'early','intermediate'}), return; end % nm2-allow: combined contexts require at least two physical fusion members
            enabled = physical([physical.enabled]);
            if numel(enabled) ~= numel(physical), return; end
            % Bound the complete combined axis, not only each member's displayed rows.
            % Voxel and vertex fields remain available through their physical sources.
            if sum([enabled.nFeatures]) > 5000 || ...
                    any(ismember({enabled.featureKind},{'voxel','surface_vertex'}))
                return;
            end

            allTabular = all(strcmp({enabled.featureKind}, 'tabular')) && ...
                all(strcmp({enabled.rendererFamily}, 'tabular'));
            if allTabular && strcmp(fusionMode,'early')
                for ii = 1:numel(enabled)
                    if ~NMResultsViewerFeatureVectorAuthority.isTabularDescriptor(NM, enabled(ii).varind)
                        return;
                    end
                end
                members = enabled;
                combined.sourceKind = 'visdata_combined';
                combined.sourceFamily = 'tabular_concatenation';
                combined.featureKind = 'tabular';
                combined.rendererFamily = 'tabular';
                combined.combinedGroupId = sprintf('a%d_t%d_r%d_tabular_concat', analysisIndex, targetIndex, resultTargetIndex);
            else
                [relation,members,relationDiagnostic] = ...
                    NMResultsViewerTools.modelFeatureInspectionCombinedRelationContract(A,enabled,'');
                if isempty(relation) || ~relation.available
                    if ~isempty(relationDiagnostic)
                        diagnostic = relationDiagnostic;
                        return;
                    end
                    % Native member feature measures need no combined correlation matrix.
                    members = enabled;
                    sourceKind = 'visdata_combined';
                    sourceFamily = sprintf('%s_native_features',fusionMode);
                else
                    if numel(members) ~= numel(enabled) || ... % nm2-allow: persisted CombinedRelation must cover the complete selected fusion-member axis
                            ~all(ismember({enabled.contextId},{members.contextId}))
                        return;
                    end
                    sourceKind = 'visdata_combined_relation';
                    sourceFamily = sprintf('%s_native_relation',fusionMode);
                end
                combined.sourceKind = sourceKind;
                combined.sourceFamily = sourceFamily;
                combined.featureKind = 'mixed_native';
                combined.rendererFamily = 'relation';
                combined.combinedGroupId = sprintf('a%d_t%d_r%d_native_relation', analysisIndex, targetIndex, resultTargetIndex);
            end

            combined.modalityLabel = 'Combined feature view';
            combined.selectionLabel = 'Combined feature view';
            combined.analysisIndex = analysisIndex;
            combined.targetIndex = targetIndex;
            combined.resultTargetIndex = resultTargetIndex;
            combined.targetLabel = members(1).targetLabel;
            combined.classIndex = classIndex;
            combined.classLabel = members(1).classLabel;
            combined.visRowIndex = 0;
            combined.modalityIndex = 0;
            combined.varind = 0;
            combined.fusionMode = fusionMode;
            combined.nFeatures = sum([members.nFeatures]);
            combined.isCombined = true;
            combined.memberContextIds = {members.contextId};
            combined.contextId = sprintf('a%d_t%d_r%d_combined_c%d', analysisIndex, targetIndex, resultTargetIndex, classIndex);
            combined.enabled = true;
            combined.disabledReason = '';
            ok = true;
        end

        function [relation, memberContexts, diagnostics] = modelFeatureInspectionCombinedRelationContract(A, physical, requestedRelationId)
            % modelFeatureInspectionCombinedRelationContract  Resolve and validate one persisted all-member fusion relation.
            %
            % nk_VisModelsC conditionally publishes one fixed-schema CombinedRelation
            % and replicates it across participating VIS entries. This function validates
            % replica identity/member parity; it does not rediscover that schema.
            relation=[];
            diagnostics=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            memberContexts=physical([]);
            fusionMode=NMResultsViewerTools.analysisFusionMode(A);
            if ~ismember(fusionMode,{'early','intermediate'}), return; end
            % nm2-allow: a combined fusion context scientifically requires at least two resolved physical member contexts.
            if numel(physical)<2, return; end
            for ii=1:numel(physical)
                v=NMResultsViewerTools.modelFeatureInspectionVisEntry(A,physical(ii).visRowIndex,physical(ii).resultTargetIndex);
                % nm2-allow: nk_VisModelsC writes CombinedRelation only when an eligible persisted combined relation was produced.
                if ~isfield(v,'CombinedRelation') || isempty(v.CombinedRelation)
                    continue;
                end
                candidate=v.CombinedRelation;
                if ~isempty(requestedRelationId) && ~strcmp(candidate.relationId,requestedRelationId), continue; end
                if isempty(relation)
                    relation=candidate;
                elseif ~isequaln(relation,candidate)
                    relation=[];
                    diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                        'combined_relation_replica_mismatch', ...
                        'CombinedRelation replicas differ across participating VIS entries.', ...
                        'CombinedRelation',physical(ii).contextId,'modelFeatureInspectionCombinedRelationMatrixPayload','','');
                    return;
                end
            end
            if isempty(relation), return; end
            if ~strcmp(relation.fusionMode,fusionMode)
                relation=[];
                diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                    'combined_relation_fusion_mismatch', ...
                    'CombinedRelation fusion identity does not match the selected analysis.', ...
                    'CombinedRelation',physical(1).contextId,'modelFeatureInspectionCombinedRelationMatrixPayload','','');
                return;
            end

            memberVarind=double(relation.memberVarind(:)');
            memberCounts=double(relation.memberFeatureCounts(:)');
            if isempty(memberVarind) || numel(memberVarind)~=numel(memberCounts) % nm2-allow: CombinedRelation writer persists paired member identity/count axes
                relation=[];
                diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                    'combined_relation_member_contract_invalid', ...
                    'CombinedRelation memberVarind/memberFeatureCounts are inconsistent.', ...
                    'CombinedRelation',physical(1).contextId,'modelFeatureInspectionCombinedRelationMatrixPayload','','');
                return;
            end

            memberContexts=repmat(physical(1),1,numel(memberVarind));
            for mm=1:numel(memberVarind)
                hit=find([physical.varind]==memberVarind(mm),1,'first');
                if isempty(hit) || physical(hit).nFeatures~=memberCounts(mm)
                    relation=[];
                    memberContexts=physical([]);
                    diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                        'combined_relation_member_context_mismatch', ...
                        sprintf('CombinedRelation member varind %g with %g features does not match the physical VIS catalogue.',memberVarind(mm),memberCounts(mm)), ...
                        'CombinedRelation',physical(1).contextId,'modelFeatureInspectionCombinedRelationMatrixPayload','','');
                    return;
                end
                memberContexts(mm)=physical(hit);
                v=NMResultsViewerTools.modelFeatureInspectionVisEntry(A,physical(hit).visRowIndex,physical(hit).resultTargetIndex);
                % nm2-allow: nk_VisModelsC conditionally writes the replicated CombinedRelation; once one replica is selected every participating member must carry the identical contract.
                if ~isfield(v,'CombinedRelation') || ~isequaln(v.CombinedRelation,relation)
                    relation=[];
                    memberContexts=physical([]);
                    diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                        'combined_relation_replication_incomplete', ...
                        'The combined relation is not replicated identically across all participating modality VIS entries.', ...
                        'CombinedRelation',physical(hit).contextId,'modelFeatureInspectionCombinedRelationMatrixPayload','','');
                    return;
                end
            end
        end
        function [matrix, diagnostics] = modelFeatureInspectionCombinedRelationMatrixPayload(A,catalogue,selectedContext,classIndex,includeFullValues,requestedRelationId)
            % modelFeatureInspectionCombinedRelationMatrixPayload  Resolve one replicated fusion relation.
            %
            % Replica/member validation is delegated to the compact CombinedRelation
            % contract resolver. The selected combined context already owns display
            % identity; this function only qualifies the writer-defined native feature
            % names by the validated member blocks and delegates matrix normalization.
            matrix=repmat(NMResultsViewerFeatureRelationTools.matrixTemplate(),1,0);
            diagnostics=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            fusionMode=NMResultsViewerTools.analysisFusionMode(A);
            if ~ismember(fusionMode,{'early','intermediate'}) || isempty(catalogue), return; end
            physical=catalogue(~[catalogue.isCombined] & [catalogue.enabled]);
            if numel(physical)<2, return; end
            [relation,memberContexts,diagnostics]= ...
                NMResultsViewerTools.modelFeatureInspectionCombinedRelationContract(A,physical,requestedRelationId);
            if isempty(relation), return; end
            memberCounts=double(relation.memberFeatureCounts(:)');
            memberContextIds={memberContexts.contextId};
            if ~selectedContext.isCombined || ~isequal(selectedContext.memberContextIds,memberContextIds)
                diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                    'combined_relation_selected_context_mismatch', ...
                    'The selected combined Feature context does not match the persisted CombinedRelation member order.', ...
                    'CombinedRelation',selectedContext.contextId,'modelFeatureInspectionCombinedRelationMatrixPayload','','');
                return;
            end
            context=selectedContext;
            context.nFeatures=sum(memberCounts);
            featureNames=relation.featureNames(:);
            % nm2-allow: nk_VisModelsC CombinedRelation featureNames must match the persisted memberFeatureCounts scientific axis.
            if numel(featureNames)~=context.nFeatures
                diagnostics=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error', ...
                    'combined_relation_feature_name_count_mismatch', ...
                    'CombinedRelation featureNames do not match the persisted memberFeatureCounts axis.', ...
                    'CombinedRelation',context.contextId,'modelFeatureInspectionCombinedRelationMatrixPayload','','');
                return;
            end
            qualified=cell(context.nFeatures,1);
            offset=0;
            for mm=1:numel(memberContexts)
                memberIndex=offset+(1:memberCounts(mm));
                label=memberContexts(mm).modalityLabel;
                qualified(memberIndex)=NMResultsViewerTools.modelFeatureInspectionQualifiedNames(featureNames(memberIndex),label);
                offset=offset+memberCounts(mm);
            end
            context.relationFeatureLabels=qualified;
            [matrix,relationDiagnostics]=NMResultsViewerFeatureRelationTools.buildCombinedMatrixPayload( ...
                relation,context,classIndex,struct('includeFullValues',logical(includeFullValues)));
            if ~isempty(relationDiagnostics), diagnostics=relationDiagnostics; end
        end

        function names = modelFeatureInspectionQualifiedNames(names,modalityLabel)
            % One presentation-label authority shared by combined feature rows and relation views.
            names=cellfun(@(name)sprintf('%s · %s',modalityLabel,name),names,'UniformOutput',false);
        end

        function mode = analysisFusionMode(A)
            % analysisFusionMode  Read the persisted analysis-level TrainParam.FUSION.flag contract.
            flag = round(double(A.params.TrainParam.FUSION.flag));
            switch flag
                case 0, mode = 'none';
                case 1, mode = 'early';
                case 2, mode = 'intermediate';
                case 3, mode = 'late';
                otherwise
                    error('NMResultsViewerTools:InvalidFusionMode', ...
                        'analysis.params.TrainParam.FUSION.flag must be one of 0, 1, 2 or 3.');
            end
        end

        function tf = analysisStackingActive(A)
            % analysisStackingActive  Read the completed-analysis STACKING.flag snapshot.
            tf = round(double(A.params.TrainParam.STACKING.flag)) == 1;
        end
        function varinds = analysisFeatureModalityVarinds(A,physicalVarinds,isStacking)
            % Purpose: Resolve the DataIO namespace that owns the already-materialized Feature Inspection axis.
            % Syntax: varinds = NMResultsViewerTools.analysisFeatureModalityVarinds(A,physicalVarinds,isStacking)
            % Inputs: A is the owning analysis; physicalVarinds are VIS-resolved modality indices; isStacking identifies an analysis-derived stacker axis.
            % Outputs: Ordered DataIO namespace indices. Early/intermediate fusion returns only the first FUSION.M member because NM projects that result feature axis onto this virtual modality.
            % Authority and flow: The completed analysis FUSION.M contract is normalized once here and consumed by context, Annotation, and Scientific State materialization.
            % Scientific/state contract: FUSION.M contributor order is scientific identity. The first member owns early/intermediate projected feature names; later members are not concatenated naming blocks.
            % Invariants: Stacking has no DataIO namespace; non-fused contexts retain their resolved physical modality order; fusion indices are finite positive integers.
            % Materialization and performance: Compact analysis metadata only; no feature vectors, names, files, or spatial resources are loaded.
            % Failure semantics: Invalid FUSION.M fails explicitly; no VIS-row or feature-count inference substitutes for the completed analysis contract.
            % Side effects: None.
            % Consumers and dependencies: modelFeatureInspectionContextFromVis and modelFeatureInspectionScientificAnnotation.
            if isStacking, varinds=[]; return; end
            physicalVarinds=double(physicalVarinds(:)');
            mode=NMResultsViewerTools.analysisFusionMode(A);
            if ismember(mode,{'early','intermediate'})
                raw=A.params.TrainParam.FUSION.M;
                members=double(raw(:)');
                if any(~isfinite(members)|members<1|members~=round(members))
                    error('NMResultsViewerTools:InvalidFusionModalityContract', ...
                        'FUSION.M must contain finite positive integer DataIO modality indices.');
                end
                varinds=members(1);
                return;
            end
            varinds=unique(physicalVarinds(isfinite(physicalVarinds)&physicalVarinds>=1),'stable');
        end
        function family = modelFeatureInspectionRendererFamily(featureKind)
            % modelFeatureInspectionRendererFamily  Map one canonical feature family to its browser renderer.
            switch featureKind
                case 'voxel', family = 'voxel_overlay';
                case 'surface_vertex', family = 'surface_overlay';
                case {'connectivity','connectivity_edge'}, family = 'connectivity';
                case 'roi', family = 'imaging';
                otherwise, family = 'tabular';
            end
        end

        function label = modelFeatureInspectionTargetLabel(NM, analysisIndex, targetIndex)
            % modelFeatureInspectionTargetLabel  Resolve the public target label from targetOptions.
            label = sprintf('Target %d', targetIndex);
            opts = NMResultsViewerTools.targetOptions(NM, analysisIndex);
            if isempty(opts), return; end
            hit = find([opts.index] == targetIndex, 1, 'first');
            if ~isempty(hit) && ~isempty(opts(hit).label), label = opts(hit).label; end
        end
        function ctx = modelFeatureInspectionContextFromVis(NM, analysisIndex, targetIndex, classIndex, modalityIndex, v, resultTargetIndex)
            % modelFeatureInspectionContextFromVis  Normalize one physical VIS row into a stable feature context.
            % Authority and flow: nk_VisModelsC owns the populated VIS params contract; one descriptor
            % normalization establishes feature/source family; canonical ROI provenance is projected once.
            % Materialization and performance: metadata-only; reads no ROI sources, atlas voxels, or annotations.
            resultTargetIndex = round(double(resultTargetIndex));
            ctx = NMResultsViewerTools.modelFeatureInspectionContextTemplate();
            ctx.analysisIndex = analysisIndex;
            ctx.targetIndex = targetIndex;
            ctx.resultTargetIndex = resultTargetIndex;
            ctx.targetLabel = NMResultsViewerTools.modelFeatureInspectionTargetLabel(NM, analysisIndex, targetIndex);
            ctx.classIndex = round(double(classIndex));
            if ~isfinite(ctx.classIndex) || ctx.classIndex < 1, ctx.classIndex = 1; end
            ctx.classLabel = sprintf('Classifier %d', ctx.classIndex);
            ctx.visRowIndex = modalityIndex;
            ctx.modalityIndex = modalityIndex;
            ctx.varind = round(double(v.params.varind));
            ctx.legacyVisFlag = double(v.params.visflag);
            A=NM.analysis{analysisIndex};
            isStacking=NMResultsViewerTools.analysisStackingActive(A);
            ctx.fusionMode=NMResultsViewerTools.analysisFusionMode(A);
            if isStacking
                ctx.modalityLabel='Stacked prediction sources';
            else
                ctx.modalityLabel=NMResultsViewerTools.modelFeatureInspectionModalityLabel(NM,ctx.varind,modalityIndex);
            end
            if isStacking
                ctx.selectionLabel=ctx.modalityLabel;
            else
                genericLabel=sprintf('Modality %d',modalityIndex);
                if strcmp(ctx.modalityLabel,genericLabel)
                    ctx.selectionLabel=genericLabel;
                else
                    ctx.selectionLabel=sprintf('Modality %d: %s',modalityIndex,ctx.modalityLabel);
                end
            end
            ctx.contextId = sprintf('a%d_t%d_r%d_v%d_m%d_c%d', analysisIndex, targetIndex, resultTargetIndex, modalityIndex, ctx.varind, ctx.classIndex);
            ctx.nFeatures = NMResultsViewerTools.modelFeatureInspectionFeatureCount(v,ctx.classIndex,ctx.contextId,isStacking);
            if isStacking
                ctx.featureKind='tabular';
                ctx.sourceFamily='stacking_predictions';
            else
                descriptor=NMResultsViewerImagingDescriptorAdapter.resolve(NM,ctx.varind,v);
                if descriptor.ok
                    ctx.featureKind=descriptor.featureKind;
                    ctx.sourceFamily=descriptor.sourceFamily;
                else
                    ctx.featureKind='tabular';
                    ctx.sourceFamily='unknown';
                end
            end
            if strcmpi(ctx.featureKind,'roi')
                if ~descriptor.roiProvenance.ok
                    error('NMResultsViewerTools:ROIProvenanceUnavailable', ...
                        'ROI Feature Inspection context %s has no valid canonical ROI provenance.',ctx.contextId);
                end
                projection = NMDataIOROIProvenanceTools.spatialProjection(descriptor.roiProvenance);
                ctx.roiSidecarAvailable = true;
                ctx.roiSpatialDomain = projection.spatialDomain;
                ctx.roiSpatialSemantics = projection.spatialSemantics;
                ctx.roiIdentityModel = projection.identityModel;
                ctx.roiSpatialReferenceIdentity = projection.spatialReferenceIdentity;
                ctx.roiHasAtlasCoordinates = any(all(isfinite(double(descriptor.roiProvenance.mniCoordinates)),2));
                if strcmp(projection.spatialDomain,'volume')
                    ref = NMDataIOROIProvenanceTools.spatialReference(descriptor.roiProvenance,'volumetric_atlas');
                    if numel(ref.sourceFiles) ~= 1
                        error('NMResultsViewerTools:ROIAtlasIdentity', ...
                            'Canonical volumetric ROI provenance for context %s must identify exactly one atlas file.',ctx.contextId);
                    end
                    ctx.roiAtlasFile = ref.sourceFiles{1};
                end
            end
            ctx.rendererFamily = NMResultsViewerTools.modelFeatureInspectionRendererFamily(ctx.featureKind);
            ctx.enabled = ctx.nFeatures > 0;
            if ~ctx.enabled, ctx.disabledReason = 'VIS context does not contain any features.'; end
        end
        function label = modelFeatureInspectionModalityLabel(NM, varind, fallbackIndex)
            % NMModalityInfoTools is the normalization authority for persisted modality labels.
            info = NMModalityInfoTools.fromNM(NM,varind,struct('ScanInMemory',false));
            label = info.description;
            if isempty(label), label = sprintf('Modality %d', fallbackIndex); end
        end
        function n = modelFeatureInspectionFeatureCount(v,classIndex,contextId,isStacking)
            % For stacking VIS with an explicit no-name placeholder, dimvecx
            % retains the scientific prediction-source axis; nfeats counts the placeholder.
            if isStacking && isequal(v.params.features,{[]})
                n=double(v.params.dimvecx(2));
            else
                n=double(v.params.nfeats);
                featureNameCount=numel(v.params.features);
                if n~=featureNameCount
                    error('NMResultsViewerTools:InconsistentFeatureCountMetadata', ...
                        'VIS context %s declares %g features but contains %g feature names.', ...
                        contextId,n,featureNameCount);
                end
            end
            if ~isscalar(n) || ~isfinite(n) || n<1 || n~=round(n)
                error('NMResultsViewerTools:InconsistentFeatureCountMetadata', ...
                    'VIS context %s has an invalid feature-axis width.',contextId);
            end
            definitions = NMResultsViewerTools.modelFeatureInspectionMeasureDefinitions();
            for definitionIndex = 1:numel(definitions)
                fieldName = definitions(definitionIndex).sourceField;
                [raw,present] = ...
                    NMResultsViewerTools.modelFeatureInspectionExactClassNumericField( ...
                    v,fieldName,classIndex);
                if ~present || isempty(raw), continue; end
                % nm2-allow: Public VIS measures are producer-conditioned vector/matrix layouts; validate their scientific feature axis against canonical params.nfeats.
                if isvector(raw)
                    fieldCount = numel(raw);
                elseif ismatrix(raw)
                    fieldCount = size(raw,1);
                else
                    continue;
                end
                if fieldCount ~= n
                    error('NMResultsViewerTools:InconsistentFeatureFieldLengths', ...
                        'VIS context %s field %s contains %d feature rows; expected %d from params.nfeats.', ...
                        contextId,fieldName,fieldCount,n);
                end
            end
        end

        function [components, selected, diagnostics, ok, message] = modelFeatureInspectionBackprojectionCatalogue(A, selectedContexts, resultTargetIndex, classIndex, selectedCatalogueEntry, requestedId, requestedIndex)
            % modelFeatureInspectionBackprojectionCatalogue  Resolve retained component axes for the selected feature source.
            %
            % The contract accepts only exact CompKept vectors and feature matrices
            % whose columns equal either all components or the retained-component
            % count. Combined views are component-selectable only when every physical
            % context exposes the same retained original component indices.
            components = repmat(NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate(),1,0);
            selected = NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate();
            diagnostics = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            ok = true;
            message = '';
            if isempty(selectedContexts), return; end

            axisTemplate = struct('declared',false,'available',false,'nAll',0, ...
                'keptIndices',[],'presence',[],'contextId','', ...
                'diagnostics',repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0));
            axes = repmat(axisTemplate,1,numel(selectedContexts));
            diagnosticTemplate = NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate();
            maxAxisDiagnostics = numel(selectedContexts) * ...
                (numel(NMResultsViewerTools.modelFeatureInspectionMeasureDefinitions()) + 8) + 4;
            diagnosticBuffer = repmat(diagnosticTemplate,1,max(1,maxAxisDiagnostics));
            diagnosticCount = 0;

            for contextPosition = 1:numel(selectedContexts)
                context = selectedContexts(contextPosition);
                visEntry = NMResultsViewerTools.modelFeatureInspectionVisEntry( ...
                    A,context.visRowIndex,resultTargetIndex);
                axes(contextPosition) = NMResultsViewerTools.modelFeatureInspectionComponentAxis( ...
                    visEntry,classIndex,context.nFeatures,context.contextId);
                nextDiagnostics = axes(contextPosition).diagnostics;
                if ~isempty(nextDiagnostics)
                    nextCount = numel(nextDiagnostics);
                    diagnosticBuffer(diagnosticCount+1:diagnosticCount+nextCount) = nextDiagnostics;
                    diagnosticCount = diagnosticCount + nextCount;
                end
            end

            invalidDeclared = [axes.declared] & ~[axes.available];
            if any(invalidDeclared)
                ok = false;
                invalidContextIds = {axes(invalidDeclared).contextId};
                message = sprintf(['Component metadata are present, but no exact ' ...
                    'feature-by-component axis could be validated for context(s): %s.'], ...
                    strjoin(invalidContextIds,', '));
                diagnosticCount = diagnosticCount + 1;
                diagnosticBuffer(diagnosticCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'error','component_axis',message,'CompKept', ...
                    selectedCatalogueEntry.contextId,'','','');
                diagnostics = diagnosticBuffer(1:diagnosticCount);
                return;
            end

            declaredMask = [axes.declared];
            if ~any(declaredMask)
                diagnostics = diagnosticBuffer(1:diagnosticCount);
                return;
            end
            if any(~declaredMask)
                ok = false;
                message = ['Combined feature inspection cannot mix component-resolved ' ...
                    'and non-component-resolved member contexts. Select a physical ' ...
                    'feature source to inspect its component-wise results.'];
                diagnosticCount = diagnosticCount + 1;
                diagnosticBuffer(diagnosticCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'error','component_axis',message,'CompKept', ...
                    selectedCatalogueEntry.contextId,'','','');
                diagnostics = diagnosticBuffer(1:diagnosticCount);
                return;
            end

            retainedIndices = axes(1).keptIndices(:)';
            totalComponentCount = axes(1).nAll;
            for axisPosition = 2:numel(axes)
                if axes(axisPosition).nAll ~= totalComponentCount || ...
                        ~isequal(retainedIndices,axes(axisPosition).keptIndices(:)')
                    ok = false;
                    message = ['Combined feature inspection requires identical total and ' ...
                        'retained original component indices in every member context.'];
                    diagnosticCount = diagnosticCount + 1;
                    diagnosticBuffer(diagnosticCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                        'error','component_axis',message,'CompKept', ...
                        selectedCatalogueEntry.contextId,'','','');
                    diagnostics = diagnosticBuffer(1:diagnosticCount);
                    return;
                end
            end

            retainedCount = numel(retainedIndices);
            if retainedCount < 1
                diagnostics = diagnosticBuffer(1:diagnosticCount);
                return;
            end
            components = repmat( ...
                NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate(), ...
                1,retainedCount);
            memberContextIds = {selectedContexts.contextId};
            for componentPosition = 1:retainedCount
                originalComponentIndex = retainedIndices(componentPosition);
                component = NMResultsViewerTools.modelFeatureInspectionBackprojectionComponentTemplate();
                component.componentId = sprintf('%s::component:%d', ...
                    selectedCatalogueEntry.contextId,originalComponentIndex);
                component.contextId = selectedCatalogueEntry.contextId;
                component.componentIndex = originalComponentIndex;
                component.componentPosition = componentPosition;
                component.componentLabel = sprintf('Component %d',originalComponentIndex);
                component.selectionLabel = component.componentLabel;
                component.nAllComponents = totalComponentCount;
                component.nRetainedComponents = retainedCount;
                component.memberContextIds = memberContextIds;

                presenceValues = nan(1,numel(axes));
                for axisPosition = 1:numel(axes)
                    if numel(axes(axisPosition).presence) >= originalComponentIndex
                        presenceValues(axisPosition) = ...
                            100 * axes(axisPosition).presence(originalComponentIndex);
                    end
                end
                finitePresence = isfinite(presenceValues);
                if any(finitePresence)
                    component.presencePercent = mean(presenceValues(finitePresence));
                    component.selectionLabel = sprintf('Component %d (present %.1f%%)', ...
                        originalComponentIndex,component.presencePercent);
                end
                component.enabled = true;
                components(componentPosition) = component;
            end

            selectedPosition = [];
            if ~isempty(requestedId)
                selectedPosition = find(strcmp({components.componentId},requestedId),1,'first');
            end
            if isempty(selectedPosition) && isempty(requestedId) && isfinite(double(requestedIndex))
                selectedPosition = find([components.componentIndex] == ...
                    round(double(requestedIndex)),1,'first');
            end
            if isempty(selectedPosition) && isempty(requestedId)
                selectedPosition = 1;
            end
            if isempty(selectedPosition)
                ok = false;
                message = sprintf(['Backprojected component "%s" is not available for ' ...
                    'feature source "%s".'],requestedId,selectedCatalogueEntry.selectionLabel);
                diagnosticCount = diagnosticCount + 1;
                diagnosticBuffer(diagnosticCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'error','component_selection',message,'CompKept', ...
                    selectedCatalogueEntry.contextId,'','','');
                diagnostics = diagnosticBuffer(1:diagnosticCount);
                return;
            end
            selected = components(selectedPosition);
            diagnostics = diagnosticBuffer(1:diagnosticCount);
        end

        function axis = modelFeatureInspectionComponentAxis(v, classIndex, nFeatures, contextId)
            % modelFeatureInspectionComponentAxis  Validate one VIS entry's retained component axis.
            diagnosticTemplate = NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate();
            maxDiagnostics = numel(NMResultsViewerTools.modelFeatureInspectionMeasureDefinitions()) + 8;
            diagnosticBuffer = repmat(diagnosticTemplate,1,maxDiagnostics);
            diagnosticCount = 0;
            axis = struct('declared',false,'available',false,'nAll',0, ...
                'keptIndices',[],'presence',[],'contextId',contextId, ...
                'diagnostics',repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0));

            [kept,present,keptDiagnostic] = ...
                NMResultsViewerTools.modelFeatureInspectionExactClassVector( ...
                v,'CompKept',classIndex,contextId);
            if ~isempty(keptDiagnostic)
                diagnosticCount = diagnosticCount + 1;
                diagnosticBuffer(diagnosticCount) = keptDiagnostic;
            end
            if ~present
                axis.diagnostics = diagnosticBuffer(1:diagnosticCount);
                return;
            end
            axis.declared = true;
            if isempty(kept) || any(~isfinite(kept))
                diagnosticCount = diagnosticCount + 1;
                diagnosticBuffer(diagnosticCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'warning','component_axis','CompKept must be a finite numeric vector.', ...
                    'CompKept',contextId,'','','');
                axis.diagnostics = diagnosticBuffer(1:diagnosticCount);
                return;
            end
            axis.nAll = numel(kept);
            axis.keptIndices = find(kept ~= 0)';
            if isempty(axis.keptIndices)
                diagnosticCount = diagnosticCount + 1;
                diagnosticBuffer(diagnosticCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'warning','component_axis','CompKept does not retain any component.', ...
                    'CompKept',contextId,'','','');
                axis.diagnostics = diagnosticBuffer(1:diagnosticCount);
                return;
            end

            [presence,presencePresent,presenceDiagnostic] = ...
                NMResultsViewerTools.modelFeatureInspectionExactClassVector( ...
                v,'CompSelRat',classIndex,contextId);
            if ~isempty(presenceDiagnostic)
                diagnosticCount = diagnosticCount + 1;
                diagnosticBuffer(diagnosticCount) = presenceDiagnostic;
            end
            if presencePresent
                if numel(presence) ~= axis.nAll
                    diagnosticCount = diagnosticCount + 1;
                    diagnosticBuffer(diagnosticCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                        'warning','component_axis', ...
                        'CompSelRat length must equal CompKept length. Presence percentages are omitted.', ...
                        'CompSelRat',contextId,'','','');
                else
                    axis.presence = presence;
                end
            end

            definitions = NMResultsViewerTools.modelFeatureInspectionMeasureDefinitions();
            malformedFields = cell(1,numel(definitions));
            malformedCount = 0;
            hasResolvedField = false;
            for definitionIndex = 1:numel(definitions)
                sourceField = definitions(definitionIndex).sourceField;
                [raw,fieldPresent] = ...
                    NMResultsViewerTools.modelFeatureInspectionExactClassNumericField( ...
                    v,sourceField,classIndex);
                if ~fieldPresent || isempty(raw), continue; end
                [resolved,malformed] = NMResultsViewerTools.modelFeatureInspectionHasComponentAxis( ...
                    raw,nFeatures,axis.nAll,numel(axis.keptIndices));
                hasResolvedField = hasResolvedField || resolved;
                if malformed
                    malformedCount = malformedCount + 1;
                    malformedFields{malformedCount} = sourceField;
                end
            end
            if malformedCount > 0
                diagnosticCount = diagnosticCount + 1;
                diagnosticBuffer(diagnosticCount) = NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'warning','component_axis',sprintf( ...
                    'Component-resolved feature fields have unsupported dimensions: %s.', ...
                    strjoin(unique(malformedFields(1:malformedCount),'stable'),', ')), ...
                    '',contextId,'','','');
            end
            axis.available = hasResolvedField;
            axis.diagnostics = diagnosticBuffer(1:diagnosticCount);
        end

        function [raw, present] = modelFeatureInspectionExactClassNumericField(v, fieldName, classIndex)
            % modelFeatureInspectionExactClassNumericField  Resolve the nk_VisModelsC classifier storage contract.
            raw=[]; present=false;
            % nm2-allow: nk_VisModelsC conditionally writes optional public VIS measure/component fields; field presence is the producer-defined capability gate.
            if ~isfield(v,fieldName), return; end
            present=true;
            if strcmp(fieldName,'FeatProb')
                % nk_VisModelsC writes FeatProb={I.PCV2}, where I.PCV2 is feature-by-classifier.
                raw=v.FeatProb{1}(:,classIndex);
            else
                % All other public measure/component fields are classifier-indexed cells.
                raw=v.(fieldName){classIndex};
            end
        end

        function [x, present, diagnostic] = modelFeatureInspectionExactClassVector(v, fieldName, classIndex, contextId)
            % modelFeatureInspectionExactClassVector  Read an exact numeric vector from writer-defined classifier storage.
            [raw,present]=NMResultsViewerTools.modelFeatureInspectionExactClassNumericField(v,fieldName,classIndex);
            diagnostic=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            x=[];
            if ~present||isempty(raw), return; end
            if ~isvector(raw)
                diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_axis',sprintf('%s must be a vector after exact classifier resolution.',fieldName),fieldName,contextId,'','',''); return;
            end
            x=double(raw(:));
        end

        function [resolved, malformed] = modelFeatureInspectionHasComponentAxis(raw, nFeatures, nAll, nRetained)
            % modelFeatureInspectionHasComponentAxis  Classify exact feature-by-component dimensions.
            resolved=false; malformed=false;
            if isempty(raw), return; end
            n=max(0,round(double(nFeatures)));
            if ndims(raw)~=2, malformed=true; return; end
            if size(raw,1)==n && size(raw,2)>1 % nm2-allow: validate nk_VisModelsC feature-by-component axis against persisted CompKept counts
                resolved=ismember(size(raw,2),unique([nAll nRetained])); malformed=~resolved; return;
            end
            if numel(raw)==n, resolved=(nRetained==1); return; end
            malformed=true;
        end

        function [available, diagnostic, status] = modelFeatureInspectionFeatureVectorAvailable(v, fieldName, classIndex, nFeatures, component, contextId)
            % modelFeatureInspectionFeatureVectorAvailable  Validate stored shape without reading feature values.
            diagnostic=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0); status='absent'; available=false;
            [raw,present]=NMResultsViewerTools.modelFeatureInspectionExactClassNumericField(v,fieldName,classIndex);
            if ~present||isempty(raw), return; end
            status='invalid';
            if ~isreal(raw), status='invalid_complex'; diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error','complex_feature_vector',sprintf('%s contains complex values and requires an explicit upstream real-valued transformation.',fieldName),fieldName,contextId,'modelFeatureInspectionFeatureVectorAvailable','',''); return; end
            n=max(0,round(double(nFeatures)));
            if n<1, diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error','feature_vector',sprintf('%s cannot be resolved without a positive feature count.',fieldName),fieldName,contextId,'','',''); return; end
            if ~isempty(component.componentId)
                if ndims(raw)~=2, diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_extraction',sprintf('%s must be a 2-D feature vector or feature-by-component matrix.',fieldName),fieldName,contextId,component.componentId,'',''); return; end
                if size(raw,1)==n&&size(raw,2)>1 % nm2-allow: validate nk_VisModelsC feature-by-component axis against persisted component counts
                    validColumns=unique([component.nRetainedComponents component.nAllComponents]);
                    if ~ismember(size(raw,2),validColumns), diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_extraction',sprintf('%s has %d columns; expected %d retained or %d total components.',fieldName,size(raw,2),component.nRetainedComponents,component.nAllComponents),fieldName,contextId,component.componentId,'',''); return; end
                    available=true; status='valid'; return;
                end
                if isvector(raw)&&numel(raw)==n, available=true; status='valid'; return; end % nm2-allow: exact writer feature-vector axis validation
                diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_extraction',sprintf('%s dimensions %s are incompatible with %d features and the selected component axis.',fieldName,mat2str(size(raw)),n),fieldName,contextId,component.componentId,'',''); return;
            end
            if isvector(raw)
                available=numel(raw)==n;
                if ~available, diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','feature_vector',sprintf('%s contains %d values; expected exactly %d features.',fieldName,numel(raw),n),fieldName,contextId,'','',''); end
            else
                diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','feature_vector',sprintf('%s dimensions %s require an explicit backprojection component selection for the %d-feature axis.',fieldName,mat2str(size(raw)),n),fieldName,contextId,'','','');
            end
            if available, status='valid'; end
        end

        function [x, diagnostic, status] = modelFeatureInspectionReadFeatureVector(v, fieldName, classIndex, nFeatures, component, contextId, indices)
            % modelFeatureInspectionReadFeatureVector  Resolve one exact selected feature vector or indexed subset.
            %
            % Ordinary nk_VisModelsC measures are classifier-indexed cells; FeatProb is
            % the single-cell feature-by-classifier exception. After exact classifier
            % projection, a value is either a feature vector or, for component-wise
            % VIS output, a validated feature-by-component matrix. Validation uses the
            % complete feature-axis dimensions; when indices are supplied only
            % those values cross the display boundary. Values are never averaged,
            % padded, truncated, or resolved through a second field authority.
            diagnostic=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0); status='absent';
            [raw,present]=NMResultsViewerTools.modelFeatureInspectionExactClassNumericField(v,fieldName,classIndex);
            x=[]; if ~present||isempty(raw), return; end
            status='invalid';
            if ~isreal(raw)
                status='invalid_complex';
                diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error','complex_feature_vector',sprintf([ ...
                    '%s contains complex values. The Results Viewer requires an upstream scientific contract that defines a real-valued transformation before this measure can be displayed.'],fieldName), ...
                    fieldName,contextId,'modelFeatureInspectionReadFeatureVector','',''); return;
            end
            n=max(0,round(double(nFeatures)));
            if n<1, diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error','feature_vector',sprintf('%s cannot be resolved without a positive feature count.',fieldName),fieldName,contextId,'','',''); return; end
            subset=~isempty(indices);
            if subset
                indices=double(indices(:));
                if any(~isfinite(indices)|indices~=round(indices)|indices<1|indices>n)
                    diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error','feature_vector_subset',sprintf('%s requested feature indices outside the resolved %d-feature axis.',fieldName,n),fieldName,contextId,'modelFeatureInspectionReadFeatureVector','',''); return;
                end
            end

            candidate=[];
            if ~isempty(component.componentId)
                if ndims(raw)~=2
                    diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_extraction',sprintf('%s must be a 2-D feature vector or feature-by-component matrix.',fieldName),fieldName,contextId,component.componentId,'',''); return;
                end
                if size(raw,1)==n&&size(raw,2)>1 % nm2-allow: validate nk_VisModelsC feature-by-component axis against persisted component counts
                    if size(raw,2)==component.nRetainedComponents, col=component.componentPosition;
                    elseif size(raw,2)==component.nAllComponents, col=component.componentIndex;
                    else, diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_extraction',sprintf('%s has %d columns; expected %d retained or %d total components.',fieldName,size(raw,2),component.nRetainedComponents,component.nAllComponents),fieldName,contextId,component.componentId,'',''); return;
                    end
                    if col<1||col>size(raw,2), diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('error','component_extraction',sprintf('%s cannot resolve component column %d.',fieldName,col),fieldName,contextId,component.componentId,'',''); return; end
                    if subset, candidate=raw(indices,col); else, candidate=raw(:,col); end
                elseif isvector(raw)&&numel(raw)==n % nm2-allow: exact writer feature-vector axis validation
                    if subset, candidate=raw(indices); else, candidate=raw(:); end
                else
                    diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_extraction',sprintf('%s dimensions %s are incompatible with %d features and the selected component axis.',fieldName,mat2str(size(raw)),n),fieldName,contextId,component.componentId,'',''); return;
                end
            elseif isvector(raw)
                if numel(raw)~=n, diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','feature_vector',sprintf('%s contains %d values; expected exactly %d features.',fieldName,numel(raw),n),fieldName,contextId,'','',''); return; end
                if subset, candidate=raw(indices); else, candidate=raw(:); end
            else
                diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','feature_vector',sprintf('%s dimensions %s require an explicit backprojection component selection for the %d-feature axis.',fieldName,mat2str(size(raw)),n),fieldName,contextId,'','',''); return;
            end
            [x,diagnostic,status]=NMResultsViewerTools.modelFeatureInspectionValidateDisplayVector(candidate,fieldName,contextId);
        end

        function [x, diagnostic, status] = modelFeatureInspectionValidateDisplayVector(candidate, fieldName, contextId)
            % modelFeatureInspectionValidateDisplayVector  Normalize per-feature missing values at the display boundary.
            x=double(candidate(:));
            diagnostic=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            status='valid';
            infMask=isinf(x);
            if any(infMask)
                x(infMask)=NaN;
                diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'warning','infinite_feature_values_as_missing',sprintf([ ...
                    '%s contains %d positive or negative infinite value(s); these entries are treated as missing ' ...
                    'for Feature Inspection while finite feature values remain available.'], ...
                    fieldName,nnz(infMask)),fieldName,contextId, ...
                    'modelFeatureInspectionReadFeatureVector','','');
            end
            if ~any(isfinite(x))
                x=[];
                status='no_finite_values';
                diagnostic=NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                    'warning','feature_vector_no_finite_values',sprintf( ...
                    '%s contains no finite feature values and cannot be displayed.',fieldName), ...
                    fieldName,contextId,'modelFeatureInspectionReadFeatureVector','','');
            end
        end

        function [bundle, diagnostics] = modelFeatureInspectionFeatureVectorBundle(v, measure, classIndex, nFeatures, component, contextId, indices, displayValues)
            % modelFeatureInspectionFeatureVectorBundle  Resolve secondary metrics only for retained display rows.
            names={'displaySE','meanWeight','seWeight','cvRatio','featProb','prob','signConsistency','signZ','signLogP','signLogQ','spearman','pearson','spearmanP','pearsonP','spearmanQ','pearsonQ','permZ','permP','permQ','analyticalP','analyticalQ'};
            fields={measure.seSourceField,'MEAN','SE','CVRatio','FeatProb','Prob_CV2','SignBased_CV2','SignBased_CV2_z','SignBased_CV2_p_uncorr','SignBased_CV2_p_fdr','Spearman_CV2','Pearson_CV2','Spearman_CV2_p_uncorr','Pearson_CV2_p_uncorr','Spearman_CV2_p_fdr','Pearson_CV2_p_fdr','PermZ_CV2','PermProb_CV2','PermProb_CV2_FDR','Analytical_p','Analyitcal_p_fdr'};
            bundle=struct('displayValue',double(displayValues(:))); diagnostics=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,numel(names)); dCount=0;
            for ii=1:numel(names)
                if isempty(fields{ii}), bundle.(names{ii})=[]; continue; end
                [x,d]=NMResultsViewerTools.modelFeatureInspectionReadFeatureVector(v,fields{ii},classIndex,nFeatures,component,contextId,indices);
                bundle.(names{ii})=x;
                if ~isempty(d), dCount=dCount+1; diagnostics(dCount)=d; end
            end
            diagnostics=diagnostics(1:dCount);
        end

        function [contexts,measures,spatialMaps,selectedMeasureId,diagnostics] = modelFeatureInspectionMetadataPayload(NM,A,selectedContexts,resultTargetIndex,classIndex,requestedMeasureId,component,baseDiagnostics)
            % modelFeatureInspectionMetadataPayload  Resolve selector and renderer metadata without materializing scientific panel arrays.
            contextT=NMResultsViewerTools.modelFeatureInspectionContextTemplate();
            measureT=NMResultsViewerTools.modelFeatureInspectionMeasureTemplate();
            spatialT=NMResultsViewerTools.modelFeatureInspectionSpatialTemplate();
            diagT=NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate();
            contexts=repmat(contextT,1,numel(selectedContexts));
            maxMeasures=max(1,numel(selectedContexts)*numel(NMResultsViewerTools.modelFeatureInspectionMeasureDefinitions()));
            measures=repmat(measureT,1,maxMeasures);
            spatialMaps=repmat(spatialT,1,maxMeasures);
            diagnostics=repmat(diagT,1,max(1,numel(baseDiagnostics)+numel(selectedContexts)*24));
            dCount=numel(baseDiagnostics); if dCount>0, diagnostics(1:dCount)=baseDiagnostics; end
            mCount=0; spCount=0; selectedMeasureId=requestedMeasureId;
            measureSelectionResolved=false;
            for cc=1:numel(selectedContexts)
                ctx=selectedContexts(cc);
                v=NMResultsViewerTools.modelFeatureInspectionVisEntry(A,ctx.visRowIndex,resultTargetIndex);
                if ~NMResultsViewerTools.modelFeatureInspectionIsVisStruct(v)
                    dCount=dCount+1;
                    diagnostics(dCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic( ...
                        'error','metadata_context_extraction', ...
                        'The selected catalogue context no longer resolves to an inspectable VIS struct.', ...
                        '',ctx.contextId,'','','');
                    continue;
                end
                contexts(cc)=ctx;
                % Use the same authoritative measure catalogue resolver as the
                % imaging and non-imaging Feature Inspection pathways. Metadata-only
                % requests must not maintain a second VIS field-detection contract.
                [ctxMeasures,selectedMeasure,measureDiagnostics]= ...
                    NMResultsViewerTools.modelFeatureInspectionMeasuresForVis( ...
                    v,classIndex,ctx.nFeatures,ctx.contextId,selectedMeasureId,component,true);
                if ~isempty(measureDiagnostics)
                    needed=dCount+numel(measureDiagnostics); if needed>numel(diagnostics), diagnostics(needed+4)=diagT; end
                    diagnostics(dCount+1:needed)=measureDiagnostics; dCount=needed;
                end
                if ~measureSelectionResolved&&~isempty(selectedMeasure.measureId)
                    selectedMeasureId=selectedMeasure.measureId;
                    measureSelectionResolved=true;
                end
                if ~isempty(ctxMeasures)
                    nAdd=numel(ctxMeasures); measures(mCount+1:mCount+nAdd)=ctxMeasures; mCount=mCount+nAdd;
                end
                if ~strcmp(ctx.featureKind,'tabular')&&~isempty(ctxMeasures)
                    for mm=1:numel(ctxMeasures)
                        spCount=spCount+1;
                        [spatialMaps(spCount),spDiag]= ...
                            NMResultsViewerTools.modelFeatureInspectionSpatialMetadataPayload( ...
                            NM,v,ctx,ctxMeasures(mm),component);
                        if ~isempty(spDiag)
                            dCount=dCount+1; if dCount>numel(diagnostics), diagnostics(dCount+4)=diagT; end
                            diagnostics(dCount)=spDiag;
                        end
                    end
                end
            end
            contexts=contexts(arrayfun(@(x)~isempty(x.contextId),contexts));
            measures=measures(1:mCount); spatialMaps=spatialMaps(1:spCount); diagnostics=diagnostics(1:dCount);
        end

        function [sp,diagnostic] = modelFeatureInspectionSpatialMetadataPayload(NM,v,ctx,measure,component)
            % modelFeatureInspectionSpatialMetadataPayload  Build a representation descriptor without reading the selected measure vector.
            % Canonical ROI consumes ctx.roi* provenance projected by context construction; it does not reopen
            % NM.datadescriptor or search atlas-like fields. Non-ROI contexts use the descriptor adapter authority.
            diagnostic=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            sp=NMResultsViewerTools.modelFeatureInspectionSpatialTemplate();
            sp.spatialMapId=sprintf('%s_spatial_%s',ctx.contextId,measure.measureId);
            sp.contextId=ctx.contextId;
            if ~isempty(component.componentId)
                sp.componentId=component.componentId; sp.componentIndex=component.componentIndex; sp.componentLabel=component.componentLabel;
                sp.spatialMapId=sprintf('%s_c%d_spatial_%s',ctx.contextId,component.componentIndex,measure.measureId);
            end
            sp.measureId=measure.measureId; sp.mapKind=ctx.featureKind;
            sp.thresholdMode=measure.thresholdMode; sp.thresholdLow=measure.thresholdLow;
            sp.thresholdHigh=measure.thresholdHigh; sp.thresholdValue=measure.thresholdValue;
            sp.hasPositiveValues=false; sp.hasNegativeValues=false;

            if strcmp(ctx.featureKind,'connectivity_edge')
                summary=NMResultsViewerConnectivityAdapter.descriptorSummary(NM,ctx.varind);
                sp.artifactKind='connectivity_descriptor';
                sp.viewerMode='connectivity_representation';
                sp.representationFrontend='connectivity';
                sp.enabled=logical(summary.ok);
                sp.disabledReason='';
                if ~sp.enabled, sp.disabledReason=summary.message; end
                sp.nodeCount=summary.nNodes;
                sp.edgeCount=summary.nEdges;
                sp.hasNodeCoordinates=logical(summary.hasCompleteNodeCoordinates);
                % Spatial-summary/report consumers use this projected coordinate-availability fact;
                % connectivity coordinates are authoritative DataIO node
                % coordinates and do not imply that an atlas image was used.
                sp.hasAtlasCoordinates=sp.hasNodeCoordinates;
                sp.coordinateSpace=summary.nodeCoordinateSpace;
                sp.coordinateUnits=summary.nodeCoordinateUnits;
                sp.atlasFile=summary.atlasFile;
                sp.atlasDescriptorFile=summary.atlasLabelFile;
                return;
            end

            if strcmp(ctx.featureKind,'roi')
                sp.roiSpatialDomain=ctx.roiSpatialDomain; sp.roiIdentityModel=ctx.roiIdentityModel; sp.roiSpatialReferenceIdentity=ctx.roiSpatialReferenceIdentity;
                sp.hasAtlasCoordinates=logical(ctx.roiHasAtlasCoordinates);
                sp.atlasFile=ctx.roiAtlasFile;
                sp.hasIndexedVoxelPositions=strcmp(ctx.roiSpatialDomain,'volume') && ~isempty(ctx.roiAtlasFile);
                if strcmp(ctx.roiSpatialDomain,'volume')
                    sp.artifactKind='voxel_feature_map'; sp.viewerMode='browser_orthogonal_overlay'; sp.representationFrontend='imaging';
                    sp.enabled=~isempty(ctx.roiAtlasFile); sp.maskFile=ctx.roiAtlasFile;
                    if ~sp.enabled, sp.disabledReason='Canonical volumetric ROI provenance has no atlas image identity.'; else, sp.disabledReason=''; end
                elseif strcmp(ctx.roiSpatialDomain,'surface')
                    sp.artifactKind='surface_descriptor'; sp.viewerMode='native_surface_overlay'; sp.representationFrontend='imaging'; sp.enabled=true; sp.disabledReason='';
                else
                    sp.artifactKind='none'; sp.viewerMode='none'; sp.representationFrontend='tabular'; sp.enabled=false; sp.disabledReason='Canonical ROI provenance has no supported spatial domain.';
                end
                return;
            end

            descriptor=NMResultsViewerImagingDescriptorAdapter.resolve(NM,ctx.varind,v);
            if descriptor.ok, sp.maskFile=descriptor.featureSpaceFile; end
            if strcmp(ctx.featureKind,'surface_vertex'), sp.surfaceFile=sp.maskFile; end
            switch ctx.featureKind
                case 'voxel'
                    sp.artifactKind='voxel_feature_map'; sp.viewerMode='browser_orthogonal_overlay'; sp.representationFrontend='imaging';
                    hasFeatureSpace=descriptor.ok&&(descriptor.featureSpaceFileExists||descriptor.embeddedFeatureSpaceAvailable);
                    sp.enabled=hasFeatureSpace;
                    if ~hasFeatureSpace
                        sp.disabledReason=['The voxel modality exposes no readable space-defining image ' ...
                            'and no persisted Vm/Vmvol feature-space payload.'];
                    end
                case 'surface_vertex'
                    availability=NMResultsViewerSurfaceTools.catalogueAvailability(NM,ctx.varind,ctx.nFeatures);
                    sp.artifactKind='surface_descriptor'; sp.viewerMode='native_surface_overlay'; sp.representationFrontend='imaging';
                    sp.enabled=logical(availability.enabled);
                    if sp.enabled, sp.disabledReason=''; else, sp.disabledReason=availability.disabledReason; end
                otherwise
                    sp.artifactKind='none'; sp.viewerMode='none'; sp.representationFrontend='tabular'; sp.enabled=false;
                    sp.disabledReason='This tabular modality has no spatial feature-map renderer.';
            end
        end

        function [measures, selectedMeasure, diagnostics] = modelFeatureInspectionMeasuresForVis(v, classIndex, nFeatures, contextId, requestedMeasureId, component, metadataOnly)
            % modelFeatureInspectionMeasuresForVis  Detect measures through the active component-axis contract.
            defs = NMResultsViewerTools.modelFeatureInspectionMeasureDefinitions();
            tmpl = NMResultsViewerTools.modelFeatureInspectionMeasureTemplate();
            measures = repmat(tmpl, 1, numel(defs));
            diagnostics=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,numel(defs)*2); dCount=0;
            count = 0;
            for ii = 1:numel(defs)
                if metadataOnly
                    [available,d,vectorStatus]=NMResultsViewerTools.modelFeatureInspectionFeatureVectorAvailable(v,defs(ii).sourceField,classIndex,nFeatures,component,contextId);
                    if available, y = true; else, y = []; end
                else
                    [y,d,vectorStatus]=NMResultsViewerTools.modelFeatureInspectionReadFeatureVector(v,defs(ii).sourceField,classIndex,nFeatures,component,contextId,[]);
                end
                if ~isempty(d), dCount=dCount+1; diagnostics(dCount)=d; end
                invalidDisplayVector=strcmp(vectorStatus,'invalid_complex');
                if isempty(y) && ~invalidDisplayVector, continue; end
                count = count + 1;
                measures(count).contextId = contextId;
                measures(count).measureId = defs(ii).measureId;
                measures(count).label = defs(ii).label;
                measures(count).category = defs(ii).category;
                measures(count).sourceField = defs(ii).sourceField;
                measures(count).legacySourceField = defs(ii).sourceField;
                measures(count).valuePolarity = defs(ii).valuePolarity;
                measures(count).thresholdMode = defs(ii).thresholdMode;
                measures(count).thresholdLow = defs(ii).thresholdLow;
                measures(count).thresholdHigh = defs(ii).thresholdHigh;
                measures(count).thresholdValue = defs(ii).thresholdValue;
                measures(count).thresholdLabel = defs(ii).thresholdLabel;
                measures(count).seSourceField = defs(ii).seSourceField;
                if invalidDisplayVector
                    measures(count).enabled = false;
                    measures(count).disabledReason = sprintf([ ...
                        '%s contains complex values. An upstream scientific contract must define ' ...
                        'a real-valued transformation before this measure can be displayed.'], ...
                        defs(ii).sourceField);
                    continue;
                end
                if ~isempty(defs(ii).seSourceField)
                    if metadataOnly
                        [seAvailable,seDiag] = NMResultsViewerTools.modelFeatureInspectionFeatureVectorAvailable(v,defs(ii).seSourceField,classIndex,nFeatures,component,contextId);
                        if seAvailable, se = true; else, se = []; end
                    else
                        [se,seDiag] = NMResultsViewerTools.modelFeatureInspectionReadFeatureVector(v,defs(ii).seSourceField,classIndex,nFeatures,component,contextId,[]);
                    end
                    if ~isempty(seDiag), dCount=dCount+1; diagnostics(dCount)=seDiag; end
                    measures(count).hasSE = ~isempty(se);
                end
                measures(count).enabled = true;
                measures(count).disabledReason = '';
            end
            measures = measures(1:count); diagnostics=diagnostics(1:dCount);
            selectedMeasure = NMResultsViewerTools.modelFeatureInspectionMeasureTemplate();
            if isempty(measures), return; end
            if ~isempty(requestedMeasureId)
                for ii = 1:numel(measures)
                    if measures(ii).enabled && strcmpi(measures(ii).measureId, requestedMeasureId), selectedMeasure=measures(ii); return; end
                end
            end
            preferred = {'feature_weight_mean','cross_validation_ratio','feature_selection_probability'};
            for pp = 1:numel(preferred)
                for ii = 1:numel(measures)
                    if measures(ii).enabled && strcmpi(measures(ii).measureId, preferred{pp}), selectedMeasure=measures(ii); return; end
                end
            end
            enabledIndex=find([measures.enabled],1,'first');
            if ~isempty(enabledIndex), selectedMeasure=measures(enabledIndex); end
        end

        function rows = modelFeatureInspectionSummaryRows(payload)
            % modelFeatureInspectionSummaryRows  Summarize the selected modality and component context.
            tmpl = struct('metric','','value','');
            rows = repmat(tmpl, 1, 12);
            rows(1) = struct('metric','Viewspace','value','Model feature inspection');
            rows(2) = struct('metric','Analysis index','value',num2str(payload.analysisIndex));
            rows(3) = struct('metric','Target index','value',num2str(payload.targetIndex));
            rows(4) = struct('metric','VIS result target','value',num2str(payload.resultTargetIndex));
            rows(5) = struct('metric','Feature source','value',payload.selectedFeatureContext.selectionLabel);
            rows(6) = struct('metric','Available feature sources','value',num2str(numel(payload.featureContexts)));
            rows(7) = struct('metric','Physical contexts loaded','value',num2str(numel(payload.contexts)));
            if payload.backprojectionAvailable
                compLabel=payload.selectedBackprojectionComponentLabel;
            else
                compLabel='Not component-resolved';
            end
            rows(8) = struct('metric','Backprojected component','value',compLabel);
            rows(9) = struct('metric','Available retained components','value',num2str(numel(payload.backprojectionComponents)));
            rows(10) = struct('metric','Measures','value',num2str(numel(payload.measures)));
            rows(11) = struct('metric','Displayed feature rows','value',num2str(numel(payload.featureTable)));
            rows(12) = struct('metric','Component statistics rows','value',num2str(numel(payload.componentAnalysis.componentTable)));
        end

        function [rows, diagnostics] = modelFeatureInspectionFeatureRows(NM, v, ctx, measure, classIndex, maxFeatures, component)
            % modelFeatureInspectionFeatureRows  Materialize a bounded ranked projection of one feature vector.
            rows=repmat(NMResultsViewerTools.modelFeatureInspectionFeatureRowTemplate(),1,0); diagnostics=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            if isempty(measure.measureId)||ctx.nFeatures<1, return; end
            n=ctx.nFeatures;
            [displayValue,displayDiagnostic]=NMResultsViewerTools.modelFeatureInspectionReadFeatureVector(v,measure.sourceField,classIndex,n,component,ctx.contextId,[]);
            if isempty(displayValue), if ~isempty(displayDiagnostic), diagnostics=displayDiagnostic; end; return; end
            finiteIndex=find(isfinite(displayValue)); nAvailable=numel(finiteIndex); nDisplay=min(nAvailable,maxFeatures);
            if nDisplay<1, if ~isempty(displayDiagnostic), diagnostics=displayDiagnostic; end; return; end

            scores=abs(displayValue(finiteIndex));
            if nDisplay<nAvailable
                topScores=maxk(scores,nDisplay); cutoff=topScores(end);
                strict=finiteIndex(scores>cutoff); ties=finiteIndex(scores==cutoff); needed=nDisplay-numel(strict);
                displayOrder=[strict;ties(1:needed)];
            else
                displayOrder=finiteIndex;
            end
            [~,localOrder]=sortrows([-abs(displayValue(displayOrder)) double(displayOrder)],[1 2]); displayOrder=displayOrder(localOrder);
            selectedDisplayValue=displayValue(displayOrder);
            [vectors,vectorDiagnostics]=NMResultsViewerTools.modelFeatureInspectionFeatureVectorBundle(v,measure,classIndex,n,component,ctx.contextId,displayOrder,selectedDisplayValue);
            diagnosticTemplate=NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate();
            diagnosticBuffer=repmat(diagnosticTemplate,1,numel(vectorDiagnostics)+2); diagnosticCount=0;
            if ~isempty(displayDiagnostic), diagnosticCount=1; diagnosticBuffer(1)=displayDiagnostic; end
            if ~isempty(vectorDiagnostics), diagnosticBuffer(diagnosticCount+1:diagnosticCount+numel(vectorDiagnostics))=vectorDiagnostics; diagnosticCount=diagnosticCount+numel(vectorDiagnostics); end
            if nDisplay<nAvailable
                diagnosticCount=diagnosticCount+1;
                diagnosticBuffer(diagnosticCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('info','feature_table_truncation',sprintf( ...
                    'Feature table for %s was truncated from %d to %d displayed rows. Use spec.maxFeatures to adjust this limit.',ctx.contextId,nAvailable,nDisplay), ...
                    measure.sourceField,ctx.contextId,'','','');
            end
            diagnostics=diagnosticBuffer(1:diagnosticCount);

            displayContract=NMResultsViewerDisplaySemanticsTools.resolveContract(displayValue,measure,struct('DisplayRangeMode','full_data_range'), ...
                struct('contextId',ctx.contextId,'measureId',measure.measureId,'pathway','feature_inspection_payload'));
            displayEligibility=NMResultsViewerDisplaySemanticsTools.eligibilityMask(displayValue,displayContract,true(size(displayValue)));
            [~,signedOrder]=sort(displayValue(finiteIndex),'descend'); signedRanks=nan(n,1); signedRanks(finiteIndex(signedOrder))=(1:nAvailable)';
            selectedEligibility=displayEligibility(displayOrder); selectedSignedRanks=signedRanks(displayOrder);
            displaySE=nan(nDisplay,1); if ~isempty(vectors.displaySE), displaySE=vectors.displaySE; end
            featureNames=NMResultsViewerTools.modelFeatureInspectionFeatureNames(NM,ctx.varind,n,displayOrder,ctx);
            rows=repmat(NMResultsViewerTools.modelFeatureInspectionFeatureRowTemplate(),1,nDisplay);
            hasComponent=~isempty(component.componentId);
            for rr=1:nDisplay
                idx=displayOrder(rr); value=vectors.displayValue(rr);
                [barState,labelState,errState]=NMResultsViewerTools.modelFeatureInspectionPresentationState(value,displaySE(rr),selectedEligibility(rr));
                [provId,provSummary]=NMResultsViewerTools.modelFeatureInspectionFeatureProvenance(NM,ctx.varind,idx,ctx.featureKind,featureNames{rr});
                if hasComponent
                    rows(rr).rowId=sprintf('%s:c%d:f%d',ctx.contextId,component.componentIndex,idx); rows(rr).componentId=component.componentId; rows(rr).componentIndex=component.componentIndex; rows(rr).componentLabel=component.componentLabel;
                else, rows(rr).rowId=sprintf('%s:f%d',ctx.contextId,idx); end
                rows(rr).contextId=ctx.contextId; rows(rr).measureId=measure.measureId; rows(rr).featureIndex=idx; rows(rr).featureName=featureNames{rr};
                rows(rr).displayValue=value; rows(rr).displaySE=displaySE(rr);
                rows(rr).meanWeight=NMResultsViewerTools.modelFeatureInspectionPick(vectors.meanWeight,rr); rows(rr).seWeight=NMResultsViewerTools.modelFeatureInspectionPick(vectors.seWeight,rr);
                rows(rr).crossValidationRatio=NMResultsViewerTools.modelFeatureInspectionPick(vectors.cvRatio,rr); rows(rr).featureSelectionProbability=NMResultsViewerTools.modelFeatureInspectionPick(vectors.featProb,rr);
                rows(rr).reliabilityProbability95CI=NMResultsViewerTools.modelFeatureInspectionPick(vectors.prob,rr); rows(rr).signConsistency=NMResultsViewerTools.modelFeatureInspectionPick(vectors.signConsistency,rr);
                rows(rr).signConsistencyZ=NMResultsViewerTools.modelFeatureInspectionPick(vectors.signZ,rr); rows(rr).signConsistencyLogP=NMResultsViewerTools.modelFeatureInspectionPick(vectors.signLogP,rr); rows(rr).signConsistencyLogQ=NMResultsViewerTools.modelFeatureInspectionPick(vectors.signLogQ,rr);
                rows(rr).spearmanAssociation=NMResultsViewerTools.modelFeatureInspectionPick(vectors.spearman,rr); rows(rr).pearsonAssociation=NMResultsViewerTools.modelFeatureInspectionPick(vectors.pearson,rr);
                rows(rr).spearmanLogP=NMResultsViewerTools.modelFeatureInspectionPick(vectors.spearmanP,rr); rows(rr).pearsonLogP=NMResultsViewerTools.modelFeatureInspectionPick(vectors.pearsonP,rr);
                rows(rr).spearmanLogQ=NMResultsViewerTools.modelFeatureInspectionPick(vectors.spearmanQ,rr); rows(rr).pearsonLogQ=NMResultsViewerTools.modelFeatureInspectionPick(vectors.pearsonQ,rr);
                rows(rr).permutationZ=NMResultsViewerTools.modelFeatureInspectionPick(vectors.permZ,rr); rows(rr).permutationLogP=NMResultsViewerTools.modelFeatureInspectionPick(vectors.permP,rr); rows(rr).permutationLogQ=NMResultsViewerTools.modelFeatureInspectionPick(vectors.permQ,rr);
                rows(rr).analyticalLogP=NMResultsViewerTools.modelFeatureInspectionPick(vectors.analyticalP,rr); rows(rr).analyticalLogQ=NMResultsViewerTools.modelFeatureInspectionPick(vectors.analyticalQ,rr);
                rows(rr).thresholdPassed=logical(selectedEligibility(rr)); rows(rr).barState=barState; rows(rr).labelState=labelState; rows(rr).errorBarState=errState;
                rows(rr).sortSignedRank=selectedSignedRanks(rr); rows(rr).sortAbsRank=rr; rows(rr).featureKind=ctx.featureKind;
                if hasComponent, rows(rr).provenanceId=sprintf('%s:c%d:%s',ctx.contextId,component.componentIndex,provId); else, rows(rr).provenanceId=sprintf('%s:%s',ctx.contextId,provId); end
                rows(rr).tooltipTitle=featureNames{rr};
                if hasComponent, rows(rr).tooltipSubtitle=sprintf('%s, %s, %s',ctx.modalityLabel,component.componentLabel,measure.label); else, rows(rr).tooltipSubtitle=sprintf('%s, %s',ctx.modalityLabel,measure.label); end
                rows(rr).tooltipMetricPrimary=value; rows(rr).tooltipMetricPrimaryLabel=measure.label; rows(rr).tooltipMetricSE=displaySE(rr);
                if measure.hasSE, rows(rr).tooltipMetricSELabel='Standard error'; else, rows(rr).tooltipMetricSELabel=''; end
                rows(rr).tooltipThresholdLabel=measure.thresholdLabel; rows(rr).tooltipThresholdPassed=rows(rr).thresholdPassed;
                rows(rr).tooltipRankSigned=rows(rr).sortSignedRank; rows(rr).tooltipRankAbsolute=rows(rr).sortAbsRank; rows(rr).tooltipSelectionProbability=rows(rr).featureSelectionProbability;
                rows(rr).tooltipStabilitySummary=NMResultsViewerTools.modelFeatureInspectionStabilitySummary(rows(rr)); rows(rr).tooltipSourceField=measure.sourceField; rows(rr).tooltipProvenanceSummary=provSummary;
            end
        end

        function [names, available, source] = modelFeatureInspectionFeatureNames(NM, varind, nFeatures, indices, context)
            % modelFeatureInspectionFeatureNames  Resolve names from the authority owning the resolved feature space.
            names=cell(numel(indices),1); available=false; source='none';
            isStacking=false; isProjectedFusion=false;
            % nm2-allow: production supports ordinary four-argument DataIO names and five-argument analysis-context VIS names.
            if nargin==5
                fusionMode=context.fusionMode;
                isProjectedFusion=ismember(fusionMode,{'early','intermediate'});
                A=NM.analysis{context.analysisIndex};
                isStacking=NMResultsViewerTools.analysisStackingActive(A);
                if isStacking||isProjectedFusion
                    v=NMResultsViewerTools.modelFeatureInspectionVisEntry(A,context.visRowIndex,context.resultTargetIndex);
                    raw=v.params.features(:);
                    if isStacking
                        if isequal(raw,{[]})
                            sourceIndices=A.params.TrainParam.STACKING.sel_anal;
                            raw=cellfun(@(a)a.id,NM.analysis(sourceIndices),'UniformOutput',false);
                            raw=raw(:);
                            source='analysis.params.TrainParam.STACKING.sel_anal';
                        else
                            source='analysis.visdata.params.features';
                        end
                    else
                        source='analysis.visdata.params.features (fusion member)';
                    end
                end
            end
            if ~(isStacking||isProjectedFusion)
                raw=NMDataIOImportTools.trainingFeatureNames(NM,varind);
                if isempty(raw), return; end
                raw=raw(:);
                source='NM.featnames';
            end
            nameCount=numel(raw);
            % nm2-allow: feature names must equal the resolved Feature Inspection scientific feature axis.
            if nameCount~=round(double(nFeatures))
                error('NMResultsViewerTools:FeatureNameCountMismatch', ...
                    '%s contains %d names but the resolved feature space contains %d features.',source,nameCount,round(double(nFeatures)));
            end
            available=true;
            if isempty(indices), return; end
            indices=round(double(indices(:)));
            % nm2-allow: requested feature-name indices must lie on the resolved scientific feature axis.
            if any(~isfinite(indices)|indices<1|indices>nameCount)
                error('NMResultsViewerTools:InvalidFeatureNameIndex','Requested feature-name indices are outside %s.',source);
            end
            names=raw(indices);
            names=names(:);
        end

        function [barState, labelState, errorBarState] = modelFeatureInspectionPresentationState(value, se, passed)
            if ~isfinite(double(value))
                barState = 'missing'; labelState = 'missing'; errorBarState = 'missing'; return;
            end
            if logical(passed)
                barState = 'active'; labelState = 'active';
                if isfinite(double(se)), errorBarState = 'active'; else, errorBarState = 'missing'; end
            else
                barState = 'below_threshold'; labelState = 'greyed';
                if isfinite(double(se)), errorBarState = 'greyed'; else, errorBarState = 'missing'; end
            end
        end

        function v = modelFeatureInspectionPick(vec, idx)
            if isempty(vec), v=NaN; else, v=vec(idx); end
        end

        function txt = modelFeatureInspectionStabilitySummary(row)
            parts = cell(1,3);
            k = 0;
            if isfinite(row.crossValidationRatio), k = k + 1; parts{k} = sprintf('CVR %.4g', row.crossValidationRatio); end
            if isfinite(row.signConsistencyZ), k = k + 1; parts{k} = sprintf('sign z %.4g', row.signConsistencyZ); end
            if isfinite(row.permutationLogQ), k = k + 1; parts{k} = sprintf('perm q %.4g', row.permutationLogQ); end
            if k < 1, txt = 'No secondary stability metric available.'; else, txt = strjoin(parts(1:k), ', '); end
        end

        function [provenanceId, summary] = modelFeatureInspectionFeatureProvenance(NM, varind, featureIndex, featureKind, featureName)
            provenanceId=sprintf('%s:%d:%d',featureKind,round(double(varind)),round(double(featureIndex)));
            switch featureKind
                case 'connectivity_edge'
                    descriptor=NMResultsViewerConnectivityAdapter.descriptorSummary(NM,varind);
                    if ~descriptor.ok
                        error('NMResultsViewerTools:ConnectivityDescriptorUnavailable','%s',descriptor.message);
                    end
                    % nm2-allow: connectivity featureIndex addresses the persisted DataIO edge axis.
                    if featureIndex<1 || featureIndex>descriptor.nEdges
                        error('NMResultsViewerTools:ConnectivityFeatureIndexOutOfRange', ...
                            'Connectivity feature index %d is outside the persisted %d-edge axis.',featureIndex,descriptor.nEdges);
                    end
                    summary=sprintf('Connectivity edge %s',descriptor.edgeNames{featureIndex});
                case 'roi'
                    summary=sprintf('ROI feature %s',featureName);
                case 'voxel'
                    summary=sprintf('Voxelwise feature %d, modality %d',round(double(featureIndex)),round(double(varind)));
                case 'surface_vertex'
                    summary=sprintf('Surface vertex %d, modality %d',round(double(featureIndex)),round(double(varind)));
                otherwise
                    summary=sprintf('Tabular feature %s, modality %d',featureName,round(double(varind)));
            end
        end

        function [mx, diagnostics] = modelFeatureInspectionMatrixPayload(NM, v, ctx, classIndex, component) %#ok<INUSD>
            % modelFeatureInspectionMatrixPayload  Build the invariant feature-relation contract.
            %
            % Backprojection-component selection is accepted only to preserve the
            % historical private call signature. It does not enter the matrix identity,
            % cache semantics, values, or provenance because CorrMat_CV2 is generated
            % only for non-decomposed feature spaces and is component-invariant.
            [mx, diagnostics] = NMResultsViewerFeatureRelationTools.buildMatrixPayload(v,ctx,classIndex);
            if mx.available&&mx.inlineTransferAvailable
                [names,hasNames]=NMResultsViewerTools.modelFeatureInspectionFeatureNames(NM,ctx.varind,ctx.nFeatures,1:ctx.nFeatures,ctx);
                if hasNames, mx.labels=names; end
            end
        end

        function net = modelFeatureInspectionNetworkPayload(mx, ctx)
            % modelFeatureInspectionNetworkPayload  Describe a graph source without constructing graph topology.
            net = NMResultsViewerTools.modelFeatureInspectionNetworkTemplate();
            net.networkId = sprintf('%s_network', ctx.contextId);
            net.contextId = ctx.contextId;
            net.matrixId = mx.matrixId;
            net.componentId = '';
            net.componentIndex = NaN;
            net.componentLabel = '';
            net.componentApplicability = 'invariant';
            net.componentSelectionAffectsContent = false;
            net.sourceField = mx.sourceField;
            net.available = logical(mx.available);
            net.enabled = false;
            if mx.available
                net.disabledReason = ['Graph topology is not available for this relation payload. ' ...
                    'The descriptor contains normalized component-invariant relation data, but no graph topology.'];
            else
                net.disabledReason = mx.disabledReason;
            end
        end

        function [sp, diagnostic] = modelFeatureInspectionSpatialPayload(NM, v, ctx, measure, component)
            % modelFeatureInspectionSpatialPayload  Bind one feature vector to established spatial context metadata.
            % Canonical ROI consumes ctx.roi* provenance only; no atlas/annotation rediscovery occurs here.
            diagnostic=repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            sp = NMResultsViewerTools.modelFeatureInspectionSpatialTemplate();
            sp.spatialMapId = sprintf('%s_spatial_%s', ctx.contextId, measure.measureId);
            sp.contextId = ctx.contextId;
            if ~isempty(component.componentId), sp.componentId=component.componentId; sp.componentIndex=component.componentIndex; sp.componentLabel=component.componentLabel; sp.spatialMapId=sprintf('%s_c%d_spatial_%s',ctx.contextId,component.componentIndex,measure.measureId); end
            sp.measureId = measure.measureId;
            sp.mapKind = ctx.featureKind;
            sp.thresholdMode = measure.thresholdMode;
            sp.thresholdLow = measure.thresholdLow;
            sp.thresholdHigh = measure.thresholdHigh;
            sp.thresholdValue = measure.thresholdValue;
            [values,diagnostic] = NMResultsViewerTools.modelFeatureInspectionReadFeatureVector(v,measure.sourceField,ctx.classIndex,ctx.nFeatures,component,ctx.contextId,[]);
            sp.hasPositiveValues = any(values > 0 & isfinite(values));
            sp.hasNegativeValues = any(values < 0 & isfinite(values));

            if strcmp(ctx.featureKind,'connectivity_edge')
                summary=NMResultsViewerConnectivityAdapter.descriptorSummary(NM,ctx.varind);
                sp.artifactKind='connectivity_descriptor';
                sp.viewerMode='connectivity_representation';
                sp.representationFrontend='connectivity';
                sp.enabled=logical(summary.ok)&&~isempty(values);
                if ~summary.ok
                    sp.disabledReason=summary.message;
                elseif isempty(values)
                    sp.disabledReason=sprintf('Measure %s does not resolve to an exact connectivity-edge feature vector.',measure.measureId);
                else
                    sp.disabledReason='';
                end
                sp.nodeCount=summary.nNodes;
                sp.edgeCount=summary.nEdges;
                sp.hasNodeCoordinates=logical(summary.hasCompleteNodeCoordinates);
                sp.hasAtlasCoordinates=sp.hasNodeCoordinates;
                sp.coordinateSpace=summary.nodeCoordinateSpace;
                sp.coordinateUnits=summary.nodeCoordinateUnits;
                sp.atlasFile=summary.atlasFile;
                sp.atlasDescriptorFile=summary.atlasLabelFile;
                return;
            end

            if strcmp(ctx.featureKind,'roi')
                sp.roiSpatialDomain = ctx.roiSpatialDomain;
                sp.roiIdentityModel = ctx.roiIdentityModel;
                sp.roiSpatialReferenceIdentity = ctx.roiSpatialReferenceIdentity;
                sp.hasAtlasCoordinates = logical(ctx.roiHasAtlasCoordinates);
                sp.atlasFile = ctx.roiAtlasFile;
                sp.hasIndexedVoxelPositions = strcmp(ctx.roiSpatialDomain,'volume') && ~isempty(ctx.roiAtlasFile);
                if strcmp(ctx.roiSpatialDomain,'volume')
                    sp.artifactKind = 'voxel_feature_map';
                    sp.viewerMode = 'browser_orthogonal_overlay';
                    sp.representationFrontend='imaging';
                    sp.enabled = ~isempty(values) && ~isempty(ctx.roiAtlasFile);
                    sp.maskFile = ctx.roiAtlasFile;
                    if isempty(values)
                        sp.disabledReason=sprintf('Measure %s does not resolve to an exact ROI feature vector.',measure.measureId);
                    elseif isempty(ctx.roiAtlasFile)
                        sp.disabledReason='Canonical volumetric ROI provenance has no atlas image identity.';
                    else
                        sp.disabledReason='';
                    end
                elseif strcmp(ctx.roiSpatialDomain,'surface')
                    sp.artifactKind='surface_descriptor'; sp.viewerMode='native_surface_overlay'; sp.representationFrontend='imaging';
                    sp.enabled=~isempty(values);
                    if ~sp.enabled, sp.disabledReason=sprintf('Measure %s does not resolve to an exact ROI feature vector.',measure.measureId); else, sp.disabledReason=''; end
                else
                    sp.artifactKind='none'; sp.viewerMode='none'; sp.representationFrontend='tabular'; sp.enabled=false; sp.disabledReason='Canonical ROI provenance has no supported spatial domain.';
                end
                return;
            end

            descriptor = NMResultsViewerImagingDescriptorAdapter.resolve(NM,ctx.varind,v);
            if descriptor.ok
                sp.maskFile = descriptor.featureSpaceFile;
            end
            if strcmp(ctx.featureKind,'surface_vertex'), sp.surfaceFile = sp.maskFile; end
            switch ctx.featureKind
                case 'voxel'
                    sp.artifactKind = 'voxel_feature_map';
                    sp.viewerMode = 'browser_orthogonal_overlay';
                    sp.representationFrontend='imaging';
                    hasFeatureSpace = descriptor.ok && ...
                        (descriptor.featureSpaceFileExists || descriptor.embeddedFeatureSpaceAvailable);
                    sp.enabled = ~isempty(values) && hasFeatureSpace;
                    if isempty(values)
                        sp.disabledReason = sprintf('Measure %s does not resolve to an exact voxel feature vector.',measure.measureId);
                    elseif ~hasFeatureSpace
                        sp.disabledReason = ['The voxel modality exposes no readable space-defining image ' ...
                            'and no persisted Vm/Vmvol feature-space payload.'];
                    else
                        sp.disabledReason = '';
                    end
                case 'surface_vertex'
                    availability = NMResultsViewerSurfaceTools.catalogueAvailability(NM,ctx.varind,ctx.nFeatures);
                    sp.artifactKind = 'surface_descriptor';
                    sp.viewerMode = 'native_surface_overlay';
                    sp.representationFrontend='imaging';
                    sp.enabled = logical(availability.enabled) && ~isempty(values);
                    if isempty(values)
                        sp.disabledReason = sprintf('Measure %s does not resolve to an exact surface-vertex feature vector.',measure.measureId);
                    elseif ~availability.enabled
                        sp.disabledReason = availability.disabledReason;
                    else
                        sp.disabledReason = '';
                    end
                otherwise
                    sp.artifactKind = 'none';
                    sp.viewerMode = 'none';
                    sp.representationFrontend='tabular';
                    sp.enabled = false;
                    sp.disabledReason = 'This tabular modality has no spatial feature-map renderer.';
            end
        end

        function [analysis, diagnostics] = modelFeatureInspectionNormalizeFusionReport(A, physicalContexts, classIndex, maxComponents)
            % modelFeatureInspectionNormalizeFusionReport  Normalize persisted fusion summaries.
            %
            % nk_VisXHelperC('report_final') owns the Report schema. ReportFinal
            % is replicated across rows produced by one nk_VisModelsC invocation.
            % Late fusion invokes nk_VisModelsC separately per modality, so it has
            % no analysis-wide shared Report to normalize here.
            analysis = NMResultsViewerTools.emptyModelFeatureInspectionComponentAnalysis();
            diagnostics = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            if isempty(physicalContexts), return; end
            fusionMode = NMResultsViewerTools.analysisFusionMode(A);
            if strcmp(fusionMode,'late'), return; end
            owner = physicalContexts(1);
            v = NMResultsViewerTools.modelFeatureInspectionVisEntry(A, owner.visRowIndex, owner.resultTargetIndex);
            [R, reportOk, reportMessage] = NMResultsViewerTools.modelFeatureInspectionReportForClass(v, classIndex);
            if ~reportOk
                if isempty(reportMessage) && ismember(fusionMode, {'early','intermediate'})
                    reportMessage = sprintf('The %s-fusion VIS context has no classifier-specific Report required for modality/component share normalization.', fusionMode);
                end
                if ~isempty(reportMessage)
                    diagnostics = NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', 'fusion_report', reportMessage, 'Report', owner.contextId, '', '', '');
                end
                return;
            end

            diagBlocks = cell(1,3); nDiag = 0;
            [modalityRows, d] = NMResultsViewerTools.modelFeatureInspectionNormalizeModalityShares(R, physicalContexts);
            if ~isempty(d), nDiag = nDiag + 1; diagBlocks{nDiag} = d; end

            componentRows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,0);
            componentModalityRows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentModalityTemplate(),1,0);
            % nm2-allow: nk_VisXHelperC report_final writes Report.components only when component-wise ModComp_L2n data exist.
            if isfield(R,'components') && ~isempty(R.components)
                [componentRows, d] = NMResultsViewerTools.modelFeatureInspectionNormalizeComponentShares( ...
                    R, physicalContexts, owner.contextId, fusionMode, maxComponents);
                if ~isempty(d), nDiag = nDiag + 1; diagBlocks{nDiag} = d; end
                if ~strcmp(fusionMode,'intermediate')
                    [componentModalityRows, d] = NMResultsViewerTools.modelFeatureInspectionNormalizeComponentModalityShares(R, owner.contextId);
                    if ~isempty(d), nDiag = nDiag + 1; diagBlocks{nDiag} = d; end
                end
            end

            analysis.modalityShareTable = modalityRows;
            analysis.componentTable = componentRows;
            analysis.componentModalityTable = componentModalityRows;
            analysis.ok = ~isempty(modalityRows) || ~isempty(componentRows) || ~isempty(componentModalityRows);
            if analysis.ok
                analysis.message = sprintf('Fusion report contains %d modality-share, %d component, and %d component-by-modality row(s).', numel(modalityRows), numel(componentRows), numel(componentModalityRows));
            else
                analysis.message = 'The stored fusion report contains no supported normalized modality or component summaries.';
            end
            if nDiag > 0, diagnostics = [diagBlocks{1:nDiag}]; end
            analysis.diagnostics = diagnostics;
        end

        function [R, ok, message] = modelFeatureInspectionReportForClass(v, classIndex)
            % modelFeatureInspectionReportForClass  Select the writer-defined classifier report.
            R = struct(); ok = false; message = '';
            % nm2-allow: nk_VisModelsC writes visdata.Report only when nk_VisXHelperC produced ReportFinal.
            if ~isfield(v,'Report'), return; end
            raw = v.Report;
            classIndex = max(1, round(double(classIndex)));
            if classIndex > numel(raw)
                message = sprintf('VIS Report does not contain a report for classifier %d.', classIndex);
                return;
            end
            R = raw{classIndex};
            ok = true;
        end

        function [rows, diagnostic] = modelFeatureInspectionNormalizeModalityShares(R, physicalContexts)
            % modelFeatureInspectionNormalizeModalityShares  Project Report.modality.
            rows = repmat(NMResultsViewerTools.modelFeatureInspectionModalityShareTemplate(),1,0);
            diagnostic = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            M = R.modality;
            if isempty(M.median), return; end

            names = M.names(:);
            med = double(M.median(:));
            meanV = double(M.mean(:));
            lo = double(M.lo95(:));
            hi = double(M.hi95(:));
            coverage = double(M.coverage);
            n = numel(names);
            % nm2-allow: nk_VisXHelperC report_final defines one shared modality axis; reject corrupted persisted Report arrays.
            if any([numel(med) numel(meanV) numel(lo) numel(hi)] ~= n) || ~isequal(size(coverage), [n 2])
                diagnostic = NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', 'fusion_report.modality', ...
                    'Report.modality arrays do not share the writer-defined modality axis.', ...
                    'Report.modality', '', '', '', '');
                return;
            end

            rows = repmat(NMResultsViewerTools.modelFeatureInspectionModalityShareTemplate(), 1, n);
            for ii = 1:n
                rows(ii).modalityIndex = ii;
                rows(ii).modalityLabel = names{ii};
                rows(ii).medianShare = med(ii);
                rows(ii).meanShare = meanV(ii);
                rows(ii).lo95 = lo(ii);
                rows(ii).hi95 = hi(ii);
                rows(ii).coverageN = coverage(ii,1);
                rows(ii).coverageTotal = coverage(ii,2);
                contextHit = find([physicalContexts.visRowIndex] == ii, 1, 'first');
                if ~isempty(contextHit), rows(ii).contextId = physicalContexts(contextHit).contextId; end
                rows(ii).sourceField = 'Report.modality';
            end
        end

        function [rows, diagnostic] = modelFeatureInspectionNormalizeComponentShares(R, physicalContexts, ownerContextId, fusionMode, maxComponents)
            % modelFeatureInspectionNormalizeComponentShares  Project the exact report branch for this fusion mode.
            rows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,0);
            diagnostic = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            if ~strcmp(fusionMode,'intermediate')
                [rows, diagnostic] = NMResultsViewerTools.modelFeatureInspectionComponentRowsFromReportStruct( ...
                    R.components, ownerContextId, NaN, NaN, '', maxComponents);
                return;
            end

            raw = R.components;
            modalityMap = double(R.components_idxs(:));
            blocks = cell(1,numel(modalityMap)); nBlocks = 0;
            for kk = 1:numel(modalityMap)
                modalityIndex = modalityMap(kk);
                hit = find([physicalContexts.visRowIndex] == modalityIndex, 1, 'first');
                if isempty(hit)
                    diagnostic = NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', 'fusion_report.components', ...
                        sprintf('Intermediate component modality %d does not map to a physical VIS context.', modalityIndex), ...
                        'Report.components_idxs', ownerContextId, '', '', '');
                    rows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,0);
                    return;
                end
                % report_final records every active DR modality in components_idxs,
                % but skips R.components{modalityIndex} when that modality has no Cmag data.
                % nm2-allow: nk_VisXHelperC report_final retains components_idxs but skips R.components{modalityIndex} when Cmag is empty.
                if modalityIndex > numel(raw) || isempty(raw{modalityIndex}), continue; end
                [nextRows, nextDiagnostic] = NMResultsViewerTools.modelFeatureInspectionComponentRowsFromReportStruct( ...
                    raw{modalityIndex}, physicalContexts(hit).contextId, kk, modalityIndex, ...
                    physicalContexts(hit).selectionLabel, maxComponents);
                if ~isempty(nextDiagnostic)
                    diagnostic = nextDiagnostic;
                    rows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,0);
                    return;
                end
                if ~isempty(nextRows), nBlocks = nBlocks + 1; blocks{nBlocks} = nextRows; end
            end
            if nBlocks > 0, rows = [blocks{1:nBlocks}]; end
        end

        function [rows, diagnostic] = modelFeatureInspectionComponentRowsFromReportStruct(C, contextId, drSourceIndex, drSourceModalityIndex, drSourceLabel, maxComponents)
            % modelFeatureInspectionComponentRowsFromReportStruct  Project one writer-defined component report.
            rows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,0);
            diagnostic = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);

            names = C.names(:);
            med = double(C.median_share(:));
            meanV = double(C.mean_share(:));
            meanR = double(C.mean_r_cv2(:));
            rLo = double(C.mean_r_lo95(:));
            rHi = double(C.mean_r_hi95(:));
            meanP = double(C.mean_p_cv2(:));
            pRawLo = double(C.mean_p_lo95(:));
            pRawHi = double(C.mean_p_hi95(:));
            present = double(C.present_cv2(:));
            denom = double(C.denom_cv2(:));
            coverage = double(C.coverage_cv1);
            nAll = numel(names);

            vectorLengths = [numel(med) numel(meanV) numel(meanR) numel(rLo) numel(rHi) ...
                numel(meanP) numel(pRawLo) numel(pRawHi) numel(present) numel(denom)];
            % nm2-allow: nk_VisXHelperC report_final defines one shared component axis; reject corrupted persisted Report arrays.
            if any(vectorLengths ~= nAll) || ~isequal(size(coverage), [nAll 2])
                diagnostic = NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', 'fusion_report.components', ...
                    'Report.components arrays do not share the writer-defined component axis.', ...
                    'Report.components', contextId, '', '', '');
                return;
            end

            % nk_VisXHelperC report_final stores mean_p_cv2 in -log10(P)
            % display space, but stores the two percentile bounds on the raw-P
            % scale. Transform and reverse those bounds deterministically.
            pLo = -log10(pRawHi);
            pHi = -log10(pRawLo);

            n = min(nAll, maxComponents);
            rows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(), 1, n);
            for ii = 1:n
                rows(ii).contextId = contextId;
                rows(ii).drSourceIndex = drSourceIndex;
                rows(ii).drSourceModalityIndex = drSourceModalityIndex;
                rows(ii).drSourceLabel = drSourceLabel;
                rows(ii).componentIndex = ii;
                rows(ii).componentLabel = names{ii};
                rows(ii).kept = true;
                rows(ii).medianL2Share = med(ii);
                rows(ii).meanL2Share = meanV(ii);
                rows(ii).meanReferenceCorrelation = meanR(ii);
                rows(ii).referenceCorrelationLo95 = rLo(ii);
                rows(ii).referenceCorrelationHi95 = rHi(ii);
                rows(ii).meanPermutationLogP = meanP(ii);
                rows(ii).permutationLogPLo95 = pLo(ii);
                rows(ii).permutationLogPHi95 = pHi(ii);
                rows(ii).presencePercent = 100 * present(ii) / max(1, denom(ii));
                rows(ii).selectionRatio = present(ii) / max(1, denom(ii));
                rows(ii).coverageN = coverage(ii,1);
                rows(ii).coverageTotal = coverage(ii,2);
                rows(ii).sourceFields = {'Report.components'};
            end
        end

        function [rows, diagnostic] = modelFeatureInspectionNormalizeComponentModalityShares(R, ownerContextId)
            % modelFeatureInspectionNormalizeComponentModalityShares  Project non-intermediate Report.comp_by_mod.
            rows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentModalityTemplate(),1,0);
            diagnostic = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            C = R.comp_by_mod;
            if isempty(C.median_share), return; end

            compNames = C.names_comp(:);
            modNames = C.names_mod(:);
            med = double(C.median_share);
            meanM = double(C.mean_share);
            % nm2-allow: nk_VisXHelperC report_final defines fixed component-by-modality axes; reject corrupted persisted Report arrays.
            if ndims(med) ~= 2 || size(med,1) ~= numel(compNames) || size(med,2) ~= numel(modNames) || ~isequal(size(meanM), size(med))
                diagnostic = NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning', 'fusion_report.comp_by_mod', ...
                    'Report.comp_by_mod arrays do not share the writer-defined component-by-modality axes.', ...
                    'Report.comp_by_mod', ownerContextId, '', '', '');
                return;
            end

            rows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentModalityTemplate(), 1, numel(med));
            rr = 0;
            for ii = 1:numel(compNames)
                for jj = 1:numel(modNames)
                    rr = rr + 1;
                    rows(rr).contextId = ownerContextId;
                    rows(rr).componentIndex = ii;
                    rows(rr).componentLabel = compNames{ii};
                    rows(rr).modalityIndex = jj;
                    rows(rr).modalityLabel = modNames{jj};
                    rows(rr).medianShare = med(ii,jj);
                    rows(rr).meanShare = meanM(ii,jj);
                    rows(rr).sourceField = 'Report.comp_by_mod';
                end
            end
        end

        function [rows, diagnostics] = modelFeatureInspectionComponentRows(v, ctx, maxComponents)
            % modelFeatureInspectionComponentRows  Project writer-defined component-wise VIS statistics.
            rows = repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,0);
            diagnostics = repmat(NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate(),1,0);
            % nm2-allow: nk_VisModelsC writes this family only for component-wise visualization output.
            if ~isfield(v,'CorrRef_CV2') || isempty(v.CorrRef_CV2), return; end

            classIndex=ctx.classIndex;
            corrMat=double(v.CorrRef_CV2{classIndex});
            pvalMat=double(v.PermPValRef_CV2{classIndex});
            kept=double(v.CompKept{classIndex}(:));
            sel=double(v.CompSelRat{classIndex}(:));
            shareRaw=double(v.ModComp_L2nShare{classIndex});
            nAll=numel(kept);
            if nAll==0, return; end

            diagTemplate=NMResultsViewerTools.modelFeatureInspectionDiagnosticTemplate();
            diagBuffer=repmat(diagTemplate,1,8); diagCount=0;
            corrOk=true; pvalOk=true; selOk=true; shareRawOk=true;
            if any(~ismember(kept,[0 1]))
                diagCount=diagCount+1;
                diagBuffer(diagCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_statistics', ...
                    'CompKept must contain only 0/1 values; component rows were not materialized.', ...
                    'CompKept',ctx.contextId,'modelFeatureInspectionComponentRows','','');
                diagnostics=diagBuffer(1:diagCount); return;
            end
            retainedIndices=find(kept~=0);
            nRetained=numel(retainedIndices);
            if nRetained==0, return; end
            % nm2-allow: nk_VisXHelperC prune_final compacts CorrRef_CV2 to find(CompKept) order.
            if size(corrMat,1)~=nRetained
                corrOk=false; corrMat=[]; diagCount=diagCount+1;
                diagBuffer(diagCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_statistics', ...
                    'CorrRef_CV2 does not share the writer-defined retained component axis and was excluded.', ...
                    'CorrRef_CV2',ctx.contextId,'modelFeatureInspectionComponentRows','','');
            end
            % nm2-allow: nk_VisXHelperC prune_final compacts PermPValRef_CV2 to find(CompKept) order.
            if size(pvalMat,1)~=nRetained
                pvalOk=false; pvalMat=[]; diagCount=diagCount+1;
                diagBuffer(diagCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_statistics', ...
                    'PermPValRef_CV2 does not share the writer-defined retained component axis and was excluded.', ...
                    'PermPValRef_CV2',ctx.contextId,'modelFeatureInspectionComponentRows','','');
            end
            % nm2-allow: nk_VisModelsC writes CompSelRat on the same pre-pruning reference axis as CompKept.
            if numel(sel)~=nAll
                selOk=false; sel=[]; diagCount=diagCount+1;
                diagBuffer(diagCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_statistics', ...
                    'CompSelRat does not share the writer-defined reference component axis and was excluded.', ...
                    'CompSelRat',ctx.contextId,'modelFeatureInspectionComponentRows','','');
            end
            % nm2-allow: nk_VisXHelperC prune_final compacts ModComp_L2nShare to find(CompKept) order.
            if ~isempty(shareRaw) && size(shareRaw,1)~=nRetained
                shareRawOk=false; shareRaw=[]; diagCount=diagCount+1;
                diagBuffer(diagCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_statistics', ...
                    'ModComp_L2nShare does not share the writer-defined retained component axis and was excluded.', ...
                    'ModComp_L2nShare',ctx.contextId,'modelFeatureInspectionComponentRows','','');
            end
            [medianShare,meanShare,loShare,hiShare,coverageShare] = ...
                NMResultsViewerTools.modelFeatureInspectionDirectComponentShares(shareRaw,shareRawOk,nRetained);

            finiteCorr=corrMat(isfinite(corrMat));
            if corrOk && ~isempty(finiteCorr) && any(abs(finiteCorr)>1+1e-12)
                corrOk=false; corrMat=[]; diagCount=diagCount+1;
                diagBuffer(diagCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_statistics', ...
                    'CorrRef_CV2 contains finite values outside [-1,1] and was excluded.', ...
                    'CorrRef_CV2',ctx.contextId,'modelFeatureInspectionComponentRows','','');
            end
            finiteP=pvalMat(isfinite(pvalMat));
            if pvalOk && ~isempty(finiteP) && any(finiteP<0 | finiteP>1)
                pvalOk=false; pvalMat=[]; diagCount=diagCount+1;
                diagBuffer(diagCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_statistics', ...
                    'PermPValRef_CV2 contains finite values outside [0,1] and was excluded.', ...
                    'PermPValRef_CV2',ctx.contextId,'modelFeatureInspectionComponentRows','','');
            end
            finiteSel=sel(isfinite(sel));
            if selOk && ~isempty(finiteSel) && any(finiteSel<0 | finiteSel>1)
                selOk=false; sel=[]; diagCount=diagCount+1;
                diagBuffer(diagCount)=NMResultsViewerTools.modelFeatureInspectionDiagnostic('warning','component_statistics', ...
                    'CompSelRat contains finite values outside [0,1] and was excluded.', ...
                    'CompSelRat',ctx.contextId,'modelFeatureInspectionComponentRows','','');
            end

            observedExpected=nan(nRetained,1); adjustedExcess=nan(nRetained,1); presenceZ=nan(nRetained,1); rawPresence=nan(nRetained,1);
            if corrOk
                [observedExpected,adjustedExcess,presenceZ,rawPresence]=NMResultsViewerTools.modelFeatureInspectionAdjustedComponentPresence(corrMat);
            end
            n=min(nRetained,max(1,round(double(maxComponents))));
            rows=repmat(NMResultsViewerTools.modelFeatureInspectionComponentRowTemplate(),1,n);
            sourceFields={'CorrRef_CV2','PermPValRef_CV2','CompKept'};
            if selOk, sourceFields{end+1}='CompSelRat'; end
            if shareRawOk && ~isempty(shareRaw), sourceFields{end+1}='ModComp_L2nShare'; end
            for ii=1:n
                originalComponentIndex=retainedIndices(ii);
                rows(ii).contextId=ctx.contextId;
                rows(ii).componentIndex=originalComponentIndex;
                rows(ii).componentLabel=sprintf('Component %d',originalComponentIndex);
                rows(ii).kept=true;
                if selOk, rows(ii).selectionRatio=sel(originalComponentIndex); end
                rows(ii).observedExpectedPresenceRatio=observedExpected(ii);
                rows(ii).adjustedExcessPresencePercent=adjustedExcess(ii);
                rows(ii).presenceZScore=presenceZ(ii);
                rows(ii).rawPresencePercent=rawPresence(ii);
                rows(ii).presencePercent=rawPresence(ii);
                if corrOk, rows(ii).meanReferenceCorrelation=NMResultsViewerTools.modelFeatureInspectionFiniteMean(corrMat(ii,:)); end
                if pvalOk
                    meanP=NMResultsViewerTools.modelFeatureInspectionFiniteMean(pvalMat(ii,:));
                    if isfinite(meanP) && meanP>=0 && meanP<=1
                        rows(ii).meanPermutationLogP=-log10(max(realmin('double'),meanP));
                    end
                end
                if shareRawOk && ~isempty(shareRaw)
                    rows(ii).medianL2Share=medianShare(ii); rows(ii).meanL2Share=meanShare(ii);
                    rows(ii).l2ShareLo95=loShare(ii); rows(ii).l2ShareHi95=hiShare(ii);
                    rows(ii).coverageN=coverageShare(ii); rows(ii).coverageTotal=size(shareRaw,2);
                end
                if rows(ii).kept, rows(ii).barState='active'; rows(ii).labelState='active'; else, rows(ii).barState='inactive'; rows(ii).labelState='inactive'; end
                rows(ii).sourceFields=sourceFields;
            end
            diagnostics=diagBuffer(1:diagCount);
        end

        function [medianShare,meanShare,loShare,hiShare,coverage] = modelFeatureInspectionDirectComponentShares(raw,rawOk,nExpected)
            % modelFeatureInspectionDirectComponentShares  Derive component L2-share statistics from the persisted raw share matrix.
            medianShare=nan(nExpected,1); meanShare=nan(nExpected,1); loShare=nan(nExpected,1); hiShare=nan(nExpected,1); coverage=nan(nExpected,1);
            if ~rawOk || isempty(raw), return; end
            raw=double(raw); raw(~isfinite(raw))=NaN;
            medianShare=nm_nanquantile(raw,0.50,2);
            loShare=nm_nanquantile(raw,0.025,2);
            hiShare=nm_nanquantile(raw,0.975,2);
            coverage=sum(isfinite(raw),2);
            meanShare=mean(raw,2,'omitnan');
        end

        function [ratio,excessPct,zScore,rawPct] = modelFeatureInspectionAdjustedComponentPresence(corrMat)
            % modelFeatureInspectionAdjustedComponentPresence  Reproduce propensity-adjusted component presence.
            [nComp,T]=size(corrMat); H=isfinite(corrMat); entry=nan(nComp,1);
            for ii=1:nComp, jj=find(H(ii,:),1,'first'); if ~isempty(jj), entry(ii)=jj; end, end
            propensity=nan(1,T);
            for tt=1:T
                eligible=isfinite(entry) & entry<=tt;
                if any(eligible), propensity(tt)=mean(H(eligible,tt)); end
            end
            ratio=nan(nComp,1); excessPct=nan(nComp,1); zScore=nan(nComp,1); rawPct=nan(nComp,1);
            for ii=1:nComp
                if ~isfinite(entry(ii)), continue; end
                range=entry(ii):T; observed=sum(H(ii,range)); exposures=numel(range);
                p=propensity(range); p=p(isfinite(p)); expected=sum(p); variance=sum(p.*(1-p));
                ratio(ii)=observed/max(expected,eps); excessPct(ii)=100*(observed-expected)/max(1,exposures); rawPct(ii)=100*observed/max(1,exposures);
                if variance>0, zScore(ii)=(observed-expected)/sqrt(variance); end
            end
        end

        function m = modelFeatureInspectionFiniteMean(x)
            % modelFeatureInspectionFiniteMean  Mean of finite values without toolbox dependencies.
            x=double(x(:)); x=x(isfinite(x)); if isempty(x), m=NaN; else, m=mean(x); end
        end

        function payload = emptyPayload(kind)
            % Purpose: Create the fixed empty Results Viewer payload schema for a result family.
            % Syntax: payload = NMResultsViewerTools.emptyPayload(kind)
            % Inputs: kind is the canonical payload family identifier.
            % Outputs: payload is an unavailable fixed-schema payload including empty performanceTabulationRows.
            % Authority and flow: Schema initialization only; domain materializers populate scientific values later.
            % Scientific/state contract: Empty tabulation rows use the same machine-readable schema consumed by Cross-analysis and Report Builder.
            % Invariants: Unavailable payloads never contain fabricated performance values.
            % Materialization and performance: Constant-size metadata allocation; no NM traversal, files/resources, scans, or feature-scale arrays.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond the compact in-memory result/metric data described above; safe on the documented interactive Model Performance/selector path.
            % Failure semantics: None.
            % Side effects: None.
            % Consumers and dependencies: Model Performance/other payload materializers and error/unavailable paths.
            payload = struct('ok',false, 'kind',kind, 'analysisIndex',0, 'classifierIndex',1, 'targetIndex',1, ...
                'title','', 'subtitle','', 'message','', 'summaryRows',[], 'performanceTabulationRows',NMPerformanceMetricTools.emptyRows(), 'scoreRows',[], ...
                'classPlot',struct('ok',false,'points',[],'message',''), ...
                'regressionPlot',struct('ok',false,'points',[],'message',''), ...
                'multiClassPlot',struct('ok',false,'points',[],'predictedPoints',[],'message',''), ...
                'binarization',struct('ok',false,'value',NaN,'message',''), ...
                'roc',struct('ok',false,'points',[],'auc',NaN,'message',''), ...
                'confusion',struct('ok',false,'matrix',[],'percentMatrix',[],'labels',{{}},'message',''), ...
                'pies',struct('ok',false,'charts',[],'message',''), ...
                'modelPermutation',NMResultsViewerTools.modelPerformancePermutationPayloadTemplate(), ...
                'cobweb',struct('ok',false,'axes',[],'series',[],'tmr',NaN,'message',''), ...
                'subjectQCScalars',NMResultsViewerTools.emptySubjectQCScalarPayload(), ...
                'unsupportedPanels',{{}});
        end

        function GD = primaryGDdims(A)
            GD = [];
            % nm2-allow: nk_MLOptimizerPrep conditionally persists the GDdims family.
            if ~isstruct(A) || ~isfield(A,'GDdims') || isempty(A.GDdims), return; end
            for i = 1:numel(A.GDdims)
                % nm2-allow: optimizer modality slots may be unpopulated before completed result materialization.
                if isstruct(A.GDdims{i}) && ~isempty(A.GDdims{i})
                    GD = A.GDdims{i}; return;
                end
            end
        end

        function C = classParamStruct(A, clsIdx)
            C = [];
            % nk_InitAnalysisPrep snapshots cv; nk_MakeCrossFolds produces cv.class{i,j}.
            % The first outer CV fold owns the displayed classifier description.
            % nm2-allow: nk_MakeCrossFolds writes cv.class only for classifier decomposition; regression snapshots legitimately omit it.
            if ~isfield(A.params.cv,'class') || isempty(A.params.cv.class), return; end
            classes = A.params.cv.class{1};
            % nm2-allow: nk_GenClass returns classifier cells for OvO/OvA and a scalar struct for its multi-group branch.
            if iscell(classes)
                if clsIdx <= numel(classes), C = classes{clsIdx}; end
            % nm2-allow: nk_GenClass emits a scalar struct under the multi-group decomposition branch.
            elseif isstruct(classes)
                if clsIdx <= numel(classes), C = classes(clsIdx); end
            end
        end

        function txt = classifierLabel(A, clsIdx)
            txt = sprintf('Binary classifier %d', clsIdx);
            C = NMResultsViewerTools.classParamStruct(A, clsIdx);
            if isstruct(C) && isfield(C,'groupdesc') && ~isempty(C.groupdesc)
                txt = char(string(C.groupdesc));
            end
        end

        function kind = normalizeResultType(resultType)
            % normalizeResultType  Normalize public Results Viewer result-type aliases at the request boundary.
            % nm2-allow: public browser/API request boundary accepts documented historical result-type aliases.
            txt=lower(strtrim(char(string(resultType))));
            switch txt
                case {'regression','regr'}
                    kind='regression';
                case {'multiclass','multi_class','multi-class','multiclass_classification'}
                    kind='multiclass';
                case {'model_optimization','modeloptimization','optimization','model_performance'}
                    kind='model_optimization';
                case {'model_feature_inspection','model_featureinspection','feature_inspection','featureinspection','model_visualization','modelvisualization','visualization'} % nm2-allow: public request boundary retains established Feature Inspection aliases.
                    kind='model_feature_inspection';
                case {'mli','ml_interpretation','machine_learning_interpretation','machinelearninginterpretation'}
                    kind='mli';
                case {'comparison','comparisons','cross_analysis','cross-analysis','crossanalysis','model_comparisons'} % nm2-allow: public request boundary retains established Cross-analysis aliases.
                    kind='comparison';
                case {'classification','class'}
                    kind='classification';
                otherwise
                    error('NMResultsViewerTools:UnknownResultType','Unknown Results Viewer result type: %s.',txt);
            end
        end

        function resultType = selectedResultType(types,spec)
            requested=spec.resultType;
            if ~isempty(requested)
                requestedKind=NMResultsViewerTools.normalizeResultType(requested);
                hit=find(strcmp({types.id},requestedKind)&[types.enabled],1,'first');
                if isempty(hit),error('NMResultsViewerTools:InvalidResultTypeSelection','Result type %s is not enabled for the selected analysis.',requestedKind);end
                resultType=types(hit).id;return;
            end
            hit=find([types.enabled],1,'first');
            if isempty(hit),resultType='classification';else,resultType=types(hit).id;end
        end

        function idx = selectedMultiClassModeIndex(modes, spec)
            idx = 1;
            % nm2-allow: canonical mode catalogue owns selector applicability; generic non-multiclass browser state may carry an irrelevant hidden multiClassModeIndex.
            if ~any([modes.enabled]), return; end
            % nm2-allow: public Results Viewer selector boundary distinguishes omitted multiClassModeIndex from an explicit request
            if isfield(spec,'multiClassModeIndex')
                idx = double(spec.multiClassModeIndex);
                % nm2-allow: public multi-class selector validates the explicit requested coordinate against the canonical enabled mode catalogue
                if ~isscalar(idx) || ~isfinite(idx) || idx ~= round(idx) || idx < 1 || idx > numel(modes) || ~modes(idx).enabled
                    error('NMResultsViewerTools:InvalidMultiClassModeIndex', ...
                        'Requested multiClassModeIndex must identify one enabled canonical multi-class mode.');
                end
            end
        end

        function labels = optionLabels(opts)
            labels = cell(1,numel(opts));
            for ii = 1:numel(opts), labels{ii} = char(string(opts(ii).label)); end
        end

        function names = groupNamesForAnalysis(NM, idx)
            A = NM.analysis{idx};
            if strcmp(A.params.label.modeflag,'regression')
                names = {};
            elseif logical(A.params.label.altlabelflag)
                names = A.params.label.altgroupnames(:)';
            else
                names = NM.groupnames(:)';
            end
        end

        function list = legacyPopupStrings(NM, A, GD, resultType) %#ok<INUSD>
            kind = NMResultsViewerTools.normalizeResultType(resultType);
            switch kind
                case 'regression'
                    list = {'Regression model'};
                case 'multiclass'
                    nBin = numel(GD.BinClass);
                    list = cell(1,nBin+1);
                    for ii = 1:nBin
                        list{ii} = sprintf('Classifier %g: %s', ii, NMResultsViewerTools.classifierLabel(A, ii));
                    end
                    list{end} = 'Multi-group classifier';
                otherwise
                    nBin = numel(GD.BinClass);
                    % nm2-allow: nk_MLOptimizer conditionally writes GD.MultiClass only when multi-group output is produced
                    hasMulti = isfield(GD,'MultiClass') && ~isempty(GD.MultiClass);
                    list = cell(1,nBin + double(hasMulti));
                    for ii = 1:nBin
                        list{ii} = sprintf('Classifier %g: %s', ii, NMResultsViewerTools.classifierLabel(A, ii));
                    end
                    if hasMulti, list{end} = 'Multi-group classifier'; end
            end
        end

        function val = legacyPopupValue(GD, resultType, requested)
            kind = NMResultsViewerTools.normalizeResultType(resultType);
            switch kind
                case 'regression'
                    val = 1;
                case 'multiclass'
                    val = numel(GD.BinClass) + 1;
                otherwise
                    nBin = numel(GD.BinClass);
                    % nm2-allow: nk_MLOptimizer conditionally writes GD.MultiClass only when multi-group output is produced
                    hasMulti = isfield(GD,'MultiClass') && ~isempty(GD.MultiClass);
                    maxVal = nBin + double(hasMulti);
                    val = round(double(requested));
                    if ~isscalar(val) || ~isfinite(val) || val < 1 || val > maxVal
                        error('NMResultsViewerTools:InvalidClassifierIndex', 'Classifier index must address the selected completed result family.');
                    end
            end
        end

        function tf = isMultiGroupClassifierRequest(NM, spec, idx)
            if nargin < 3 || isempty(idx)
                idx = spec.analysisIndex;
            end
            tf = false;
            if isnan(idx) || idx < 1 || ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || idx > numel(NM.analysis)
                return;
            end
            [~, GD] = NMResultsViewerTools.resultGDForSpec(NM, idx, 'classification', spec);
            if ~isstruct(GD) || ~isfield(GD,'MultiClass') || isempty(GD.MultiClass)
                return;
            end
            nBin = 0;
            if isfield(GD,'BinClass') && ~isempty(GD.BinClass)
                nBin = numel(GD.BinClass);
            end
            clsIdx = spec.classifierIndex;
            if isnan(clsIdx), clsIdx = 1; end
            tf = round(double(clsIdx)) == nBin + 1;
        end

        function txt = initialMessage(state)
            if ~state.canInspect
                txt = 'Complete at least one analysis before using the alpha Results Viewer.';
            else
                txt = 'Alpha Results Viewer ready. Legacy viewer remains available from the workbench and from this page.';
            end
        end

        function txt = analysisId(A, idx)
            txt = sprintf('%d', idx);
            if isstruct(A) && isfield(A,'id') && ~isempty(A.id), txt = char(string(A.id)); end
        end

        function txt = analysisTitle(A, idx)
            txt = sprintf('Analysis %d', idx);
            if isstruct(A)
                if isfield(A,'description') && ~isempty(A.description), txt = char(string(A.description));
                elseif isfield(A,'id') && ~isempty(A.id), txt = sprintf('Analysis %d - %s', idx, char(string(A.id))); end
            end
        end

        function v = statusValue(A)
            v = NaN;
            if isstruct(A) && isfield(A,'status') && ~isempty(A.status)
                x = double(A.status(:)); if ~isempty(x), v = x(1); end
            end
        end

        function txt = statusLabel(status)
            if isnan(status), txt = 'unknown'; elseif status >= 1, txt = 'completed'; elseif status == 0, txt = 'configured'; else, txt = sprintf('status %.3g', status); end
        end

        function txt = analysisSummary(A, GD)
            bits = {};
            if isstruct(GD)
                if isfield(GD,'BinClass'), bits{end+1} = sprintf('%d binary classifier(s)', numel(GD.BinClass)); end %#ok<AGROW>
                if isfield(GD,'MultiClass'), bits{end+1} = 'multi-class results'; end %#ok<AGROW>
                if isfield(GD,'Regr'), bits{end+1} = 'regression results'; end %#ok<AGROW>
            end
            if isstruct(A) && isfield(A,'visdata') && ~isempty(A.visdata), bits{end+1} = 'VIS'; end %#ok<AGROW>
            if isstruct(A) && isfield(A,'MLI') && ~isempty(A.MLI), bits{end+1} = 'MLI'; end %#ok<AGROW> % nm2-allow: nk_MLInterpreterPrep conditionally persists analysis.MLI for completed CV interpretation.
            if isempty(bits), txt = 'No browser-readable result payload detected.'; else, txt = strjoin(bits, ', '); end
        end

        function tf = hasAllFields(s, fields)
            tf = isstruct(s);
            if ~tf, return; end
            for i=1:numel(fields)
                if ~isfield(s, fields{i}), tf = false; return; end
            end
        end

        function vals = scalarFieldsAt(s, fields, idx)
            vals = nan(1,numel(fields));
            for i=1:numel(fields)
                if ~isstruct(s) || ~isfield(s, fields{i}), continue; end
                v = double(s.(fields{i}));
                if isempty(v), continue; end
                if numel(v) >= idx, vals(i) = v(idx); else, vals(i) = v(1); end
            end
        end

        function x = asColumnDouble(v)
            if isempty(v), x = []; return; end
            try
                x = double(v(:));
            catch
                x = str2double(cellstr(string(v(:))));
            end
        end

        function x = padNumericColumn(x, n, fillValue)

            if isempty(x), x = repmat(fillValue, n, 1); return; end
            x = double(x(:));
            if numel(x) < n, x(end+1:n,1) = fillValue; end %#ok<AGROW>
            if numel(x) > n, x = x(1:n); end
        end


        function [nCases, sourceLabel] = plotVectorCaseCount(NM, spec)
            source = spec.source;
            [isOOCVSource, oocvIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            if isOOCVSource
                % nm2-allow: public source selector boundary validates the requested global OOCV container index
            if oocvIndex < 1 || oocvIndex > numel(NM.OOCV)
                    error('NMResultsViewerTools:InvalidPlotVectorOOCVSource', ...
                        'OOCV vector source %s does not address a committed NM.OOCV container.',source);
                end
                sourceLabel = sprintf('OOCV container %d cases', oocvIndex);
                nCases = numel(NM.OOCV{oocvIndex}.cases);
                return;
            end
            if ~strcmp(source,'cv')
                error('NMResultsViewerTools:InvalidPlotVectorSource', ...
                    'Vector controls support source cv or a canonical oocv:<index> source, not "%s".',source);
            end
            sourceLabel = 'training/CV cases';
            nCases = numel(NM.cases);
        end

        function opts = emptyPlotVectorOptions()
            tmpl = NMResultsViewerTools.plotVectorOptionTemplate();
            opts = repmat(tmpl, 1, 0);
        end

        function tmpl = plotVectorOptionTemplate()
            tmpl = struct('id','', 'label','', 'expression','', 'source','', 'type','', 'enabled',true, 'reason','');
        end

        function W = plotVectorWorkspaceCatalogue()
            % plotVectorWorkspaceCatalogue  External base-workspace catalogue boundary.
            W = evalin('base', 'whos');
        end

        function opts = plotVectorCandidateOptions(NM, nCases, role, spec, workspaceCatalogue)
            labels = {}; exprs = {}; sources = {}; types = {}; reasons = {}; enabled = [];
            source = spec.source;
            [isOOCVSource, oocvIndex] = NMResultsViewerTools.parseOOCVSourceId(source);

            if isOOCVSource
                [labels, exprs, sources, types, reasons, enabled] = NMResultsViewerTools.appendOOCVContainerVectorOptions(NM, oocvIndex, nCases, labels, exprs, sources, types, reasons, enabled);
            else
                [labels, exprs, sources, types, reasons, enabled] = NMResultsViewerTools.appendTrainingVectorOptions(NM, nCases, labels, exprs, sources, types, reasons, enabled);
            end

            [labels, exprs, sources, types, reasons, enabled] = NMResultsViewerTools.appendQCScalarVectorOptions(NM, spec, nCases, labels, exprs, sources, types, reasons, enabled);
            if strcmp(role,'subgroup')
                [labels, exprs, sources, types, reasons, enabled] = NMResultsViewerTools.appendSubgroupExpressionOptions(NM, spec, nCases, labels, exprs, sources, types, reasons, enabled);
            end

            W = workspaceCatalogue;
            for ii = 1:numel(W)
                cls = W(ii).class;
                sz = W(ii).size;
                % nm2-allow: external workspace catalogue boundary admits only one-dimensional numeric or logical case vectors
                if numel(sz) == 2 && any(sz == nCases) && any(sz == 1) && ismember(cls, {'double','single','logical','uint8','uint16','uint32','uint64','int8','int16','int32','int64'})
                    nm = W(ii).name;
                    if strcmp(nm,'NM'), continue; end
                    labels{end+1} = sprintf('%s  [%s vector]', nm, cls); %#ok<AGROW>
                    exprs{end+1} = nm; %#ok<AGROW>
                    sources{end+1} = 'MATLAB workspace'; %#ok<AGROW>
                    types{end+1} = cls; %#ok<AGROW>
                    reasons{end+1} = ''; %#ok<AGROW>
                    enabled(end+1) = true; %#ok<AGROW>
                elseif strcmp(cls,'table') && sz(1) == nCases
                    varNames = evalin('base', sprintf('%s.Properties.VariableNames', W(ii).name));
                    for jj = 1:numel(varNames)
                        if ~isvarname(varNames{jj}), continue; end
                        expr = sprintf('%s.%s', W(ii).name, varNames{jj});
                        c = evalin('base', expr);
                        % nm2-allow: external workspace table boundary admits only numeric or logical case-vector columns
                        if (isnumeric(c) || islogical(c)) && isvector(c) && numel(c) == nCases
                            colType = class(c);
                            labels{end+1} = sprintf('%s.%s  [%s table column]', W(ii).name, varNames{jj}, colType); %#ok<AGROW>
                            exprs{end+1} = expr; %#ok<AGROW>
                            sources{end+1} = 'MATLAB workspace table'; %#ok<AGROW>
                            types{end+1} = colType; %#ok<AGROW>
                            reasons{end+1} = ''; %#ok<AGROW>
                            enabled(end+1) = true; %#ok<AGROW>
                        end
                    end
                end
            end
            [exprs, ia] = unique(exprs, 'stable');
            labels = labels(ia); sources = sources(ia); types = types(ia); reasons = reasons(ia); enabled = enabled(ia);
            tmpl = NMResultsViewerTools.plotVectorOptionTemplate();
            opts = repmat(tmpl, 1, numel(exprs));
            for ii = 1:numel(exprs)
                opts(ii) = struct('id',exprs{ii}, 'label',labels{ii}, 'expression',exprs{ii}, ...
                    'source',sources{ii}, 'type',types{ii}, 'enabled',logical(enabled(ii)), 'reason',reasons{ii});
            end
        end

        function [labels, exprs, sources, types, reasons, enabled] = appendTrainingVectorOptions(NM, nCases, labels, exprs, sources, types, reasons, enabled)
            % nm2-allow: DataIO writes NM.covars only when one or more covariates are configured
            if isfield(NM,'covars') && ~isempty(NM.covars)
                % nm2-allow: canonical training covariates must share the committed NM.cases axis
                if size(NM.covars,1) ~= nCases
                    error('NMResultsViewerTools:PlotVectorCovariateAxisMismatch', ...
                        'NM.covars has %d rows but NM.cases has %d entries.',size(NM.covars,1),nCases);
                end
                nCov = size(NM.covars,2);
                covNames = NMResultsViewerTools.plotVectorCovariateNames(NM, nCov);
                for jj = 1:nCov
                    labels{end+1} = NMResultsViewerTools.plotVectorOptionDisplayLabel('Covariate', jj, covNames{jj}); %#ok<AGROW>
                    exprs{end+1} = sprintf('NM.covars(:,%d)', jj); %#ok<AGROW>
                    sources{end+1} = 'NM.covars'; %#ok<AGROW>
                    types{end+1} = 'numeric'; %#ok<AGROW>
                    reasons{end+1} = sprintf('MATLAB expression: NM.covars(:,%d)', jj); %#ok<AGROW>
                    enabled(end+1) = true; %#ok<AGROW>
                end
            end
            % nm2-allow: canonical training labels must share the committed NM.cases axis
            if size(NM.label,1) ~= nCases
                error('NMResultsViewerTools:PlotVectorLabelAxisMismatch', ...
                    'NM.label has %d rows but NM.cases has %d entries.',size(NM.label,1),nCases);
            end
            labelNames = NMResultsViewerTools.plotVectorLabelNamesFromStruct(NM, size(NM.label,2), 'NM label');
            for jj = 1:size(NM.label,2)
                labels{end+1} = NMResultsViewerTools.plotVectorOptionDisplayLabel('NM label', jj, labelNames{jj}); %#ok<AGROW>
                exprs{end+1} = sprintf('NM.label(:,%d)', jj); %#ok<AGROW>
                sources{end+1} = 'NM.label'; %#ok<AGROW>
                types{end+1} = 'numeric'; %#ok<AGROW>
                reasons{end+1} = sprintf('MATLAB expression: NM.label(:,%d)', jj); %#ok<AGROW>
                enabled(end+1) = true; %#ok<AGROW>
            end
        end

        function [labels, exprs, sources, types, reasons, enabled] = appendOOCVContainerVectorOptions(NM, oocvIndex, nCases, labels, exprs, sources, types, reasons, enabled)
            O = NM.OOCV{oocvIndex};
            prefix = sprintf('NM.OOCV{%d}', oocvIndex);
            % nm2-allow: DataIO writes OOCV covars only when covariates are committed for that container
            if isfield(O,'covars') && ~isempty(O.covars)
                % nm2-allow: canonical OOCV covariates must share the committed OOCV case axis
                if size(O.covars,1) ~= nCases
                    error('NMResultsViewerTools:PlotVectorOOCVCovariateAxisMismatch', ...
                        'NM.OOCV{%d}.covars has %d rows but its case axis has %d entries.',oocvIndex,size(O.covars,1),nCases);
                end
                covNames = NMResultsViewerTools.plotVectorCovariateNamesFromStruct(O, size(O.covars,2));
                for jj = 1:size(O.covars,2)
                    labels{end+1} = NMResultsViewerTools.plotVectorOptionDisplayLabel('OOCV covariate', jj, covNames{jj}); %#ok<AGROW>
                    exprs{end+1} = sprintf('%s.covars(:,%d)', prefix, jj); %#ok<AGROW>
                    sources{end+1} = 'NM.OOCV covars'; %#ok<AGROW>
                    types{end+1} = 'numeric'; %#ok<AGROW>
                    reasons{end+1} = sprintf('MATLAB expression: %s.covars(:,%d)', prefix, jj); %#ok<AGROW>
                    enabled(end+1) = true; %#ok<AGROW>
                end
            end
            if logical(O.labels_known)
                % nm2-allow: labels-known OOCV data must share the committed OOCV case axis
                if size(O.label,1) ~= nCases
                    error('NMResultsViewerTools:PlotVectorOOCVLabelAxisMismatch', ...
                        'NM.OOCV{%d}.label has %d rows but its case axis has %d entries.',oocvIndex,size(O.label,1),nCases);
                end
                labelNames = NMResultsViewerTools.plotVectorLabelNamesFromStruct(O, size(O.label,2), 'OOCV label');
                for jj = 1:size(O.label,2)
                    labels{end+1} = NMResultsViewerTools.plotVectorOptionDisplayLabel('OOCV label', jj, labelNames{jj}); %#ok<AGROW>
                    exprs{end+1} = sprintf('%s.label(:,%d)', prefix, jj); %#ok<AGROW>
                    sources{end+1} = 'NM.OOCV label'; %#ok<AGROW>
                    types{end+1} = 'numeric'; %#ok<AGROW>
                    reasons{end+1} = sprintf('MATLAB expression: %s.label(:,%d)', prefix, jj); %#ok<AGROW>
                    enabled(end+1) = true; %#ok<AGROW>
                end
            end
        end

        function covNames = plotVectorCovariateNames(NM, nCov)
            covNames = NMResultsViewerTools.plotVectorCovariateNamesFromStruct(NM, nCov);
        end

        function covNames = plotVectorCovariateNamesFromStruct(S, nCov)
            if numel(S.covnames) ~= nCov
                error('NMResultsViewerTools:PlotVectorCovariateNameAxisMismatch', ...
                    'Canonical covariate names contain %d entries for %d covariate columns.',numel(S.covnames),nCov);
            end
            covNames = S.covnames(:)';
        end

        function label = plotVectorOptionDisplayLabel(prefix, idx, rawName)
            defaultName = sprintf('%s %d', prefix, idx);
            if strcmp(rawName,defaultName)
                label = defaultName;
            else
                label = sprintf('%s: %s', defaultName, rawName);
            end
        end

        function label = plotVectorAxisName(prefix, idx, rawName)
            defaultName = sprintf('%s %d', prefix, idx);
            if strcmp(rawName,defaultName)
                label = defaultName;
            else
                label = rawName;
            end
        end

        function labelNames = plotVectorLabelNamesFromStruct(S, nLab, defaultPrefix)
            labelNames = cell(1,nLab);
            for jj = 1:nLab
                if jj == 1 && strcmp(defaultPrefix,'NM label')
                    labelNames{jj} = 'Primary label';
                else
                    labelNames{jj} = sprintf('%s %d', defaultPrefix, jj);
                end
            end
            % nm2-allow: DataIO writes labelnames for named target axes; classification containers may omit target names
            if ~isfield(S,'labelnames') || isempty(S.labelnames)
                return;
            end
            if numel(S.labelnames) ~= nLab
                error('NMResultsViewerTools:PlotVectorLabelNameAxisMismatch', ...
                    'Canonical labelnames contain %d entries for %d target columns.',numel(S.labelnames),nLab);
            end
            labelNames = S.labelnames(:)';
        end

        function label = plotVectorAxisLabel(NM, expr, nExpected, spec)
            %#ok<INUSD>
            label = expr;
            tok = regexp(expr, '^NM\.covars\(:,\s*(\d+)\)$', 'tokens', 'once');
            if ~isempty(tok)
                idx = str2double(tok{1});
                covNames = NMResultsViewerTools.plotVectorCovariateNames(NM, size(NM.covars,2));
                label = NMResultsViewerTools.plotVectorAxisName('Covariate', idx, covNames{idx});
                return;
            end
            tok = regexp(expr, '^NM\.OOCV\{(\d+)\}\.covars\(:,\s*(\d+)\)$', 'tokens', 'once');
            if ~isempty(tok)
                oi = str2double(tok{1}); ci = str2double(tok{2});
                O = NM.OOCV{oi};
                covNames = NMResultsViewerTools.plotVectorCovariateNamesFromStruct(O, size(O.covars,2));
                label = NMResultsViewerTools.plotVectorAxisName('OOCV covariate', ci, covNames{ci});
                return;
            end
            tok = regexp(expr, '^NM\.label\(:,\s*(\d+)\)$', 'tokens', 'once');
            if ~isempty(tok)
                idx = str2double(tok{1});
                labelNames = NMResultsViewerTools.plotVectorLabelNamesFromStruct(NM, size(NM.label,2), 'NM label');
                label = NMResultsViewerTools.plotVectorAxisName('NM label', idx, labelNames{idx});
                return;
            end
            tok = regexp(expr, '^NM\.OOCV\{(\d+)\}\.label\(:,\s*(\d+)\)$', 'tokens', 'once');
            if ~isempty(tok)
                oi = str2double(tok{1}); li = str2double(tok{2});
                O = NM.OOCV{oi};
                labelNames = NMResultsViewerTools.plotVectorLabelNamesFromStruct(O, size(O.label,2), 'OOCV label');
                label = NMResultsViewerTools.plotVectorAxisName('OOCV label', li, labelNames{li});
                return;
            end
            tok = regexp(expr, '^QC\.([A-Za-z][A-Za-z0-9_]*)$', 'tokens', 'once');
            if ~isempty(tok)
                qcLabel = NMResultsViewerTools.plotVectorQCMetricLabel(NM, spec, tok{1});
                if ~isempty(qcLabel), label = qcLabel; end
                return;
            end
            if strcmp(expr,'label')
                label = 'Primary label';
            end
        end

        function label = plotVectorQCMetricLabel(NM, spec, key)
            label = '';
            qc = NMResultsViewerTools.subjectQCScalarPayload(NM, spec);
            if ~qc.ok, return; end
            for ii = 1:numel(qc.metrics)
                m = qc.metrics(ii);
                if strcmp(m.key,key)
                    label = m.label;
                    return;
                end
            end
        end

        function [labels, exprs, sources, types, reasons, enabled] = appendQCScalarVectorOptions(NM, spec, nCases, labels, exprs, sources, types, reasons, enabled)
            qc = NMResultsViewerTools.subjectQCScalarPayload(NM, spec);
            if ~qc.ok || isempty(qc.metrics), return; end
            % nm2-allow: persisted QC case identity must match the active Results Viewer case axis
            if numel(qc.caseIds) ~= nCases
                error('NMResultsViewerTools:PlotVectorQCCaseAxisMismatch', ...
                    'Subject QC contains %d cases but the active result source contains %d.',numel(qc.caseIds),nCases);
            end
            for ii = 1:numel(qc.metrics)
                m = qc.metrics(ii);
                % nm2-allow: each fixed subject-QC metric must cover the complete QC case axis
                if numel(m.values) ~= nCases
                    error('NMResultsViewerTools:PlotVectorQCMetricAxisMismatch', ...
                        'Subject QC metric %s contains %d values for %d cases.',m.key,numel(m.values),nCases);
                end
                expr = sprintf('QC.%s', m.key);
                labels{end+1} = sprintf('QC: %s', m.label); %#ok<AGROW>
                exprs{end+1} = expr; %#ok<AGROW>
                sources{end+1} = 'DataIO subject QC'; %#ok<AGROW>
                types{end+1} = 'numeric'; %#ok<AGROW>
                reasons{end+1} = sprintf('Subject-level QC metric: %s', expr); %#ok<AGROW>
                enabled(end+1) = true; %#ok<AGROW>
            end
        end

        function [labels, exprs, sources, types, reasons, enabled] = appendSubgroupExpressionOptions(NM, spec, nCases, labels, exprs, sources, types, reasons, enabled)
            source = spec.source;
            [isOOCVSource, oocvIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            if isOOCVSource
                O = NM.OOCV{oocvIndex};
                if ~logical(O.labels_known), return; end
                y = O.label;
            else
                y = NM.label;
            end
            % nm2-allow: subgroup proposals are defined only on the active committed case axis
            if size(y,1) ~= nCases
                error('NMResultsViewerTools:PlotVectorSubgroupLabelAxisMismatch', ...
                    'Subgroup label material contains %d rows for %d active cases.',size(y,1),nCases);
            end
            y = double(y(:,1));
            u = unique(y(isfinite(y)));
            % nm2-allow: subgroup selector presentation bounds generated equality shortcuts to twelve distinct label values
            if isempty(u) || numel(u) > 12, return; end
            for ii = 1:numel(u)
                expr = sprintf('label==%g', u(ii));
                labels{end+1} = sprintf('Label == %g', u(ii)); %#ok<AGROW>
                exprs{end+1} = expr; %#ok<AGROW>
                sources{end+1} = 'label comparison'; %#ok<AGROW>
                types{end+1} = 'logical'; %#ok<AGROW>
                reasons{end+1} = ''; %#ok<AGROW>
                enabled(end+1) = true; %#ok<AGROW>
            end
        end

        function handles = applyPlotVectorSubgroupOverride(handles, NM, viewerOpts)
            if viewerOpts.deferPlotVectorOverrides, return; end
            sExpr = viewerOpts.subgroupExpression;
            if isempty(sExpr), return; end
            n = numel(handles.subjects);
            [g, ok, msg] = NMResultsViewerTools.resolvePlotVectorReference(NM, sExpr, n, 'subgroup', viewerOpts);
            if ~ok
                handles.alphaVectorWarning = msg;
                return;
            end
            fullMask = logical(isfinite(g(:)) & g(:) ~= 0);
            switch viewerOpts.resultType
                case 'classification'
                    B = handles.BinClass{viewerOpts.classifierIndex};
                    resultMask = fullMask(B.ind);
                    handles.SubIndex = resultMask(B.sortind);
                case 'regression'
                    handles.SubIndex = fullMask;
                case 'multiclass'
                    subjectIds = string(handles.subjects(:));
                    caseIds = string(handles.MultiClass.cases(:));
                    [present, rowIndex] = ismember(caseIds, subjectIds);
                    if ~all(present)
                        error('NMResultsViewerTools:PlotVectorCaseIdentityMismatch', ...
                            'The multi-class result case axis is not a subset of the committed training case axis.');
                    end
                    handles.SubIndex = fullMask(rowIndex);
            end
        end

        function handles = applyPlotVectorXAxisOverride(handles, NM, viewerOpts)
            if viewerOpts.deferPlotVectorOverrides, return; end
            xExpr = viewerOpts.xAxisExpression;
            if isempty(xExpr)
                handles.XaxisName = '';
                return;
            end
            n = numel(handles.subjects);
            [x, ok, msg] = NMResultsViewerTools.resolvePlotVectorReference(NM, xExpr, n, 'xaxis', viewerOpts);
            if ~ok
                if isempty(handles.alphaVectorWarning)
                    handles.alphaVectorWarning = msg;
                else
                    handles.alphaVectorWarning = sprintf('%s %s',handles.alphaVectorWarning,msg);
                end
                return;
            end
            axisName = viewerOpts.xAxisLabel;
            if isempty(axisName)
                axisName = NMResultsViewerTools.plotVectorAxisLabel(NM, xExpr, n, viewerOpts);
            end
            handles.XaxisName = axisName;
            switch viewerOpts.resultType
                case 'classification'
                    for kk = 1:numel(handles.BinClass)
                        xClass = x(handles.BinClass{kk}.ind);
                        handles.BinClass{kk}.Xaxis = xClass(handles.BinClass{kk}.sortind);
                    end
                case 'regression'
                    handles.Regr.Xaxis = x;
                case 'multiclass'
                    subjectIds = string(handles.subjects(:));
                    caseIds = string(handles.MultiClass.cases(:));
                    [present, rowIndex] = ismember(caseIds, subjectIds);
                    if ~all(present)
                        error('NMResultsViewerTools:PlotVectorCaseIdentityMismatch', ...
                            'The multi-class result case axis is not a subset of the committed training case axis.');
                    end
                    handles.MultiClass.Xaxis = x(rowIndex);
            end
        end

        function [x, ok, msg] = resolvePlotVectorReference(NM, expr, nExpected, role, spec)
            x = []; ok = false; msg = '';
            expr = strtrim(expr);
            if isempty(expr), ok = true; return; end

            cmp = regexp(expr, '^(.+?)\s*(==|~=|>=|<=|>|<)\s*(-?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?)\s*$', 'tokens', 'once');
            if ~isempty(cmp)
                [base, okBase, msgBase] = NMResultsViewerTools.resolvePlotVectorReference(NM, strtrim(cmp{1}), nExpected, role, spec);
                if ~okBase
                    msg = msgBase;
                    return;
                end
                rhs = str2double(cmp{3});
                switch cmp{2}
                    case '=='
                        x = double(base == rhs);
                    case '~='
                        x = double(base ~= rhs);
                    case '>='
                        x = double(base >= rhs);
                    case '<='
                        x = double(base <= rhs);
                    case '>'
                        x = double(base > rhs);
                    case '<'
                        x = double(base < rhs);
                end
                ok = true;
                return;
            end

            if strcmp(expr,'label')
                source = spec.source;
                [isOOCVSource, oocvIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
                if isOOCVSource
                    O = NM.OOCV{oocvIndex};
                    if ~logical(O.labels_known)
                        msg = sprintf('The OOCV source %s has no known labels.',source);
                        return;
                    end
                    val = O.label(:,1);
                else
                    val = NM.label(:,1);
                end
            elseif strncmp(expr,'QC.',3)
                [val, okQC, msgQC] = NMResultsViewerTools.resolvePlotVectorQCMetric(NM, spec, expr, nExpected);
                if ~okQC, msg = msgQC; return; end
            else
                % External MATLAB-reference boundary: accept one simple variable/path/index expression.
                if isempty(regexp(expr, '^[A-Za-z][A-Za-z0-9_]*(\{\d+\})?(\.[A-Za-z][A-Za-z0-9_]*(\{\d+\})?)*(\([0-9: ,]+\))?$', 'once'))
                    msg = sprintf('The %s reference "%s" is not a supported vector reference. Use a workspace vector, a table column, an NM field such as NM.covars(:,1), or a comparison such as label==1.', role, expr);
                    return;
                end
                % nm2-allow: explicit user MATLAB reference is resolved only at this bounded external-expression boundary
                try
                    if strncmp(expr, 'NM.', 3) || strcmp(expr, 'NM')
                        val = eval(expr); %#ok<EVLDOT>
                    else
                        val = evalin('base', expr);
                    end
                % nm2-allow: external MATLAB reference errors are converted into visible selector diagnostics
                catch ME
                    msg = sprintf('The %s reference "%s" could not be resolved: %s', role, expr, ME.message);
                    return;
                end
            end
            % nm2-allow: external vector-reference boundary validates numeric/logical vector type and active-case length
            if ~(isnumeric(val) || islogical(val)) || ~isvector(val) || numel(val) ~= nExpected
                msg = sprintf('The %s reference "%s" must resolve to a numeric/logical vector with %d entries.', role, expr, nExpected);
                return;
            end
            x = double(val(:));
            ok = true;
        end

        function [val, ok, msg] = resolvePlotVectorQCMetric(NM, spec, expr, nExpected)
            tok = regexp(expr, '^QC\.([A-Za-z][A-Za-z0-9_]*)$', 'tokens', 'once');
            if isempty(tok)
                val = []; ok = false; msg = sprintf('Invalid QC vector reference "%s".',expr);
                return;
            end
            [val, ok, msg] = NMResultsViewerTools.resolvePlotVectorQCMetricValue(NM, spec, tok{1}, nExpected);
        end

        function [val, ok, msg] = resolvePlotVectorQCMetricValue(NM, spec, key, nExpected)
            val = []; ok = false; msg = '';
            qc = NMResultsViewerTools.subjectQCScalarPayload(NM, spec);
            if ~qc.ok
                msg = qc.message;
                return;
            end
            for ii = 1:numel(qc.metrics)
                m = qc.metrics(ii);
                if strcmp(m.key,key)
                    val = cellfun(@double,m.values(:));
                    % nm2-allow: fixed subject-QC metric vectors must match the active Results Viewer case axis
                    if numel(val) ~= nExpected
                        msg = sprintf('The QC metric "%s" has %d entries, but the current plot expects %d.',key,numel(val),nExpected);
                        val = [];
                        return;
                    end
                    ok = true;
                    return;
                end
            end
            msg = sprintf('The QC metric "%s" is not available for the selected result source.',key);
        end

        function mask = viewerSubIndexMask(handles, n)
            mask = true(n,1);
            % nm2-allow: applyPlotVectorSubgroupOverride conditionally writes SubIndex at the public presentation boundary
            if isfield(handles,'SubIndex')
                raw = logical(handles.SubIndex(:));
                % nm2-allow: subgroup presentation mask must match the materialized result case axis exactly
                if numel(raw) ~= n
                    error('NMResultsViewerTools:PlotVectorSubgroupAxisMismatch', ...
                        'The subgroup mask has %d entries for a %d-case result axis.',numel(raw),n);
                end
                mask = raw;
            end
        end

        function txt = formatNumber(x)
            if isempty(x) || ~isfinite(double(x(1))), txt = 'n/a'; else, txt = sprintf('%.4g', double(x(1))); end
        end

        function v = rangeValue(x)
            x = double(x(:)); x = x(isfinite(x));
            if isempty(x), v = 0; else, v = max(x)-min(x); end
        end

        function p = probTransformMethod(labelh, predh, method)
            if isempty(method), method = 'platt'; end
            y = double(labelh(:)); y(y==-1 | y==2) = 0;
            z = double(predh(:));
            if strcmp(method,'none') || all(z >= 0 & z <= 1)
                p = z; return;
            end
            p = probtransform(y, z, [], method);
        end

        function info = emptyCalibrationPersistInfo()
            info = struct('cvCanPersist',false,'cvUsedStored',false,'cvProbabilities',[],'cvMethod','', ...
                'oocvCanPersist',false,'oocvUsedStored',false,'oocvProbabilities',[],'oocvMethod','', ...
                'oocvGlobalIndex',NaN);
        end

        function probs = storedCalibrationProbabilities(S, n, forceRecomputeProbability)
            probs = [];

            if forceRecomputeProbability, return; end
            if ~isstruct(S) || ~isfield(S,'Calibration') || ~isstruct(S.Calibration), return; end
            if ~isfield(S.Calibration,'Probabilities') || isempty(S.Calibration.Probabilities), return; end
            p = double(S.Calibration.Probabilities(:));
            if ~isempty(n) && isfinite(double(n))
                p = NMResultsViewerTools.padNumericColumn(p, round(double(n)), NaN);
                p = p(1:round(double(n)));
            end
            if any(isfinite(p)), probs = p; end
        end

        function methodOut = storedCalibrationMethod(S, fallback)
            methodOut = char(string(fallback));
            if isstruct(S) && isfield(S,'Calibration') && isstruct(S.Calibration) && isfield(S.Calibration,'Method') && ~isempty(S.Calibration.Method)
                methodOut = lower(strtrim(char(string(S.Calibration.Method))));
                if isempty(methodOut), methodOut = char(string(fallback)); end
            end
        end

        function C = calibrationArtifact(probabilities, method, classifierIndex)

            C = struct('Probabilities',double(probabilities(:)), ...
                'Method',method, ...
                'Source','NMResultsViewer', ...
                'Created',datestr(now), ...
                'ClassifierIndex',double(classifierIndex));
        end

        function [NM, didPersist] = persistClassificationProbabilityArtifact(NM, idx, clsIdx, source, persistInfo, methodOut, forceRecomputeProbability) %#ok<INUSD>
            didPersist = false;
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || idx < 1 || idx > numel(NM.analysis), return; end
            if isempty(methodOut), methodOut = 'platt'; end
            if persistInfo.cvCanPersist && ~isempty(persistInfo.cvProbabilities) && (~persistInfo.cvUsedStored || forceRecomputeProbability)
                gdIdx = NMResultsViewerTools.primaryGDdimsIndex(NM.analysis{idx});
                if gdIdx > 0
                    GD = NM.analysis{idx}.GDdims{gdIdx};
                    if isstruct(GD) && isfield(GD,'BinClass') && iscell(GD.BinClass) && clsIdx <= numel(GD.BinClass) && isstruct(GD.BinClass{clsIdx})
                        meth = methodOut;
                        if ~isempty(persistInfo.cvMethod), meth = persistInfo.cvMethod; end
                        GD.BinClass{clsIdx}.Calibration = NMResultsViewerTools.calibrationArtifact(persistInfo.cvProbabilities, meth, clsIdx);
                        NM.analysis{idx}.GDdims{gdIdx} = GD;
                        didPersist = true;
                    end
                end
            end
            [isOOCVSource, requestedGlobal] = NMResultsViewerTools.parseOOCVSourceId(source);
            if isOOCVSource && persistInfo.oocvCanPersist && ~isempty(persistInfo.oocvProbabilities) && (~persistInfo.oocvUsedStored || forceRecomputeProbability)
                g = requestedGlobal;
                if isfinite(double(persistInfo.oocvGlobalIndex)) && double(persistInfo.oocvGlobalIndex) > 0
                    g = round(double(persistInfo.oocvGlobalIndex));
                end
                if isfield(NM.analysis{idx},'OOCV') && iscell(NM.analysis{idx}.OOCV) && g >= 1 && g <= numel(NM.analysis{idx}.OOCV) && isstruct(NM.analysis{idx}.OOCV{g}) && isfield(NM.analysis{idx}.OOCV{g},'BinResults')
                    R = NM.analysis{idx}.OOCV{g};
                    meth = methodOut;
                    if ~isempty(persistInfo.oocvMethod), meth = persistInfo.oocvMethod; end
                    % nm2-allow: nk_OOCV conditionally fills compact-target BinResults cells; absent target material cannot be modified.
                    if ~isempty(R.BinResults) && isstruct(R.BinResults{1})
                        R.BinResults{1}.Calibration = NMResultsViewerTools.calibrationArtifact(persistInfo.oocvProbabilities, meth, clsIdx);
                        didPersist = true;
                    end
                    NM.analysis{idx}.OOCV{g} = R;
                end
            end
        end

        function gdIdx = primaryGDdimsIndex(A)
            gdIdx = 0;
            if ~isfield(A,'GDdims') || isempty(A.GDdims), return; end % nm2-allow: H7 completed-analysis GDdims is an optional persisted result family.
            g = A.GDdims;
            for ii = 1:numel(g)
                % nm2-allow: nk_MLOptimizerPrep creates modality result cells conditionally; an unpopulated result slot is unavailable.
                if isstruct(g{ii}) && ~isempty(g{ii}), gdIdx = ii; return; end
            end
        end

        function handles = overlayPersistedBinClassCalibration(handles, GD)
            if ~isstruct(GD) || ~isfield(GD,'BinClass') || ~iscell(GD.BinClass), return; end
            if ~isfield(handles,'BinClass') || ~iscell(handles.BinClass), return; end
            n = min(numel(GD.BinClass), numel(handles.BinClass));
            for ii = 1:n
                if isstruct(GD.BinClass{ii}) && isfield(GD.BinClass{ii},'Calibration') && isstruct(GD.BinClass{ii}.Calibration) && isstruct(handles.BinClass{ii})
                    handles.BinClass{ii}.Calibration = GD.BinClass{ii}.Calibration;
                end
            end
        end

        function [labels01, probs, rawScores, titleText, methodOut, msg, persistInfo] = classificationProbabilitiesFromHandles(handles, h, method, forceRecomputeProbability)
            B = handles.BinClass{h};
            methodOut = method;
            titleText = sprintf('%s | %s', B.description, NMResultsViewerTools.calibrationMethodLabel(methodOut));
            labels01 = double(B.labelh(:)); labels01(labels01==-1 | labels01==2) = 0;
            rawScores = double(B.mean_predictions(:));
            % nm2-allow: load_GDdims writes BinClass labelh and mean_predictions on one transformed case axis
            if numel(labels01) ~= numel(rawScores)
                error('NMResultsViewerTools:InvalidClassificationCaseAxis', 'Classification labels and scores must share the transformed case axis.');
            end
            n = numel(labels01);
            persistInfo = NMResultsViewerTools.emptyCalibrationPersistInfo();
            persistInfo.cvProbabilities = nan(n,1);
            persistInfo.cvCanPersist = true;

            stored = NMResultsViewerTools.storedCalibrationProbabilities(B, n, forceRecomputeProbability);
            probflag = logical(handles.params.probflag);
            if ~isempty(stored)
                persistInfo.cvUsedStored = true;
                probs = stored;
                methodOut = NMResultsViewerTools.storedCalibrationMethod(B, methodOut);
                msg = sprintf('Reused persisted Discovery/CV probability scores from BinClass{%d}.Calibration.Probabilities.', h);
            elseif probflag
                probs = rawScores;
                if max(probs) < 0.5, probs = probs + 0.5; end
                methodOut = 'native';
                msg = 'Native/probabilistic classifier outputs are used directly as probabilities.';
            elseif strcmp(methodOut,'none')
                probs = rawScores;
                msg = 'No calibration selected. Raw decision scores are passed through; DCA/calibration panels expect bounded probabilities.';
            else
                probs = NMResultsViewerTools.probTransformMethod(labels01, rawScores, methodOut);
                msg = sprintf('Decision scores converted to probabilities using %s, following the perf_calibration/probtransform path.', NMResultsViewerTools.calibrationMethodLabel(methodOut));
            end
            probs = double(probs(:));
            % nm2-allow: calibration probability producer must preserve the fixed transformed case axis
            if numel(probs) ~= n
                error('NMResultsViewerTools:InvalidClassificationProbabilityAxis', 'Classification probabilities must match the transformed case axis.');
            end
            persistInfo.cvProbabilities = probs;
            persistInfo.cvMethod = methodOut;
            titleText = sprintf('%s | %s', B.description, NMResultsViewerTools.calibrationMethodLabel(methodOut));
        end

        function [labelsCV, probsCV, scoresCV, labelsOOCV, probsOOCV, scoresOOCV, titleText, methodOut, msg, persistInfo] = classificationProbabilitiesFromOOCVHandles(handles, h, method, forceRecomputeProbability)
            [labelsCV, probsCV, scoresCV, titleText, methodOut, msgCV, persistInfo] = NMResultsViewerTools.classificationProbabilitiesFromHandles(handles, h, method, forceRecomputeProbability);
            [OOCVres, ~] = NMResultsViewerTools.oocvResultContainer(handles, handles.oocvind);
            if ~NMResultsViewerTools.oocvLabelsKnown(handles, handles.oocvind)
                error('NMResultsViewerTools:OOCVLabelsUnknown', 'OOCV calibration and DCA require known OOCV labels.');
            end
            labelsOOCVAll = double(OOCVres.BinLabels{h}(:)); labelsOOCVAll(labelsOOCVAll==-1 | labelsOOCVAll==2) = 0;
            scoresOOCVAll = double(OOCVres.MeanCV2PredictedValues{h}(:));
            % nm2-allow: nk_OOCV writes BinLabels and MeanCV2PredictedValues on one application case axis
            if numel(labelsOOCVAll) ~= numel(scoresOOCVAll)
                error('NMResultsViewerTools:InvalidOOCVClassificationCaseAxis', 'OOCV labels and scores must share the application case axis.');
            end
            nOAll = numel(labelsOOCVAll);
            [~, ~, subgroupMask] = NMResultsViewerTools.applyOOCVSubgroupSelection(handles, OOCVres, h, handles.oocvind, nOAll);
            subgroupMask = logical(subgroupMask(:));
            % nm2-allow: OOCV subgroup authority returns a mask on the exact application case axis
            if numel(subgroupMask) ~= nOAll
                error('NMResultsViewerTools:InvalidOOCVSubgroupAxis', 'OOCV subgroup mask must match the application case axis.');
            end

            storedOOCV = NMResultsViewerTools.storedCalibrationProbabilities(OOCVres, nOAll, forceRecomputeProbability);
            probflag = logical(handles.params.probflag);
            if ~isempty(storedOOCV)
                persistInfo.oocvUsedStored = true;
                probsOOCVAll = storedOOCV;
                methodOut = NMResultsViewerTools.storedCalibrationMethod(OOCVres, methodOut);
                msg = 'Reused persisted OOCV probability scores with persisted/active Discovery-CV reference probabilities.';
            elseif probflag
                probsOOCVAll = scoresOOCVAll;
                if max(probsOOCVAll) < 0.5, probsOOCVAll = probsOOCVAll + 0.5; end
                methodOut = 'native';
                msg = 'Native/probabilistic classifier outputs are used directly as OOCV probabilities; Discovery/CV probabilities are carried as a faint reference curve.';
            elseif strcmp(methodOut,'none')
                probsOOCVAll = scoresOOCVAll;
                msg = 'No calibration selected. OOCV decision scores are passed through; DCA/calibration panels require bounded probabilities.';
            else
                probsOOCVAll = NMResultsViewerTools.probTransformAgainstReference(labelsCV, scoresCV, scoresOOCVAll, methodOut);
                msg = sprintf('Decision scores converted to OOCV probabilities using %s; Discovery/CV probabilities are carried as a faint reference curve.', NMResultsViewerTools.calibrationMethodLabel(methodOut));
            end
            probsOOCVAll = double(probsOOCVAll(:));
            % nm2-allow: calibration probability producer must preserve the fixed application case axis
            if numel(probsOOCVAll) ~= nOAll
                error('NMResultsViewerTools:InvalidOOCVClassificationProbabilityAxis', 'OOCV probabilities must match the application case axis.');
            end
            persistInfo.oocvProbabilities = probsOOCVAll;
            persistInfo.oocvMethod = methodOut;
            persistInfo.oocvCanPersist = true;
            persistInfo.oocvGlobalIndex = double(handles.OOCV(handles.oocvind).num);

            labelsOOCV = labelsOOCVAll(subgroupMask);
            scoresOOCV = scoresOOCVAll(subgroupMask);
            probsOOCV = probsOOCVAll(subgroupMask);
            msg = sprintf('%s %s', msg, msgCV);
        end

        function [labels01, scores] = regressionBinaryVectorsFromPoints(points)
            % Regression CV/OOCV point constructors always provide both fields.
            if isempty(points), labels01 = []; scores = []; return; end
            labels = double([points.binaryObserved]');
            scores = double([points.binaryScore]');
            good = isfinite(labels) & isfinite(scores);
            labels = labels(good); scores = scores(good);
            labels(labels==-1 | labels==2) = 0;
            labels01 = labels(:);
            scores = scores(:);
        end

        function [probsActive, probsReference, methodOut, msg, persistInfo] = regressionBinarizedProbabilities(NM, idx, targetIdx, source, threshold, activeLabels, activeScores, referenceLabels, referenceScores, method, forceRecomputeProbability)
            methodOut = method; % canonical calibration token (viewerPlotOptions)
            persistInfo = NMResultsViewerTools.emptyRegressionBinarizedPersistInfo();
            persistInfo.threshold = double(threshold);
            persistInfo.targetIndex = double(targetIdx);
            persistInfo.method = methodOut;
            [isOOCVSource, oocvGlobalIndex] = NMResultsViewerTools.parseOOCVSourceId(source);
            persistInfo.oocvGlobalIndex = double(oocvGlobalIndex);

            probsReference = [];
            if isOOCVSource
                storedReference = NMResultsViewerTools.storedRegressionBinarizedCVProbabilities(NM, idx, numel(referenceScores), threshold, forceRecomputeProbability);
                if ~isempty(storedReference)
                    persistInfo.cvUsedStored = true;
                    probsReference = storedReference;
                    msgReference = 'Reused persisted Discovery/CV derived binary-risk probabilities from Regr.Calibration.BinarizedRegression.';
                else
                    probsReference = NMResultsViewerTools.probTransformMethod(referenceLabels, referenceScores, methodOut);
                    msgReference = sprintf('Derived Discovery/CV binary-risk probabilities from regression predictions using %s.', NMResultsViewerTools.calibrationMethodLabel(methodOut));
                end
                persistInfo.cvCanPersist = true;
                persistInfo.cvProbabilities = probsReference(:);
                persistInfo.cvLabels = referenceLabels(:);
                persistInfo.cvScores = referenceScores(:);

                storedActive = NMResultsViewerTools.storedRegressionBinarizedOOCVProbabilities(NM, idx, targetIdx, oocvGlobalIndex, numel(activeScores), threshold, forceRecomputeProbability);
                if ~isempty(storedActive)
                    persistInfo.oocvUsedStored = true;
                    probsActive = storedActive;
                    msgActive = 'Reused persisted OOCV derived binary-risk probabilities from RegrResults.Calibration.BinarizedRegression.';
                else
                    probsActive = NMResultsViewerTools.probTransformAgainstReference(referenceLabels, referenceScores, activeScores, methodOut);
                    msgActive = sprintf('Applied Discovery/CV-fitted %s conversion to OOCV regression predictions.', NMResultsViewerTools.calibrationMethodLabel(methodOut));
                end
                persistInfo.oocvCanPersist = true;
                persistInfo.oocvProbabilities = probsActive(:);
                persistInfo.oocvLabels = activeLabels(:);
                persistInfo.oocvScores = activeScores(:);
                msg = sprintf('%s %s Probabilities are derived from regression predictions using threshold %.4g.', msgActive, msgReference, threshold);
            else
                storedActive = NMResultsViewerTools.storedRegressionBinarizedCVProbabilities(NM, idx, numel(activeScores), threshold, forceRecomputeProbability);
                if ~isempty(storedActive)
                    persistInfo.cvUsedStored = true;
                    probsActive = storedActive;
                    msg = sprintf('Reused persisted Discovery/CV derived binary-risk probabilities from Regr.Calibration.BinarizedRegression for threshold %.4g.', threshold);
                else
                    probsActive = NMResultsViewerTools.probTransformMethod(activeLabels, activeScores, methodOut);
                    msg = sprintf('Derived Discovery/CV binary-risk probabilities from regression predictions using %s and threshold %.4g.', NMResultsViewerTools.calibrationMethodLabel(methodOut), threshold);
                end
                persistInfo.cvCanPersist = true;
                persistInfo.cvProbabilities = probsActive(:);
                persistInfo.cvLabels = activeLabels(:);
                persistInfo.cvScores = activeScores(:);
            end
            probsActive = NMResultsViewerTools.padNumericColumn(double(probsActive(:)), numel(activeLabels), NaN);
            if isOOCVSource
                probsReference = NMResultsViewerTools.padNumericColumn(double(probsReference(:)), numel(referenceLabels), NaN);
            end
        end

        function info = emptyRegressionBinarizedPersistInfo()
            info = struct('threshold',NaN,'targetIndex',NaN,'method','', ...
                'cvCanPersist',false,'cvUsedStored',false,'cvProbabilities',[],'cvLabels',[],'cvScores',[], ...
                'oocvCanPersist',false,'oocvUsedStored',false,'oocvProbabilities',[],'oocvLabels',[],'oocvScores',[],'oocvGlobalIndex',NaN);
        end

        function probs = storedRegressionBinarizedCVProbabilities(NM, idx, n, threshold, forceRecomputeProbability)
            probs = [];

            if forceRecomputeProbability, return; end
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || idx < 1 || idx > numel(NM.analysis), return; end
            gdIdx = NMResultsViewerTools.primaryGDdimsIndex(NM.analysis{idx});
            if gdIdx <= 0, return; end
            GD = NM.analysis{idx}.GDdims{gdIdx};
            if ~isstruct(GD) || ~isfield(GD,'Regr') || ~isstruct(GD.Regr), return; end
            probs = NMResultsViewerTools.storedRegressionBinarizedProbabilities(GD.Regr, n, threshold, forceRecomputeProbability);
        end

        function probs = storedRegressionBinarizedOOCVProbabilities(NM, idx, targetIdx, g, n, threshold, forceRecomputeProbability)
            probs = [];

            if forceRecomputeProbability, return; end
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || idx < 1 || idx > numel(NM.analysis), return; end
            if ~isfield(NM.analysis{idx},'OOCV') || ~iscell(NM.analysis{idx}.OOCV) || g < 1 || g > numel(NM.analysis{idx}.OOCV), return; end
            R = NM.analysis{idx}.OOCV{g};
            if ~isstruct(R) || ~isfield(R,'RegrResults') || isempty(R.RegrResults), return; end
            rr = R.RegrResults;
            targetIdx = max(1, round(double(targetIdx)));
            % nm2-allow: nk_OOCV optionally populates compact-target RegrResults cells; absent target material is not a stored probability artifact.
            if targetIdx > numel(rr) || ~isstruct(rr{targetIdx}), return; end
            S = rr{targetIdx};
            probs = NMResultsViewerTools.storedRegressionBinarizedProbabilities(S, n, threshold, forceRecomputeProbability);
        end

        function probs = storedRegressionBinarizedProbabilities(S, n, threshold, forceRecomputeProbability)
            probs = [];

            if forceRecomputeProbability, return; end
            if ~isstruct(S) || ~isfield(S,'Calibration') || ~isstruct(S.Calibration), return; end
            if ~isfield(S.Calibration,'BinarizedRegression') || ~isstruct(S.Calibration.BinarizedRegression), return; end
            C = S.Calibration.BinarizedRegression;
            if isempty(C.Threshold) || abs(double(C.Threshold(1)) - double(threshold)) > max(1e-8, abs(double(threshold))*1e-8), return; end
            if isempty(C.Probabilities), return; end
            p = double(C.Probabilities(:));
            if ~isempty(n) && isfinite(double(n))
                p = NMResultsViewerTools.padNumericColumn(p, round(double(n)), NaN);
                p = p(1:round(double(n)));
            end
            if any(isfinite(p)), probs = p; end
        end

        function C = regressionBinarizedCalibrationArtifact(probabilities, labels01, scores, method, threshold, targetIdx, role)
            C = struct('Probabilities',double(probabilities(:)), ...
                'Labels01',double(labels01(:)), ...
                'Scores',double(scores(:)), ...
                'Method',method, ...
                'Threshold',double(threshold), ...
                'Direction','greater_or_equal', ...
                'TargetIndex',double(targetIdx), ...
                'Role',char(string(role)), ...
                'Source','NMResultsViewer', ...
                'Created',datestr(now));
        end

        function [NM, didPersist] = persistRegressionBinarizedProbabilityArtifact(NM, idx, targetIdx, source, persistInfo, methodOut, forceRecomputeProbability) %#ok<INUSD>
            didPersist = false;
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || idx < 1 || idx > numel(NM.analysis), return; end
            if ~isfinite(double(persistInfo.threshold)), return; end
            threshold = double(persistInfo.threshold);
            targetIdx = max(1, round(double(targetIdx)));
            if persistInfo.cvCanPersist && ~isempty(persistInfo.cvProbabilities) && (~persistInfo.cvUsedStored || forceRecomputeProbability)
                gdIdx = NMResultsViewerTools.primaryGDdimsIndex(NM.analysis{idx});
                if gdIdx > 0
                    GD = NM.analysis{idx}.GDdims{gdIdx};
                    if isstruct(GD) && isfield(GD,'Regr') && isstruct(GD.Regr)
                        if ~isfield(GD.Regr,'Calibration') || ~isstruct(GD.Regr.Calibration), GD.Regr.Calibration = struct(); end
                        GD.Regr.Calibration.BinarizedRegression = NMResultsViewerTools.regressionBinarizedCalibrationArtifact( ...
                            persistInfo.cvProbabilities, persistInfo.cvLabels, persistInfo.cvScores, methodOut, threshold, targetIdx, 'Discovery/CV');
                        NM.analysis{idx}.GDdims{gdIdx} = GD;
                        didPersist = true;
                    end
                end
            end
            [isOOCVSource, requestedGlobal] = NMResultsViewerTools.parseOOCVSourceId(source);
            if isOOCVSource && persistInfo.oocvCanPersist && ~isempty(persistInfo.oocvProbabilities) && (~persistInfo.oocvUsedStored || forceRecomputeProbability)
                g = requestedGlobal;
                if isfinite(double(persistInfo.oocvGlobalIndex)) && double(persistInfo.oocvGlobalIndex) > 0
                    g = round(double(persistInfo.oocvGlobalIndex));
                end
                if isfield(NM.analysis{idx},'OOCV') && iscell(NM.analysis{idx}.OOCV) && g >= 1 && g <= numel(NM.analysis{idx}.OOCV) && isstruct(NM.analysis{idx}.OOCV{g}) && isfield(NM.analysis{idx}.OOCV{g},'RegrResults')
                    R = NM.analysis{idx}.OOCV{g};
                    % nm2-allow: nk_OOCV writes compact-target RegrResults cells conditionally; missing target results are not writable.
                    if targetIdx <= numel(R.RegrResults) && isstruct(R.RegrResults{targetIdx})
                        % nm2-allow: current calibration writer augments existing regression result objects; a prior Calibration branch is optional.
                        if ~isfield(R.RegrResults{targetIdx},'Calibration') || ~isstruct(R.RegrResults{targetIdx}.Calibration), R.RegrResults{targetIdx}.Calibration = struct(); end
                        R.RegrResults{targetIdx}.Calibration.BinarizedRegression = NMResultsViewerTools.regressionBinarizedCalibrationArtifact( ...
                            persistInfo.oocvProbabilities, persistInfo.oocvLabels, persistInfo.oocvScores, methodOut, threshold, targetIdx, 'OOCV');
                        didPersist = true;
                    end
                    NM.analysis{idx}.OOCV{g} = R;
                end
            end
        end

        function V = probabilityVectorPayload(labels, probs, scores, label)
            labels = double(labels(:)); probs = double(probs(:)); scores = double(scores(:));
            n = min([numel(labels), numel(probs)]);
            if isempty(scores)
                scores = nan(n,1);
            elseif numel(scores) < n
                scores(end+1:n,1) = NaN;
            end
            V = struct('label',label,'labels',double(labels(1:n)'), ...
                'probabilities',double(probs(1:n)'),'scores',double(scores(1:n)'),'n',double(n));
        end

        function txt = calibrationMethodLabel(method)
            switch method
                case 'platt', txt = 'Platt Scaling';
                case 'isotonic', txt = 'Isotonic Regression';
                case 'bbq', txt = 'Bayesian Binning into Quantiles (BBQ)';
                case 'native', txt = 'Native probabilities';
                otherwise, txt = 'No Calibration';
            end
        end

        function P = probabilitySummaryPayload(labels01, probs, rawScores, titleText, method)
            n = min([numel(labels01), numel(probs), numel(rawScores), 1000]);
            rowTmpl = struct('index',0,'label',NaN,'score',NaN,'probability',NaN);
            rows = repmat(rowTmpl, 1, n);
            for i=1:n
                rows(i).index = i;
                rows(i).label = double(labels01(i));
                rows(i).score = double(rawScores(i));
                rows(i).probability = double(probs(i));
            end
            P = struct('ok',true,'title',titleText,'method',method, ...
                'methodLabel',NMResultsViewerTools.calibrationMethodLabel(method), ...
                'n',numel(probs),'minProb',min(probs),'maxProb',max(probs),'rows',rows);
        end

        function C = calibrationCurvePayload(labels01, probs, numBins, smoothCurve, metric, titleText, method)
            C = struct('ok',false,'title',titleText,'method',method,'methodLabel',NMResultsViewerTools.calibrationMethodLabel(method), ...
                'multi',false,'curves',struct([]),'activeLabel','Active','referenceLabel','','hasReferenceCurve',false, ...
                'referenceCurve',struct('ok',false,'label','','color','#64748b','points',[],'smoothPoints',[]), ...
                'numBins',numBins,'smoothCurve',logical(smoothCurve),'metric',metric, ...
                'metricValue',NaN,'points',[],'smoothPoints',[],'message','');
            y = double(labels01(:)); p = double(probs(:));
            good = isfinite(y) & isfinite(p);
            y = y(good); p = p(good);
            if isempty(y) || isempty(p) || numel(unique(y)) < 2
                C.message = 'Calibration analysis requires finite binary labels from both classes.'; return;
            end
            if any(p < 0 | p > 1)
                C.message = 'Calibration analysis requires bounded probabilities. Select Platt, isotonic or BBQ conversion before plotting calibration.'; return;
            end
            [ece, meanPred, fracPos, binCount] = ECE(y, p, numBins);
            valid = isfinite(meanPred) & isfinite(fracPos);
            meanPred = meanPred(valid); fracPos = fracPos(valid); binCount = binCount(valid);
            n = numel(meanPred);
            ptTmpl = struct('meanPredicted',NaN,'fractionPositive',NaN,'count',0);
            pts = repmat(ptTmpl, 1, n);
            for i=1:n
                pts(i).meanPredicted = double(meanPred(i));
                pts(i).fractionPositive = double(fracPos(i));
                pts(i).count = double(binCount(i));
            end
            C.points = pts;
            if strcmpi(metric,'Brier Score')
                C.metric = 'Brier Score';
                C.metricValue = mean((p - y).^2);
            else
                C.metric = 'ECE';
                C.metricValue = ece;
            end
            if smoothCurve && n >= 2
                grid = linspace(min(meanPred), max(meanPred), 100);
                sm = interp1(meanPred, fracPos, grid, 'pchip');
                smTmpl = struct('meanPredicted',NaN,'fractionPositive',NaN);
                smPts = repmat(smTmpl, 1, numel(grid));
                for i=1:numel(grid)
                    smPts(i).meanPredicted = double(grid(i));
                    smPts(i).fractionPositive = double(sm(i));
                end
                C.smoothPoints = smPts;
            end
            C.ok = n >= 2;
            if ~C.ok, C.message = 'Not enough occupied calibration bins to draw a curve.'; end
        end

        function D = dcaPayload(labels01, probs, labelsReference, probsReference, maxProb, stepSize, titleText, method)
            D = struct('ok',false,'title',titleText,'method',method,'methodLabel',NMResultsViewerTools.calibrationMethodLabel(method), ...
                'multi',false,'curves',struct([]),'activeLabel','Active','referenceLabel','','maxProb',maxProb,'stepSize',stepSize, ...
                'train',struct('label','Active','points',[]),'active',struct('label','Active','points',[]), ...
                'reference',struct('label','Discovery/CV','points',[]),'oocv',struct('label','Active','points',[]),'message','');
            y = double(labels01(:)); p = double(probs(:));
            good = isfinite(y) & isfinite(p); y = y(good); p = p(good);
            if isempty(y) || isempty(p) || numel(unique(y)) < 2
                D.message = 'DCA requires finite binary labels from both classes.'; return;
            end
            if any(p < 0 | p > 1)
                D.message = 'DCA requires bounded probabilities. Select Platt, isotonic or BBQ conversion before plotting DCA.'; return;
            end
            [thr, nb, ta, tn] = nk_DCA(y, p, maxProb, stepSize);
            D.active = NMResultsViewerTools.dcaCurveStruct(thr, nb, ta, tn, 'Active');
            D.train = D.active;
            if ~isempty(labelsReference) && ~isempty(probsReference)
                yr = double(labelsReference(:)); pr = double(probsReference(:)); good = isfinite(yr) & isfinite(pr);
                yr = yr(good); pr = pr(good);
                if numel(yr) > 2 && numel(unique(yr)) >= 2 && all(pr >= 0 & pr <= 1)
                    [tr, nbr, tar, tnr] = nk_DCA(yr, pr, maxProb, stepSize);
                    D.reference = NMResultsViewerTools.dcaCurveStruct(tr, nbr, tar, tnr, 'Discovery/CV');
                    D.oocv = D.active;
                end
            end
            D.ok = true;
        end

        function S = dcaCurveStruct(thr, nb, ta, tn, label)
            n = numel(thr);
            ptTmpl = struct('threshold',NaN,'model',NaN,'treatAll',NaN,'treatNone',NaN);
            pts = repmat(ptTmpl, 1, n);
            for i=1:n
                pts(i).threshold = double(thr(i));
                pts(i).model = double(nb(i));
                pts(i).treatAll = double(ta(i));
                pts(i).treatNone = double(tn(i));
            end
            S = struct('label',label,'points',pts);
        end

        function p = initialDcaMaxProbability(y, p)
            [thr, nb] = nk_DCA(y, p, 1, 0.01);
            idx = find(nb > 0);
            if isempty(idx), p = 1; else, p = double(thr(max(idx))); end
        end

        function C = colorTable()
            C = getNMcolors;
        end

        function h = rgbHex(c)
            c = double(c(:)'); if numel(c) < 3, c = [0.4 0.4 0.4]; end
            c = max(0,min(1,c(1:3)));
            h = sprintf('#%02X%02X%02X', round(c(1)*255), round(c(2)*255), round(c(3)*255));
        end

        function out = asStringCell(x)
            if isempty(x), out = {'Group 1','Group 2'}; return; end
            if isstring(x), out = cellstr(x); elseif ischar(x), out = cellstr(x); elseif iscell(x), out = x; else, out = cellstr(string(x)); end
            out = out(:)';
            for i=1:numel(out), out{i} = char(string(out{i})); end
            if numel(out) < 2, out{2} = 'Group 2'; end
        end
    end

    methods (Static, Access = private)
        function [ok, msg, out] = modelOptimizationAvailability(NM, idx, spec)
            % modelOptimizationAvailability  Resolve one canonical optimization source and selector context.
            ok = false;
            msg = 'No model-optimization grid payload detected.';
            sources=NMResultsViewerTools.emptyModelOptimizationSources();
            selectedSource='';
            context=NMResultsViewerTools.emptyModelOptimizationContext();
            grid=NMResultsViewerTools.emptyModelOptimizationGrid();
            metrics=NMResultsViewerTools.emptyModelOptimizationMetrics();
            partitions=NMResultsViewerTools.emptyModelOptimizationPartitions();
            A=[];
            out=NMResultsViewerTools.modelOptimizationAvailabilityStruct(A,idx,sources,selectedSource,context,grid,metrics,partitions,msg);
            % nm2-allow: public Model Optimization payload boundary accepts an absent or invalid analysis selection.
            if isnan(double(idx)) || idx < 1 || idx > numel(NM.analysis)
                msg = 'Select a completed analysis to inspect model optimization.';
                out.message=msg;
                return;
            end
            A = NM.analysis{idx};
            sources = NMResultsViewerTools.modelSourcesForAnalysis(NM, idx, 'model_optimization', spec);
            if isempty(sources)
                msg = 'The selected analysis does not contain model-optimization sources.';
                out=NMResultsViewerTools.modelOptimizationAvailabilityStruct(A,idx,sources,selectedSource,context,grid,metrics,partitions,msg);
                return;
            end
            selectedSource = NMResultsViewerTools.selectedModelSourceId(sources, spec);
            [sourceOk, GD, sourceInfo, sourceMsg] = NMResultsViewerTools.modelGDFromSource(A, sources, selectedSource);
            if ~sourceOk
                msg = sourceMsg;
                out=NMResultsViewerTools.modelOptimizationAvailabilityStruct(A,idx,sources,selectedSource,context,grid,metrics,partitions,msg);
                return;
            end

            [~, modeflag] = NMResultsViewerTools.analysisLabelAndMode(NM, A);
            targets=NMResultsViewerTools.targetOptions(NM,idx);
            targetNativeIdx=NMResultsViewerTools.selectedTargetIndex(targets,spec);
            targetIdx=NMResultsViewerTools.selectedTargetResultIndex(targets,targetNativeIdx);
            classifierIdx = spec.classifierIndex;
            if isnan(double(classifierIdx)),classifierIdx=1;end
            if classifierIdx < 1 || classifierIdx ~= round(classifierIdx)
                error('NMResultsViewerTools:InvalidOptimizationClassifier','classifierIndex must be one positive integer.');
            end
            nBinary = NMResultsViewerTools.modelOptimizationBinaryClassifierCount(GD,modeflag);
            if strcmp(modeflag,'regression')
                if classifierIdx ~= 1
                    error('NMResultsViewerTools:InvalidOptimizationClassifier','Regression model optimization has classifierIndex 1 only.');
                end
                modelFamily='regression';
                isMulti=false;
            else
                hasMulti=logical(A.params.TrainParam.MULTI.flag);
                nOptions=nBinary+double(hasMulti);
                if classifierIdx > nOptions
                    error('NMResultsViewerTools:InvalidOptimizationClassifier', ...
                        'classifierIndex %d exceeds the %d classifier option(s) produced by the selected analysis.',classifierIdx,nOptions);
                end
                isMulti=hasMulti && classifierIdx==nBinary+1;
                if isMulti,modelFamily='multiclass';else,modelFamily='classification';end
            end

            context = NMResultsViewerTools.emptyModelOptimizationContext();
            context.analysisIndex = idx;
            context.targetIndex = targetIdx;
            context.classifierIndex = classifierIdx;
            context.binaryClassifierCount = nBinary;
            context.modeflag = modeflag;
            context.modelFamily = modelFamily;
            context.isMultiClass = isMulti;
            context.isMeta = sourceInfo.isMeta;
            context.modelSource = sourceInfo.id;
            context.modelSourceLabel = sourceInfo.label;
            context.modalityIndex = sourceInfo.index;
            context.criterionCode = double(A.params.TrainParam.SVM.GridParam);
            if context.isMeta
                context.legacyMeasureSource = 'META/display_modelperf_bagged';
                context.metricBasis = 'training_cv_bagged_meta_summary';
            else
                context.legacyMeasureSource = 'GDdims.grid/display_modelperf';
                context.metricBasis = 'training_cv_optimization_grid';
            end
            if isMulti
                context.classifierLabel = 'Multi-group classifier';
            elseif strcmp(modelFamily,'regression')
                context.classifierLabel = 'Regression model';
            else
                context.classifierLabel = NMResultsViewerTools.classifierLabel(A, classifierIdx);
            end

            metrics = NMResultsViewerTools.buildModelOptimizationMetrics(GD, A, context);
            nMetricRows = NMResultsViewerTools.modelOptimizationMetricRowCount(metrics);
            grid = NMResultsViewerTools.normalizeModelOptimizationGrid(GD, context, nMetricRows);
            partitions = NMResultsViewerTools.buildModelOptimizationPartitions(GD, A, context);
            comparisons = NMResultsViewerTools.buildModelOptimizationComparisons(metrics);
            out = NMResultsViewerTools.modelOptimizationAvailabilityStruct(A,idx,sources,selectedSource,context,grid,metrics,partitions,msg);
            out.comparisons = comparisons;
            out.subtitle = sprintf('%s: %s', context.modelSourceLabel, context.classifierLabel);

            availableMask = NMResultsViewerTools.modelOptimizationMetricAvailableMask(metrics);
            if ~grid.ok
                msg = grid.message;
                out.message = msg;
                return;
            end
            if ~any(availableMask)
                msg = 'The selected optimization result contains no available measure for this classifier/target context.';
                out.message = msg;
                return;
            end
            ok = true;
            msg = sprintf('Model-optimization metric registry extracted for analysis %d, %s, %s.', idx, context.modelSourceLabel, context.classifierLabel);
            out.message = msg;
        end

        function out = modelOptimizationAvailabilityStruct(A, idx, sources, selectedSource, context, grid, metrics, partitions, msg)
            % modelOptimizationAvailabilityStruct  Create the fixed internal availability object.
            out = struct();
            out.analysisIndex = idx;
            out.modelSources = sources;
            out.selectedModelSource = selectedSource;
            out.context = context;
            out.grid = grid;
            out.metrics = metrics;
            out.partitions = partitions;
            out.comparisons = NMResultsViewerTools.emptyModelOptimizationComparisons();
            if isempty(A),out.title='Model optimization';else,out.title=NMResultsViewerTools.analysisTitle(A,idx);end
            out.subtitle = '';
            out.message = msg;
        end

        function [ok, reason] = performanceModelSourceAvailable(GD, kind)
            % performanceModelSourceAvailable  Test only the authoritative result container for one model source.
            ok=false; reason=''; if ~isstruct(GD)||isempty(GD),reason='Model source is empty or not a struct.';return;end
            switch NMResultsViewerTools.normalizeResultType(kind)
                case 'regression', field='Regr';
                case 'multiclass', field='MultiClass';
                otherwise, field='BinClass';
            end
            ok=isfield(GD,field)&&~isempty(GD.(field)); if ~ok,reason=sprintf('Model source does not contain %s.',field);end
        end

        function [ok, GD, info, msg] = resultGDForSpec(NM, idx, resultType, spec)
            % resultGDForSpec  Resolve the training/CV result container from the model-source authority.
            ok=false; GD=[]; info=struct('id','','label','','kind','','index',NaN,'isMeta',false); msg='';
            A=NM.analysis{idx}; sources=NMResultsViewerTools.modelSourcesForAnalysis(NM,idx,resultType,spec);
            if isempty(sources)
                GD=NMResultsViewerTools.primaryGDdims(A);
                [ok,msg]=NMResultsViewerTools.performanceModelSourceAvailable(GD,resultType);
                return;
            end
            selected=NMResultsViewerTools.selectedModelSourceId(sources,spec);
            [ok,GD,info,msg]=NMResultsViewerTools.modelGDFromSource(A,sources,selected);
        end

        function [ok, reason] = modelOptimizationSourceBaseAvailable(GD)
            % modelOptimizationSourceBaseAvailable  Admit a produced modality optimization result.
            ok = ~isempty(GD);
            if ok,reason='';else,reason='The modality did not produce an optimization result.';end
        end

        function [ok, reason] = modelOptimizationMetaSourceAvailable(META)
            % modelOptimizationMetaSourceAvailable  Admit the writer-conditioned META optimization summary.
            ok = ~isempty(META);
            if ok,reason='';else,reason='The analysis did not produce a META optimization summary.';end
        end

        function label = modelSourceModalityLabel(~, A, idx)
            % modelSourceModalityLabel  Use the descriptor copied into GDdims by nk_MLOptimizerPrep.
            label=sprintf('Modality #%d',idx);
            desc=A.GDdims{idx}.datadescriptor.desc;
            if ~isempty(desc),label=sprintf('Modality #%d: %s',idx,desc);end
        end

        function selected = selectedModelSourceId(sources, spec)
            % selectedModelSourceId  Resolve the explicit source id or the first enabled source.
            selected='';
            if isempty(sources),return;end
            requested=spec.modelSource;
            if ~isempty(requested)
                hit=find(strcmp({sources.id},requested),1,'first');
                if isempty(hit),error('NMResultsViewerTools:InvalidModelSource','Model source %s is not defined for the selected scientific context.',requested);end
                if ~sources(hit).enabled,error('NMResultsViewerTools:InvalidModelSource','Model source %s is unavailable: %s',requested,sources(hit).reason);end
                selected=sources(hit).id;
                return;
            end
            hit=find([sources.enabled],1,'first');
            if isempty(hit),hit=1;end
            selected=sources(hit).id;
        end

        function [ok, GD, info, msg] = modelGDFromSource(A, sources, selectedSource)
            % modelGDFromSource  Resolve the selected produced GDdims/META object.
            hit=find(strcmp({sources.id},selectedSource),1,'first');
            if isempty(hit)
                error('NMResultsViewerTools:InvalidModelSource','Selected model source %s is not in the source catalogue.',selectedSource);
            end
            source=sources(hit);
            info=struct('id',source.id,'label',source.label,'kind',source.kind,'index',source.index,'isMeta',strcmp(source.kind,'meta'));
            if ~source.enabled
                ok=false;
                GD=[];
                msg=source.reason;
                return;
            end
            if info.isMeta,GD=A.META;else,GD=A.GDdims{source.index};end
            ok=true;
            msg='';
        end

        function n = modelOptimizationBinaryClassifierCount(GD, modeflag)
            % modelOptimizationBinaryClassifierCount  Count writer-produced binary decomposition results.
            if strcmp(modeflag,'regression'),n=0;else,n=numel(GD.BinClass);end
        end

        function view = emptySequenceDiagnosticView()
            % Browser-only projection; native ALLPARAM remains in the existing result containers.
            view = struct('available',false,'metrics',struct('id',{},'label',{},'group',{},'unit',{}), ...
                'records',struct([]));
        end

        function view = sequenceDiagnosticView(NM, analysisIndex, context)
            % Use grid-owned CV2 means/SDs and sequence-grouped OOCV summaries.
            A = NM.analysis{analysisIndex};
            view = NMResultsViewerTools.emptySequenceDiagnosticView();
            ids = {'sens','spec','FPR','PPV','pLR','percentReached','targetPrevalenceReached', ...
                'acc','BAC','NPV','nLR','MCC','Fscore','Youden','PSI','AUC','nReached','nTerminal'};
            labels = {'Sensitivity','Specificity','False-positive rate','Positive predictive value', ...
                'Positive likelihood ratio','Cases reaching examination','Target prevalence in remaining cases', ...
                'Accuracy','Balanced accuracy','Negative predictive value','Negative likelihood ratio', ...
                'Matthews correlation','F-score','Youden index','Predictive summary index', ...
                'Area under ROC','Cases reaching examination (N)','Terminal cases (N)'};
            groups = {'performance','performance','performance','performance','performance', ...
                'propagation','yield','performance','performance','performance','performance', ...
                'performance','performance','performance','performance','performance', ...
                'propagation','propagation'};
            units = {'%','%','%','%','ratio','%','%','%','%','%','ratio', ...
                'coefficient','fraction','index','percentage points','fraction','count','count'};
            view.metrics = struct('id',ids,'label',labels,'group',groups,'unit',units);
            if context.isMeta, return; end
            G = A.GDdims{context.modalityIndex}.grid;
            [found,metricPositions] = ismember(ids,G.SeqDiagnosticMetricNames);
            assert(all(found),'NMResultsViewerTools:SequenceMetricAxis', ...
                'SEQOPT grid is missing a required diagnostic metric.');
            records = struct([]);
            sources = A.params.TrainParam.STACKING.sel_anal;
            nMetrics = numel(ids);
            for comb = 1:size(G.mean_SeqDiagnostics,1)
                cols = G.SeqDiagnosticSequenceCols{comb,context.classifierIndex,context.targetIndex};
                if isempty(cols), continue; end
                n = numel(cols);
                means = reshape(G.mean_SeqDiagnostics( ...
                    comb,1:n,context.classifierIndex,1,context.targetIndex,metricPositions),[n nMetrics]);
                stds = reshape(G.se_SeqDiagnostics( ...
                    comb,1:n,context.classifierIndex,1,context.targetIndex,metricPositions),[n nMetrics]);
                R = NMResultsViewerTools.sequenceDiagnosticSummaryRecord( ...
                    cols,means,stds,ids,sources,NM);
                R.scope='CV2'; R.combination=comb; R.cohort=0;
                records = [records R]; %#ok<AGROW>
            end
            % OOCV result ownership exists only after successful application.
            if isfield(A,'OOCV') % nm2-allow: nk_OOCV conditionally creates analysis-local OOCV results at application.
                for o = 1:numel(A.OOCV)
                    cohort = A.OOCV{o};
                    if isempty(cohort) || isempty(cohort.BinResults), continue; end
                    bin = cohort.BinResults{context.targetIndex};
                    if isempty(bin), continue; end
                    [found,oocvPositions] = ismember(ids,bin.SeqDiagnosticMetricNames);
                    assert(all(found),'NMResultsViewerTools:OOCVSequenceMetricAxis', ...
                        'OOCV results are missing a required diagnostic metric.');
                    summaries = bin.SeqDiagnosticSummary{context.classifierIndex};
                    for j = 1:numel(summaries)
                        S = summaries(j);
                        R = NMResultsViewerTools.sequenceDiagnosticSummaryRecord( ...
                            S.sequenceCols,S.mean(:,oocvPositions), ...
                            S.sd(:,oocvPositions),ids,sources,NM);
                        R.scope='OOCV'; R.combination=0; R.cohort=o;
                        R.nModels=S.nModels;R.nPartitions=S.nPartitions;
                        records = [records R]; %#ok<AGROW>
                    end
                end
            end
            view.records = records;
            view.available = ~isempty(records);
        end

        function choices = sequenceCandidateChoices(metrics,grid,criterionCode)
            % Rank complete CV2 grid rows only; no OOCV test outcome enters selection.
            catalog=NMLearnerLibrary.criterionCatalog();
            criterion=catalog([catalog.code]==criterionCode);
            cv=metrics(strcmp({metrics.id},'cv_performance'));
            selection=metrics(strcmp({metrics.id},'selection_frequency'));
            complexity=metrics(strcmp({metrics.id},'complexity'));
            assert(isscalar(cv)&&isscalar(selection)&&isscalar(complexity)&&isscalar(criterion), ...
                'NMResultsViewerTools:SequenceCandidateAuthority','SEQOPT candidate ranking requires canonical CV1, frequency, complexity and criterion metadata.');
            n=grid.nCombinations;
            score=cv.values(:,1);freq=selection.values(:,1);cost=complexity.values(:,1);
            % nm2-allow: Writer-produced CV1 criterion frequency and complexity metrics must have identical complete hyperparameter-grid axes.
            assert(numel(score)==n&&numel(freq)==n&&numel(cost)==n, ...
                'NMResultsViewerTools:SequenceCandidateAxis','SEQOPT candidate measures must share the grid-row axis.');
            if strcmp(criterion.direction,'maximize'),rankScore=score;else,rankScore=-score;end
            rankScore(~isfinite(rankScore))=-Inf;
            freq(~isfinite(freq))=-Inf;
            cost(~isfinite(cost))=Inf;
            [~,winner]=max(rankScore);[~,popular]=max(freq);[~,simplest]=min(cost);
            if ~isfinite(rankScore(winner))
                error('NMResultsViewerTools:SequenceCandidateUnavailable', ...
                    'SEQOPT has no finite CV1 optimization criterion for candidate ranking.');
            end
            if ~isfinite(freq(popular)),popular=NaN;end
            if ~isfinite(cost(simplest)),simplest=NaN;end
            choices=struct('winner',winner,'mostSelected',popular,'leastComplex',simplest, ...
                'criterionDirection',criterion.direction,'rows',{grid.parameterRows});
        end

        function record = sequenceDiagnosticSummaryRecord(sequence,means,stds,ids,sources,NM)
            % Project one already-aggregated, ordered examination series.
            names = arrayfun(@(j)NM.analysis{sources(j)}.id, ...
                sequence,'UniformOutput',false);
            vals = struct(); sdVals = struct();
            for j=1:numel(ids)
                vals.(ids{j}) = means(:,j)';
                sdVals.(ids{j}) = stds(:,j)';
            end
            record = struct('scope','','combination',0,'cohort',0, ...
                'sequenceCols',sequence,'sourceNames',{names}, ...
                'nStages',numel(sequence),'nModels',NaN,'nPartitions',NaN, ...
                'values',vals,'sd',sdVals);
        end

        function metrics = buildModelOptimizationMetrics(GD, A, context)
            % buildModelOptimizationMetrics  Project writer-defined optimization measures into the fixed registry.
            if context.isMeta
                metrics = NMResultsViewerTools.buildMetaModelOptimizationMetrics(GD, context);
            elseif context.isMultiClass
                metrics = NMResultsViewerTools.buildMultiClassModelOptimizationMetrics(GD.grid, context);
            else
                metrics = NMResultsViewerTools.buildBinaryModelOptimizationMetrics(GD.grid, context);
                if strcmp(A.params.TrainParam.SVM.prog,'SEQOPT')
                    nodeCount = size(GD.grid.mean_SeqPerfGains,2);
                    names = arrayfun(@(k)sprintf('Examination %d',k),1:nodeCount,'UniformOutput',false);
                    metric = NMResultsViewerTools.metricFromGridFields(GD.grid, context, ...
                        'sequence_node_performance', 'Sequence performance by examination', ...
                        'sequence_optimization', {'mean_SeqPerfGains'}, {'se_SeqPerfGains'}, names, ...
                        'CV2-test performance at examination stage', '', true, false, false, '', 'sequence');
                    metric.supportsScatter = false;
                    metric.plotKind = 'sequence_curve';
                    metrics(end+1) = metric;
                end
            end
        end

        function metrics = buildBinaryModelOptimizationMetrics(grid, context)
            % buildBinaryModelOptimizationMetrics  Map binary/regression grid fields written by nk_MLOptimizer.
            tmpl = NMResultsViewerTools.modelOptimizationMetricTemplate();
            metrics = repmat(tmpl, 1, 8);
            metrics(1) = NMResultsViewerTools.metricFromGridFields(grid, context, 'cv_performance', 'Cross-validation performances', 'performance', ...
                {'mean_CVPerf','mean_TSPerf'}, {'se_CVPerf','se_TSPerf'}, {'CV1 test performance','CV2 test performance'}, ...
                'CV1/CV2-test performance', '', true, false, true, 'cv_performance','standard');
            metrics(2) = NMResultsViewerTools.metricFromGridFields(grid, context, 'generalization_error', 'Generalization error', 'generalization_gap', ...
                {'mean_Err_CVTSPerf'}, {'se_Err_CVTSPerf'}, {'Generalization error'}, ...
                'Generalization error [CV1-test - CV2-test]', '', false, true, true, 'error','standard');
            metrics(3) = NMResultsViewerTools.metricFromGridFields(grid, context, 'complexity', 'Model complexity', 'complexity', ...
                {'mean_Complexity'}, {'se_Complexity'}, {'Model complexity'}, ...
                'Model complexity', '', false, true, true, 'complexity','standard');
            metrics(4) = NMResultsViewerTools.metricFromGridFields(grid, context, 'diversity', 'Ensemble diversity', 'diversity', ...
                {'mean_CVDiversity','mean_TsDiversity'}, {'se_CVDiversity','se_TsDiversity'}, {'CV ensemble diversity','Test ensemble diversity'}, ...
                'Binary ensemble entropy', '', false, false, false, '','standard');
            metrics(5) = NMResultsViewerTools.metricFromGridFields(grid, context, 'selection_frequency', 'Model selection frequency', 'selection_frequency', ...
                {'SelNodeFreq'}, {}, {'Selection frequency'}, ...
                'Parameter selection frequency [%]', '%', false, false, false, '','standard');
            metrics(6) = NMResultsViewerTools.metricFromGridFields(grid, context, 'sequence_gain', 'Overall sequence gain', 'sequence_optimization', ...
                {'mean_SeqGain'}, {'se_SeqGain'}, {'Sequence gain'}, ...
                'CV1-test performance gain', '', true, false, false, '','standard');
            metrics(7) = NMResultsViewerTools.metricFromGridFields(grid, context, 'sequence_exam_frequency', 'Examination frequencies', 'sequence_optimization', ...
                {'mean_SeqExamFreq'}, {'se_SeqExamFreq'}, {'Examination frequency'}, ...
                'Examination frequencies [%]', '%', false, false, false, '', 'sequence');
            metrics(8) = NMResultsViewerTools.metricFromGridFields(grid, context, 'sequence_thresholds', 'Case propagation thresholds', 'sequence_optimization', ...
                {'mean_SeqPercUpper','mean_SeqPercLower'}, {'se_SeqPercUpper','se_SeqPercLower'}, {'Upper propagation threshold','Lower propagation threshold'}, ...
                'Case propagation thresholds', '', false, false, false, '', 'thresholds');
            % Each persisted examination/transition is one plotted series.
            nNodes=size(metrics(7).values,2);
            metrics(7).seriesLabels=arrayfun(@(k)sprintf('Node %d',k),1:nNodes,'UniformOutput',false);
            nTransitions=size(metrics(8).values,2)/2;
            metrics(8).seriesLabels=[ ...
                arrayfun(@(k)sprintf('Upper threshold: node %d to %d',k,k+1),1:nTransitions,'UniformOutput',false), ...
                arrayfun(@(k)sprintf('Lower threshold: node %d to %d',k,k+1),1:nTransitions,'UniformOutput',false)];
        end

        function metrics = buildMultiClassModelOptimizationMetrics(grid, context)
            % buildMultiClassModelOptimizationMetrics  Map multi-group grid fields written by nk_MLOptimizer.
            tmpl = NMResultsViewerTools.modelOptimizationMetricTemplate();
            metrics = repmat(tmpl, 1, 5);
            metrics(1) = NMResultsViewerTools.metricFromGridFields(grid, context, 'multiclass_cv_performance', 'Multi-class cross-validation performance', 'performance', ...
                {'MultiCVPerf','MultiTSPerf'}, {'seMultiCVPerf','seMultiTSPerf'}, {'Multi-class CV1 test performance','Multi-class CV2 test performance'}, ...
                'Multi-class CV1/CV2-test performance', '', true, false, true, 'cv_performance', 'multiclass');
            metrics(2) = NMResultsViewerTools.metricFromGridFields(grid, context, 'multiclass_generalization_error', 'Multi-class generalization error', 'generalization_gap', ...
                {'MultiERR_CVTSPerf'}, {'seMultiERR_CVTSPerf'}, {'Multi-class generalization error'}, ...
                'Multi-group generalization error [CV1-test - CV2-test]', '', false, true, true, 'error', 'multiclass');
            metrics(3) = NMResultsViewerTools.metricFromGridFields(grid, context, 'multiclass_complexity', 'Multi-class complexity', 'complexity', ...
                {'MultiComplexity'}, {'seMultiComplexity'}, {'Multi-class complexity'}, ...
                'Average model complexity [%]', '%', false, true, true, 'complexity', 'multiclass');
            metrics(4) = NMResultsViewerTools.metricFromGridFields(grid, context, 'multiclass_diversity', 'Multi-class ensemble diversity', 'diversity', ...
                {'MultiCVDiversity','MultiTsDiversity'}, {'seMultiCVDiversity','seMultiTsDiversity'}, {'Multi-class CV ensemble diversity','Multi-class test ensemble diversity'}, ...
                'Multi-class ensemble entropy', '', false, false, false, '', 'multiclass');
            metrics(5) = NMResultsViewerTools.metricFromGridFields(grid, context, 'multiclass_selection_frequency', 'Multi-class model selection frequency', 'selection_frequency', ...
                {'MultiSelNodeFreq'}, {}, {'Multi-class selection frequency'}, ...
                'Multi-class parameter selection frequency [%]', '%', false, false, false, '', 'multiclass_percent');
        end

        function metrics = buildMetaModelOptimizationMetrics(META, context)
            % buildMetaModelOptimizationMetrics  Map the META summary fields written by nk_MLOptimizerMeta.
            tmpl = NMResultsViewerTools.modelOptimizationMetricTemplate();
            if context.isMultiClass
                metrics = repmat(tmpl, 1, 2);
                metrics(1) = NMResultsViewerTools.metaCvMetric(META, context, true);
                metrics(2) = NMResultsViewerTools.metaGeneralizationMetric(META, context, true);
            else
                metrics = repmat(tmpl, 1, 3);
                metrics(1) = NMResultsViewerTools.metaCvMetric(META, context, false);
                metrics(2) = NMResultsViewerTools.metaGeneralizationMetric(META, context, false);
                metrics(3) = NMResultsViewerTools.metaComplexityMetric(META, context);
            end
        end

        function metric = metaCvMetric(META, context, isMulti)
            % metaCvMetric  Build the produced META cross-validation summary.
            metric = NMResultsViewerTools.modelOptimizationMetricTemplate();
            metric.family = 'performance';
            metric.higherIsBetter = true;
            metric.lowerIsBetter = false;
            metric.supportsPanel = true;
            metric.supportsScatter = true;
            metric.supportsPartitionHeatmap = false;
            metric.partitionField = '';
            metric.unit = '';
            metric.xLabel = 'Unimodal source index';
            metric.plotKind = 'bar';
            if isMulti
                metric.id = 'meta_multiclass_cv_summary';
                metric.label = 'Multi-class cross-validation performance summary';
                metric.yLabel = 'Multi-class CV1/CV2 performance';
                metric.sourceFields = {'best_MultiCVperf_unimodal','best_MultiTSperf_unimodal','MultiClass'};
                cv = NMResultsViewerTools.metaMetricColumn(META, 'best_MultiCVperf_unimodal', context, true);
                ts = NMResultsViewerTools.metaMetricColumn(META, 'best_MultiTSperf_unimodal', context, true);
                ref = NMResultsViewerTools.metaMultiClassReference(META, context, size(cv,1));
                metric.seriesLabels = {'Multi-class CV1 test performance (unimodal)','Multi-class CV2 test performance (unimodal)','Multi-class CV2 performance (bagged/META)'};
            else
                metric.id = 'meta_cv_summary';
                metric.label = 'Cross-validation performance summary';
                metric.yLabel = 'CV1/CV2 performance';
                metric.sourceFields = {'best_CVperf_unimodal','best_TSperf_unimodal','best_TSperf_multimodal'};
                cv = NMResultsViewerTools.metaMetricColumn(META, 'best_CVperf_unimodal', context, false);
                ts = NMResultsViewerTools.metaMetricColumn(META, 'best_TSperf_unimodal', context, false);
                ref = NMResultsViewerTools.metaRepeatedReference(META, 'best_TSperf_multimodal', context, size(cv,1));
                metric.seriesLabels = {'CV1 test performance (unimodal)','CV2 test performance (unimodal)','CV2 performance (bagged/META)'};
            end
            metric = NMResultsViewerTools.metaFinalizeMetric(metric, {cv, ts, ref});
        end

        function metric = metaGeneralizationMetric(META, context, isMulti)
            % metaGeneralizationMetric  Build the produced META generalization-error summary.
            metric = NMResultsViewerTools.modelOptimizationMetricTemplate();
            metric.family = 'generalization_gap';
            metric.higherIsBetter = false;
            metric.lowerIsBetter = true;
            metric.supportsPanel = true;
            metric.supportsScatter = true;
            metric.supportsPartitionHeatmap = false;
            metric.partitionField = '';
            metric.unit = '';
            metric.xLabel = 'Unimodal source index';
            metric.plotKind = 'bar';
            if isMulti
                metric.id = 'meta_multiclass_generalization_error_summary';
                metric.label = 'Multi-class generalization error summary';
                metric.yLabel = 'Multi-group generalization error [CV1 - CV2]';
                metric.seriesLabels = {'Multi-class generalization error'};
                metric.sourceFields = {'best_MultiCVperf_unimodal','best_MultiTSperf_unimodal'};
                cv = NMResultsViewerTools.metaMetricColumn(META, 'best_MultiCVperf_unimodal', context, true);
                ts = NMResultsViewerTools.metaMetricColumn(META, 'best_MultiTSperf_unimodal', context, true);
                metric = NMResultsViewerTools.metaFinalizeMetric(metric, {cv-ts});
            else
                metric.id = 'meta_generalization_error_summary';
                metric.label = 'Generalization error summary';
                metric.yLabel = 'Generalization error [CV1 - CV2]';
                metric.seriesLabels = {'Generalization error'};
                metric.sourceFields = {'best_Error_unimodal'};
                metric = NMResultsViewerTools.metaFinalizeMetric(metric, ...
                    {NMResultsViewerTools.metaMetricColumn(META, 'best_Error_unimodal', context, false)});
            end
        end

        function metric = metaComplexityMetric(META, context)
            % metaComplexityMetric  Build the produced META model-complexity summary.
            metric = NMResultsViewerTools.modelOptimizationMetricTemplate();
            metric.id = 'meta_complexity_summary';
            metric.label = 'Model complexity summary';
            metric.family = 'complexity';
            metric.yLabel = 'Model complexity';
            metric.xLabel = 'Unimodal source index';
            metric.unit = '';
            metric.higherIsBetter = false;
            metric.lowerIsBetter = true;
            metric.supportsPanel = true;
            metric.supportsScatter = true;
            metric.supportsPartitionHeatmap = false;
            metric.partitionField = '';
            metric.plotKind = 'bar';
            metric.seriesLabels = {'Model complexity'};
            metric.sourceFields = {'best_Complexity_unimodal'};
            metric = NMResultsViewerTools.metaFinalizeMetric(metric, ...
                {NMResultsViewerTools.metaMetricColumn(META, 'best_Complexity_unimodal', context, false)});
        end

        function metric = metaFinalizeMetric(metric, parts)
            % metaFinalizeMetric  Concatenate META vectors on their shared writer-defined source axis.
            rowCounts=cellfun(@(part)size(part,1),parts);
            if any(rowCounts ~= rowCounts(1))
                error('NMResultsViewerTools:InvalidMetaOptimizationAxis', ...
                    'META optimization fields do not share one unimodal-source axis.');
            end
            values=[parts{:}];
            if ~any(isfinite(values(:)))
                metric.available = false;
                metric.supportsPanel = false;
                metric.supportsScatter = false;
                metric.missingReason = sprintf('META field(s) contain no finite values: %s.', strjoin(metric.sourceFields, ', '));
                return;
            end
            metric.values = values;
            metric.sem = [];
            metric.available = true;
        end

        function metric = metricFromGridFields(grid, context, id, label, family, valueFields, semFields, seriesLabels, yLabel, unit, higherIsBetter, lowerIsBetter, supportsPartitionHeatmap, partitionField, sliceMode)
            % metricFromGridFields  Project one writer-defined grid-field family into a metric descriptor.
            metric = NMResultsViewerTools.modelOptimizationMetricTemplate();
            metric.id = id;
            metric.label = label;
            metric.family = family;
            metric.seriesLabels = seriesLabels;
            metric.yLabel = yLabel;
            metric.unit = unit;
            metric.higherIsBetter = logical(higherIsBetter);
            metric.lowerIsBetter = logical(lowerIsBetter);
            metric.supportsPanel = true;
            metric.supportsScatter = true;
            metric.supportsPartitionHeatmap = logical(supportsPartitionHeatmap);
            metric.partitionField = partitionField;
            metric.sourceFields = [valueFields(:)' semFields(:)'];
            missingValues = NMResultsViewerTools.missingFieldNames(grid, valueFields);
            if ~isempty(missingValues)
                metric.available = false;
                metric.supportsPanel = false;
                metric.supportsScatter = false;
                metric.supportsPartitionHeatmap = false;
                metric.missingReason = sprintf('Measure was not produced: %s.', strjoin(missingValues, ', '));
                return;
            end
            values = NMResultsViewerTools.metricMatricesFromFields(grid, valueFields, context, sliceMode);
            if strcmp(sliceMode, 'thresholds')
                % nm2-allow: nk_MLOptimizer writes paired upper/lower SEQOPT threshold series on equal examination axes.
                if mod(size(values,2),2) ~= 0
                    error('NMResultsViewerTools:InvalidSequenceThresholdAxis','SEQOPT threshold fields do not form paired upper/lower series.');
                end
                nHalf=size(values,2)/2;
                values(:,nHalf+1:end)=-values(:,nHalf+1:end);
            elseif strcmp(sliceMode, 'multiclass_percent')
                values=values.*100;
                metric.unitTransform='fraction_to_percent';
            end
            metric.values = values;
            missingSem = NMResultsViewerTools.missingFieldNames(grid, semFields);
            if isempty(semFields)
                metric.sem = [];
            elseif isempty(missingSem)
                sem = NMResultsViewerTools.metricMatricesFromFields(grid, semFields, context, sliceMode);
                if strcmp(sliceMode, 'thresholds')
                    nHalf=size(sem,2)/2;
                    sem(:,nHalf+1:end)=-sem(:,nHalf+1:end);
                elseif strcmp(sliceMode, 'multiclass_percent')
                    sem=sem.*100;
                end
                metric.sem = sem;
            else
                metric.sem = [];
                metric.missingReason = sprintf('Uncertainty field(s) were not produced: %s. Values remain available.', strjoin(missingSem, ', '));
            end
            metric.available = true;
        end

        function mats = metricMatricesFromFields(grid, fields, context, sliceMode)
            % metricMatricesFromFields  Concatenate grid fields on their common parameter-combination axis.
            parts = cell(1, numel(fields));
            rowCounts = zeros(1, numel(fields));
            for ii = 1:numel(fields)
                parts{ii} = NMResultsViewerTools.metricMatrixFromRaw(grid.(fields{ii}), context, sliceMode);
                rowCounts(ii) = size(parts{ii},1);
            end
            if any(rowCounts ~= rowCounts(1))
                error('NMResultsViewerTools:InvalidOptimizationGridAxis', ...
                    'Optimization grid fields do not share one parameter-combination axis.');
            end
            mats=[parts{:}];
        end

        function mat = metricMatrixFromRaw(raw, context, sliceMode)
            % metricMatrixFromRaw  Slice nk_MLOptimizer grid arrays using their persisted dimensions.
            arr=double(raw);
            switch sliceMode
                case {'sequence','thresholds'}
                    val=arr(:,:,context.classifierIndex,:,context.targetIndex);
                case {'multiclass','multiclass_percent'}
                    val=arr(:,:,context.targetIndex);
                otherwise
                    val=arr(:,context.classifierIndex,:,context.targetIndex);
            end
            mat=reshape(val,size(val,1),[]);
        end

        function missing = missingFieldNames(s, names)
            % missingFieldNames  Return writer-conditioned measure fields that were not produced.
            if isempty(names),missing={};return;end
            present=fieldnames(s);
            missing=names(~ismember(names,present));
        end

        function col = metaMetricColumn(META, field, context, isMulti)
            % metaMetricColumn  Slice the nk_MLOptimizerMeta unimodal-source-by-classifier matrix.
            arr=double(META.(field));
            if isMulti,col=arr(:);else,col=arr(:,context.classifierIndex);end
        end

        function ref = metaRepeatedReference(META, field, context, nRows)
            % metaRepeatedReference  Expand the produced bagged classifier reference across source rows.
            value=double(META.(field)(context.classifierIndex));
            ref=repmat(value,nRows,1);
        end

        function ref = metaMultiClassReference(META, context, nRows)
            % metaMultiClassReference  Use the criterion-specific multi-group reference written by nk_MultiPerfComp.
            if context.criterionCode==14,value=double(META.MultiClass.BAC(1));else,value=double(META.MultiClass.accuracy);end
            ref=repmat(value,nRows,1);
        end

        function grid = normalizeMetaModelOptimizationGrid(~, ~, nHint)
            % normalizeMetaModelOptimizationGrid  Build the META unimodal-source axis from the materialized metric rows.
            grid = NMResultsViewerTools.emptyModelOptimizationGrid();
            nRows=round(double(nHint));
            if nRows < 1
                grid.message = 'META optimization summary has no materialized source rows.';
                return;
            end
            grid.ok = true;
            grid.message = '';
            grid.nCombinations = nRows;
            grid.index = 1:nRows;
            grid.parameterNames = {};
            tmpl = struct('index',0,'label','','values',{{}},'tooltip','');
            rows = repmat(tmpl, 1, nRows);
            labels = cell(1, nRows);
            for ii = 1:nRows
                rows(ii).index = ii;
                rows(ii).label = sprintf('U%d', ii);
                rows(ii).values = {};
                rows(ii).tooltip = sprintf('META/bagged unimodal source %d', ii);
                labels{ii} = rows(ii).label;
            end
            grid.labels = labels;
            grid.parameterRows = rows;
            grid.parameterValues = {rows.values};
        end

        function grid = normalizeModelOptimizationGrid(GD, context, nHint)
            % normalizeModelOptimizationGrid  Project GDdims.Model parameter metadata on the persisted model axis.
            if context.isMeta
                grid = NMResultsViewerTools.normalizeMetaModelOptimizationGrid(GD, context, nHint);
                return;
            end
            grid=NMResultsViewerTools.emptyModelOptimizationGrid();
            ML=GD.Model;
            clsIdx=context.classifierIndex;
            if context.isMultiClass,clsIdx=1;end
            nModel=double(ML.NumParamCombs(clsIdx));
            paramCombs=ML.ParamCombs{clsIdx};
            paramDesc=ML.ParamDesc{clsIdx};
            nRows=size(paramCombs,1);
            % nm2-allow: nk_MLOptimizer writes NumParamCombs from the same ParamCombs classifier axis.
            if nRows ~= nModel
                error('NMResultsViewerTools:InvalidOptimizationParameterAxis', ...
                    'Model.NumParamCombs=%d but Model.ParamCombs contains %d rows.',nModel,nRows);
            end
            if nHint > 0 && nHint ~= nRows
                error('NMResultsViewerTools:InvalidOptimizationMetricAxis', ...
                    'Optimization metric axis has %d rows but Model.ParamCombs has %d.',nHint,nRows);
            end
            grid.ok=true;
            grid.message='';
            grid.nCombinations=nRows;
            grid.index=1:nRows;
            grid.parameterNames=paramDesc;
            tmpl=struct('index',0,'label','','values',{{}},'tooltip','');
            rows=repmat(tmpl,1,nRows);
            labels=cell(1,nRows);
            for ii=1:nRows
                rows(ii).index=ii;
                rows(ii).label=sprintf('M%d',ii);
                rows(ii).values=NMResultsViewerTools.paramCombinationValues(paramCombs,ii);
                rows(ii).tooltip=NMResultsViewerTools.paramCombinationTooltip(rows(ii).values,paramDesc,rows(ii).label);
                labels{ii}=rows(ii).label;
            end
            grid.labels=labels;
            grid.parameterRows=rows;
            grid.parameterValues={rows.values};
        end

        function values = paramCombinationValues(paramCombs, rowIdx)
            % paramCombinationValues  Serialize one allcomb2 parameter row for display.
            % nm2-allow: nk_MLOptimizer allcomb2 output may be homogeneous numeric or heterogeneous cell ParamCombs.
            if iscell(paramCombs),raw=paramCombs(rowIdx,:);else,raw=num2cell(paramCombs(rowIdx,:));end
            values=cell(1,numel(raw));
            for ii=1:numel(raw),values{ii}=NMResultsViewerTools.valueToText(raw{ii});end
        end

        function txt = paramCombinationTooltip(values, names, fallbackLabel)
            % paramCombinationTooltip  Join writer-defined parameter names and one parameter row.
            if isempty(names),txt=fallbackLabel;return;end
            % nm2-allow: nk_MLOptimizer ParamDesc and ParamCombs must share the parameter-column axis when descriptors exist.
            if numel(names) ~= numel(values)
                error('NMResultsViewerTools:InvalidOptimizationParameterDescriptionAxis', ...
                    'Model.ParamDesc has %d names for %d parameter values.',numel(names),numel(values));
            end
            parts=cell(1,numel(values));
            for ii=1:numel(values),parts{ii}=sprintf('%s: %s',names{ii},values{ii});end
            txt=strjoin(parts,'; ');
        end

        function txt = valueToText(v)
            % valueToText  Serialize one persisted parameter value without changing its optimization semantics.
            % nm2-allow: nk_MLOptimizer ParamCombs cells contain textual or numeric allcomb2 parameter values at this display boundary.
            if ischar(v)
                txt=v;
                return;
            end
            flat=double(v(:));
            if isscalar(flat)
                txt=NMResultsViewerTools.formatNumber(flat);
                return;
            end
            n=min(numel(flat),5);
            cells=cell(1,n);
            for ii=1:n,cells{ii}=NMResultsViewerTools.formatNumber(flat(ii));end
            txt=['[' strjoin(cells,', ')];
            if numel(flat)>n,txt=[txt ', ...'];end
            txt=[txt ']'];
        end

        function partitions = buildModelOptimizationPartitions(GD, ~, context)
            % buildModelOptimizationPartitions  Extract the writer-defined CV2 partition matrices.
            partitions = NMResultsViewerTools.emptyModelOptimizationPartitions();
            partitions.ok = true;
            if context.isMeta
                partitions.message='';
                return;
            end
            targetIdx=context.targetIndex;
            clsIdx=context.classifierIndex;
            if context.isMultiClass
                cv1=GD.multi_bestTR(:,:,targetIdx);
                cv2=GD.multi_bestTS(:,:,targetIdx);
                partitions.cv1=NMResultsViewerTools.partitionMatrixStruct(cv1,'Mean CV1 Performance at CV2 partition level','Performance');
                partitions.cv2=NMResultsViewerTools.partitionMatrixStruct(cv2,'Mean CV2 Performance at CV2 partition level','Performance');
                complexity=NMResultsViewerTools.multiClassComplexityPartition(GD,targetIdx);
                partitions.complexity=NMResultsViewerTools.partitionMatrixStruct(complexity,'Mean model complexity at CV2 partition level','Complexity');
                partitions.error=NMResultsViewerTools.partitionMatrixStruct(cv1-cv2,'Mean generalization error at CV2 partition level','Generalization error');
            else
                partitions.cv1=NMResultsViewerTools.partitionMatrixStruct(NMResultsViewerTools.partitionCellSlice(GD,'bestTR',clsIdx,targetIdx),'Mean CV1 Performance at CV2 partition level','Performance');
                partitions.cv2=NMResultsViewerTools.partitionMatrixStruct(NMResultsViewerTools.partitionCellSlice(GD,'bestTS',clsIdx,targetIdx),'Mean CV2 Performance at CV2 partition level','Performance');
                partitions.complexity=NMResultsViewerTools.partitionMatrixStruct(NMResultsViewerTools.partitionCellSlice(GD,'bestComplexity',clsIdx,targetIdx),'Mean model complexity at CV2 partition level','Complexity');
                partitions.error=NMResultsViewerTools.partitionMatrixStruct(NMResultsViewerTools.partitionCellSlice(GD,'bestError',clsIdx,targetIdx),'Mean generalization error at CV2 partition level','Generalization error');
            end
            partitions.availableForMetricIds={'cv_performance','multiclass_cv_performance','complexity','multiclass_complexity','generalization_error','multiclass_generalization_error'};
            partitions.message='';
        end

        function mat = partitionCellSlice(GD, fieldName, clsIdx, targetIdx)
            % partitionCellSlice  Slice classifier-indexed partition cells on the selected target axis.
            arr=double(GD.(fieldName){clsIdx});
            mat=squeeze(arr(:,:,targetIdx));
        end

        function mat = multiClassComplexityPartition(GD, targetIdx)
            % multiClassComplexityPartition  Average the binary complexity partitions exactly as load_GDdims does.
            stack=cat(4,GD.bestComplexity{:});
            avg=sum(stack,4)./numel(GD.bestComplexity);
            mat=squeeze(avg(:,:,targetIdx));
        end

        function S = partitionMatrixStruct(mat, titleText, valueLabel)
            % partitionMatrixStruct  Build a fixed-schema CV-partition matrix payload.
            S = struct('ok',false,'matrix',[],'title',titleText,'valueLabel',valueLabel,'min',NaN,'max',NaN,'message','Partition matrix is unavailable.');
            if isempty(mat),return;end
            S.matrix=double(mat);
            vals=S.matrix(isfinite(S.matrix));
            if ~isempty(vals),S.min=min(vals);S.max=max(vals);end
            S.ok=true;
            S.message='';
        end

        function comparisons = buildModelOptimizationComparisons(metrics)
            % buildModelOptimizationComparisons  Prepare paired-metric metadata for scatter and Pareto views.
            %
            % comparisons = NMResultsViewerTools.buildModelOptimizationComparisons(metrics)
            % derives same-grid metric pairs from the Stage 1 registry. It does not compute
            % scatter plots or Pareto frontiers; those remain later UI/backend stages.
            comparisons = NMResultsViewerTools.emptyModelOptimizationComparisons();
            available = NMResultsViewerTools.modelOptimizationMetricAvailableMask(metrics);
            ids = {metrics.id};
            ids = ids(available);
            defaultPairs = {'cv_performance','complexity'; 'cv_performance','generalization_error'; ...
                'cv_performance','diversity'; 'selection_frequency','cv_performance'; ...
                'multiclass_cv_performance','multiclass_complexity'; 'multiclass_cv_performance','multiclass_generalization_error'};
            pairTmpl = struct('xMetricId','','yMetricId','','label','','enabled',false,'reason','');
            nPairs = size(defaultPairs,1);
            pairs = repmat(pairTmpl, 1, nPairs);
            for ii = 1:nPairs
                xId = defaultPairs{ii,2};
                yId = defaultPairs{ii,1};
                pairs(ii).xMetricId = xId;
                pairs(ii).yMetricId = yId;
                pairs(ii).label = sprintf('%s vs %s', yId, xId);
                pairs(ii).enabled = any(strcmp(ids, xId)) && any(strcmp(ids, yId));
                if ~pairs(ii).enabled
                    pairs(ii).reason = 'One or both metrics are unavailable in the selected optimization registry.';
                end
            end
            comparisons.compatibleMetricPairs = pairs;
            comparisons.defaultPairs = pairs([pairs.enabled]);
            comparisons.rejectedPairs = pairs(~[pairs.enabled]);
        end

        function opts = modelOptimizationMeasureOptions(NM, idx, spec)
            % modelOptimizationMeasureOptions  Convert the fixed metric registry to selector options.
            tmpl = struct('index',1,'id','none','label','No model-optimization metrics','enabled',false,'reason','No model-optimization grid payload detected.');
            [~, reason, availability] = NMResultsViewerTools.modelOptimizationAvailability(NM, idx, spec);
            metrics = availability.metrics;
            if isempty(metrics),opts=tmpl;opts.reason=reason;return;end
            opts = repmat(tmpl, 1, numel(metrics));
            for ii = 1:numel(metrics)
                opts(ii).index = ii;
                opts(ii).id = metrics(ii).id;
                opts(ii).label = metrics(ii).label;
                opts(ii).enabled = logical(metrics(ii).available);
                opts(ii).reason = metrics(ii).missingReason;
            end
        end

        function opts = modelOptimizationClassifierOptions(NM, idx, spec)
            % modelOptimizationClassifierOptions  Build classifier choices from completed-analysis task/MULTI state.
            tmpl = struct('index',1,'label','Classifier 1','enabled',false,'reason','No classifier/model option detected.','resultType','','classCount',NaN);
            opts = tmpl([]);
            % nm2-allow: public classifier selector boundary validates the requested analysis index.
            if idx < 1 || idx > numel(NM.analysis),return;end
            A=NM.analysis{idx};
            sources=NMResultsViewerTools.modelSourcesForAnalysis(NM,idx,'model_optimization',spec);
            if isempty(sources),return;end
            selected=NMResultsViewerTools.selectedModelSourceId(sources,spec);
            [ok,GD]=NMResultsViewerTools.modelGDFromSource(A,sources,selected);
            if ~ok,return;end
            [~,modeflag]=NMResultsViewerTools.analysisLabelAndMode(NM,A);
            if strcmp(modeflag,'regression')
                opts=tmpl;
                opts.index=1;
                opts.label='Regression model';
                opts.enabled=true;
                opts.reason='';
                opts.resultType='regression';
                opts.classCount=0;
                return;
            end
            nBin=NMResultsViewerTools.modelOptimizationBinaryClassifierCount(GD,modeflag);
            hasMulti=logical(A.params.TrainParam.MULTI.flag);
            nOpts=nBin+double(hasMulti);
            opts=repmat(tmpl,1,nOpts);
            for ii=1:nBin
                opts(ii).index=ii;
                opts(ii).label=NMResultsViewerTools.classifierLabel(A,ii);
                opts(ii).enabled=true;
                opts(ii).reason='';
                opts(ii).resultType='classification';
                opts(ii).classCount=2;
            end
            if hasMulti
                groupNames=NMResultsViewerTools.groupNamesForAnalysis(NM,idx);
                opts(nBin+1).index=nBin+1;
                opts(nBin+1).label='Multi-group classifier';
                opts(nBin+1).enabled=true;
                opts(nBin+1).reason='';
                opts(nBin+1).resultType='multiclass';
                opts(nBin+1).classCount=numel(groupNames);
            end
        end

        function metrics = jsonSafeModelOptimizationMetrics(metrics)
            % jsonSafeModelOptimizationMetrics  Convert fixed numeric metric matrices into browser row cells.
            for ii=1:numel(metrics)
                metrics(ii).values=NMResultsViewerTools.jsonSafeNumericMatrixRows(metrics(ii).values);
                metrics(ii).sem=NMResultsViewerTools.jsonSafeNumericMatrixRows(metrics(ii).sem);
            end
        end

        function partitions = jsonSafeModelOptimizationPartitions(partitions)
            % jsonSafeModelOptimizationPartitions  Convert fixed partition matrices into browser row cells.
            fields={'cv1','cv2','complexity','error'};
            for ii=1:numel(fields)
                f=fields{ii};
                partitions.(f).matrix=NMResultsViewerTools.jsonSafeNumericMatrixRows(partitions.(f).matrix);
            end
        end

        function rows = jsonSafeNumericMatrixRows(mat)
            % jsonSafeNumericMatrixRows  Represent one numeric matrix as JSON-safe row cells.
            if isempty(mat),rows=mat;return;end
            mat=double(mat);
            rows=mat2cell(mat,ones(1,size(mat,1)),size(mat,2));
        end

        function rows = modelOptimizationSummaryRows(metrics)
            % modelOptimizationSummaryRows  Summarize fixed-registry availability and finite-value counts.
            rowTmpl=struct('metric','','value','','source','model_optimization_registry');
            if isempty(metrics),rows=rowTmpl([]);return;end
            rows=repmat(rowTmpl,1,numel(metrics));
            for ii=1:numel(metrics)
                rows(ii).metric=metrics(ii).label;
                if metrics(ii).available
                    rows(ii).value=sprintf('available (%d finite value(s))',sum(isfinite(metrics(ii).values(:))));
                else
                    rows(ii).value=metrics(ii).missingReason;
                end
            end
        end

        function rows = modelOptimizationParameterRows(grid, metrics)
            % modelOptimizationParameterRows  Build one summary row per canonical parameter combination.
            rowTmpl=struct('index',0,'label','','parameters','','firstMetric','','firstValue',NaN);
            if grid.nCombinations < 1,rows=rowTmpl([]);return;end
            n=grid.nCombinations;
            rows=repmat(rowTmpl,1,n);
            available=NMResultsViewerTools.modelOptimizationMetricAvailableMask(metrics);
            firstMetric=0;
            if any(available),firstMetric=find(available,1,'first');end
            for ii=1:n
                rows(ii).index=ii;
                rows(ii).label=grid.labels{ii};
                rows(ii).parameters=grid.parameterRows(ii).tooltip;
                if firstMetric>0
                    rows(ii).firstMetric=metrics(firstMetric).label;
                    rows(ii).firstValue=double(metrics(firstMetric).values(ii,1));
                end
            end
        end

        function n = modelOptimizationMetricRowCount(metrics)
            % modelOptimizationMetricRowCount  Return the shared materialized parameter-row extent.
            if isempty(metrics),n=0;return;end
            n=max([0,arrayfun(@(metric)size(metric.values,1),metrics)]);
        end

        function mask = modelOptimizationMetricAvailableMask(metrics)
            % modelOptimizationMetricAvailableMask  Return fixed-registry availability flags.
            mask=[metrics.available];
        end

        function ctx = emptyModelOptimizationContext()
            % emptyModelOptimizationContext  Create fixed-schema optimization context.
            ctx = struct('analysisIndex',0,'modalityIndex',NaN,'modelSource','','modelSourceLabel','', ...
                'targetIndex',1,'classifierIndex',1,'classifierLabel','','binaryClassifierCount',0, ...
                'modeflag','','modelFamily','','isMultiClass',false,'isMeta',false,'criterionCode',NaN, ...
                'metricBasis','','legacyMeasureSource','');
        end

        function grid = emptyModelOptimizationGrid()
            % emptyModelOptimizationGrid  Create fixed-schema parameter-grid payload.
            grid = struct('ok',false,'message','Parameter grid unavailable.','nCombinations',0, ...
                'index',[],'labels',{{}},'parameterNames',{{}},'parameterValues',{{}},'parameterRows',[]);
        end

        function metric = modelOptimizationMetricTemplate()
            % modelOptimizationMetricTemplate  Create one fixed-schema metric descriptor.
            metric = struct('id','','label','','family','','values',[],'sem',[], ...
                'seriesLabels',{{}},'yLabel','','xLabel','','unit','','higherIsBetter',false, ...
                'lowerIsBetter',false,'supportsPanel',false,'supportsScatter',false, ...
                'supportsPartitionHeatmap',false,'partitionField','','sourceFields',{{}}, ...
                'available',false,'missingReason','','unitTransform','none','plotKind','line');
        end

        function metrics = emptyModelOptimizationMetrics()
            % emptyModelOptimizationMetrics  Create empty fixed-schema metric registry.
            metrics = NMResultsViewerTools.modelOptimizationMetricTemplate();
            metrics = metrics([]);
        end

        function partitions = emptyModelOptimizationPartitions()
            % emptyModelOptimizationPartitions  Create fixed-schema partition payload.
            emptyMatrix = NMResultsViewerTools.partitionMatrixStruct([], '', '');
            partitions = struct('ok',false,'message','Partition payload unavailable.', ...
                'availableForMetricIds',{{}},'xLabel','Folds','yLabel','Permutations', ...
                'cv1',emptyMatrix,'cv2',emptyMatrix,'complexity',emptyMatrix,'error',emptyMatrix);
        end

        function comparisons = emptyModelOptimizationComparisons()
            % emptyModelOptimizationComparisons  Create fixed-schema comparison metadata.
            pairTmpl = struct('xMetricId','','yMetricId','','label','','enabled',false,'reason','');
            comparisons = struct('compatibleMetricPairs',pairTmpl([]),'defaultPairs',pairTmpl([]),'rejectedPairs',pairTmpl([]));
        end


        function profileLog(enabled, varargin)
            % profileLog  Emit Results Viewer backend timing diagnostics when enabled.
            if ~enabled, return; end
            fprintf(varargin{:});
        end

        function sources = emptyModelOptimizationSources()
            % emptyModelOptimizationSources  Create empty fixed-schema source descriptors.
            tmpl = struct('id','','label','','enabled',false,'reason','','kind','modality','index',NaN);
            sources = tmpl([]);
        end
    end
end

classdef NMResultsViewerReportTools
% NMResultsViewerReportTools
% -------------------------------------------------------------------------
% API-first, read-only report assembly for NM2 Results Viewer components.
%
% The report tools separate scientific payload construction from the browser
% DOM. Browser panels, MATLAB scripts, and future assistant/agent workflows can
% request the same component inventory, assemble a report specification, and
% build JSON-safe report payloads without depending on the currently visible
% viewspace. Report specifications are planned into a deterministic scientific
% order and may expand feature-inspection panels across authoritative modality
% and retained-component identities. A request-scoped execution cache prevents
% repeated payload extraction and probability conversion during one build. The
% report contract carries explicit feature-relation source scope and persisted relation identity
% through report specifications, cache keys, details tables, and shared renderers.
% -------------------------------------------------------------------------

    methods (Static)
        function [components, featurePlanCatalogue, reportContext, featurePresentationPayload] = listAvailableComponents(NM, spec, analysisSetState)
            % Purpose: Discover reportable components for the selected analysis while optionally appending set-level components for a fixed multi-analysis scope.
            % Syntax: [components,featurePlanCatalogue,reportContext,featurePresentationPayload] = NMResultsViewerReportTools.listAvailableComponents(NM,spec,analysisSetState)
            % Inputs: NM is read-only; spec supplies the ReportContext and current per-analysis Results Viewer selectors; optional analysisSetState is a previously queried authoritative Scientific State inventory for the same analysis set.
            % Outputs: Component catalogue for reportContext.SelectedAnalysisIndex, optional set-level cross-analysis components, feature-planning catalogue, normalized report context, and the same compact Feature Inspection metadata payload already materialized for catalogue construction so presentation state can be activated without a second backend request.
            % Authority and flow: Single-analysis component availability is derived from the same Results Viewer payload/Scientific State authorities as before. multi_analysis appends crossAnalysisComponents for the explicit AnalysisIndices set; it does not replace the selected analysis catalogue. Analysis-set inventory comes from NMResultsViewerScientificState.forAnalysisSet or an already-resident state supplied by the Results Viewer session boundary.
            % Scientific/state contract: Scientific State answers what exists; Report Builder only composes requested components. A multi_analysis context is one fixed analysis set plus one currently configured analysis, never an independent result-discovery system.
            % Invariants: Cross-analysis components occur only in multi_analysis scope and operate on reportContext.AnalysisIndices. Ordinary components always carry the selected analysisIndex in PayloadSpec. No raw analysis-result traversal is added here.
            % Materialization and performance: Catalogue construction materializes the existing compact performance/optimization/feature metadata for only the currently configured analysis. The already-resident feature metadata payload is returned as featurePresentationPayload for both ordinary and multi-analysis Report Builder scopes rather than recomputed by the browser. analysis_set and multi_analysis consume the session-resident compact analysis-set inventory when supplied; direct API calls without one build that compact inventory once. No per-analysis full Scientific State is constructed merely to populate the Report Builder analysis selector, and no cross-analysis numerical result or feature-scale array is materialized at catalogue time.
            % Resource declaration: This method itself reads no files/XML/atlas/annotation/mesh resources and performs no voxel/vertex scans or scans over vertices. Delegated single-analysis authorities retain their own contracts; analysis_set inventory is explicit user/report setup work.
            % Interactive/retained use: Safe for retained Report Builder opening/switching when the caller supplies the resident analysisSetState; direct API calls without a resident state may build the compact inventory explicitly.
            % Failure semantics: Invalid report scopes/analysis sets fail in reportAnalysisScope/Scientific State. Underlying component authority failures propagate explicitly.
            % Side effects: None; NM is not mutated and no export file is written.
            % Consumers and dependencies: Browser Report Builder, API/script generation, Scientific State, existing model-result component builders and crossAnalysisComponents.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if nargin < 3, analysisSetState = struct(); end

            scopeContext = NMResultsViewerTools.reportAnalysisScope(NM,spec);
            if any(strcmp(scopeContext.Scope,{'analysis_set','multi_analysis'}))
                if isempty(fieldnames(analysisSetState))
                    analysisSetState=NMResultsViewerScientificState.forAnalysisSet(NM,scopeContext.AnalysisIndices,spec);
                end
            end
            reportContext = NMResultsViewerReportTools.reportInvocationContext(NM,spec,analysisSetState,scopeContext);
            selectedEntry=find([reportContext.Analyses.AnalysisIndex]==reportContext.SelectedAnalysisIndex,1,'first');
            payloadSpec=scopeContext.PayloadSpec;
            performancePayloadSpec=payloadSpec;
            performancePayloadSpec.resultType=reportContext.Analyses(selectedEntry).ResultType;

            doProfile = NMRuntimeProgressTools.profileEnabled();
            [reportContext.OOCVSubgroups,reportContext.SelectedOOCVSubgroupIndex] = ...
                NMResultsViewerTools.oocvSubgroupsForAnalysis(NM,reportContext.SelectedAnalysisIndex,performancePayloadSpec);
            t = tic; performancePayload = NMResultsViewerTools.getPayload(NM,performancePayloadSpec);
            if doProfile, fprintf('[nm-prof]     report catalogue performance payload: %.3fs\n',toc(t)); end
            optimizationPayloadSpec=payloadSpec;optimizationPayloadSpec.resultType='model_optimization';
            t = tic; optPayload = NMResultsViewerTools.getModelOptimizationPayload(NM, optimizationPayloadSpec);
            if doProfile, fprintf('[nm-prof]     report catalogue optimization payload: %.3fs\n',toc(t)); end
            featureSpec=payloadSpec;featureSpec.resultType='model_feature_inspection';
            featureMetadataSpec = featureSpec; featureMetadataSpec.featureInspectionPayloadScope = 'metadata';
            t = tic; featurePayload = NMResultsViewerTools.getModelFeatureInspectionPayload(NM, featureMetadataSpec);
            if doProfile, fprintf('[nm-prof]     report catalogue feature payload: %.3fs\n',toc(t)); end

            t = tic; singleState = NMResultsViewerScientificState.fromPayloads({performancePayload,optPayload,featurePayload},performancePayloadSpec);
            if doProfile, fprintf('[nm-prof]     report catalogue Scientific State: %.3fs\n',toc(t)); end
            if isfield(optPayload,'sequenceDiagnostics') && optPayload.sequenceDiagnostics.available % nm2-allow: SEQOPT optimization producer conditionally publishes normalized sequence diagnostics.
                reportContext.Seqopt=struct('Candidates',optPayload.sequenceDiagnostics.candidates, ...
                    'Metrics',optPayload.sequenceDiagnostics.metrics, ...
                    'Criterion',optPayload.optimizationCriterion);
            end
            performanceComponents = NMResultsViewerReportTools.modelPerformanceComponentsFromState(performancePayloadSpec,singleState,1);
            optimizationComponents = NMResultsViewerReportTools.modelOptimizationComponentsFromState(optimizationPayloadSpec,singleState,numel(performanceComponents)+1,optPayload);
            featureComponents = NMResultsViewerReportTools.modelFeatureInspectionComponents(featurePayload,featureSpec,numel(performanceComponents)+numel(optimizationComponents)+1,singleState);
            featurePlanCatalogue = NMResultsViewerReportTools.featureInspectionPlanCatalogue(featurePayload,NM,featureSpec,performancePayloadSpec,singleState);
            featurePresentationPayload = featurePayload;
            components = [performanceComponents optimizationComponents featureComponents];
            if strcmp(reportContext.Scope,'multi_analysis')
                components=[components NMResultsViewerReportTools.crossAnalysisComponents(analysisSetState,reportContext,spec,numel(components)+1)];
                synthParents=[];
                if isfield(NM,'SYNTH') % nm2-allow: NM1.4 observed workspaces legitimately lack NM2 SYNTH experiment records.
                    synthParents=find(cellfun(@(parent)isequal( ...
                        sort(parent.analysisIndices),reportContext.AnalysisIndices),NM.SYNTH.analysis));
                end
                assert(numel(synthParents)<=1,'NMResultsViewerReportTools:SynthReportMembership', ...
                    'Report analysis set belongs to multiple SYNTH experiments.');
                if ~isempty(synthParents)
                    experiment=NM.SYNTH.analysis{synthParents};
                    c=NMResultsViewerReportTools.componentTemplate();
                    c.Id='cross_analysis.synth_overview';c.Label='SYNTH cumulative learning curve';c.Viewspace='cross_analysis';
                    if strcmp(experiment.mode,'fully_synthetic')
                        c.Label='SYNTH factorial mean by sample size';
                    end
                    c.Enabled=~isempty(experiment.performanceSummary);
                    c.RequiredArtifacts={'persisted SYNTH performance summary'};
                    c.DefaultLayout.Row=numel(components)+1;c.DefaultLayout.Order=c.DefaultLayout.Row;c.DefaultLayout.Group='cross_analysis';
                    c.PayloadSpec=struct('analysisIndices',experiment.analysisIndices, ...
                        'synthExperimentIndex',synthParents);
                    if c.Enabled
                        first=experiment.performanceSummary.contexts(1);
                        c.PayloadSpec.synthSelection=struct( ...
                            'targetNativeIndex',first.targetNativeIndex, ...
                            'classifierIndex',first.classifierIndex,'modelSource',first.modelSource, ...
                            'multiClassModeIndex',first.multiClassModeIndex, ...
                            'metricId',experiment.performanceSummary.criterion.metricId);
                    end
                    components(end+1)=c;
                end
            else
                analysisSetState=struct();
            end
        end

        function context = reportInvocationContext(NM,spec,analysisSetState,scopeContext)
            % Purpose: Build the Report Builder invocation context from canonical scope identity plus resident Scientific State result-type facts when available.
            % Syntax: context = NMResultsViewerReportTools.reportInvocationContext(NM,spec,analysisSetState,scopeContext)
            % Inputs: NM/spec define scope/focus; optional analysisSetState is the authoritative resident Scientific State inventory for the same analysis set; optional scopeContext is the already-normalized output of Results Viewer selection producer when the scope has just been resolved.
            % Outputs: Canonical context containing Scope, fixed AnalysisIndices, SelectedAnalysisIndex, selector availability, canonical labels and effective default Performance result type per analysis.
            % Authority and flow: Results Viewer selection owns set identity; NMResultsViewerTools.listAnalyses owns labels when no resident set inventory exists; Scientific State inventory owns resident labels/result-type facts; NMResultsViewerTools.defaultPerformanceResultType owns the default Performance semantics.
            % Scientific/state contract: Report Builder consumes effectivePerformanceResultType already stored by Scientific State and never derives multiclass/default Performance semantics from resultTypes rows.
            % Invariants: Resident state must match the exact canonical set; stored multiclass and binary-plus-multigroup defaults retain the established Results Viewer selector behavior.
            % Materialization and performance: With resident analysis-set state and supplied scopeContext this is O(A) compact projection with no analysis-catalogue traversal and zero per-analysis Scientific State constructions; without resident state direct API behavior may query the central result-type authority.
            % Resource declaration: Reads no files/XML/atlas/annotation/mesh resources, scans no voxel arrays or vertices and creates no feature-scale arrays; fallback work is delegated to the Results Viewer result-type authority.
            % Interactive/retained use: Safe on retained multi-analysis focus switching when the resident analysis-set inventory is supplied; this path performs no per-analysis Scientific State reconstruction.
            % Failure semantics: Invalid scope/state or missing resident inventory facts fail explicitly; no Report Builder-local result-type inference/fallback chain is introduced.
            % Side effects: None.
            % Consumers and dependencies: listAvailableComponents and direct Report Builder API callers.
            if nargin<2||~isstruct(spec),spec=struct();end
            if nargin<3,analysisSetState=struct();end
            if nargin<4,scopeContext=NMResultsViewerTools.reportAnalysisScope(NM,spec);end % nm2-allow: the existing MATLAB report-context function uses the central selection producer for omitted scopeContext.
            scope=scopeContext.Scope;indices=scopeContext.AnalysisIndices;selected=scopeContext.SelectedAnalysisIndex;
            inventory=struct([]);
            if ~isempty(fieldnames(analysisSetState))
                inventory=analysisSetState.inventory;
            end
            catalogue=struct([]);
            if isempty(inventory),catalogue=NMResultsViewerTools.listAnalyses(NM);end
            tmpl=struct('AnalysisIndex',1,'Label','','ResultType','');entries=repmat(tmpl,1,numel(indices));
            for ii=1:numel(indices)
                entries(ii).AnalysisIndex=indices(ii);
                if isempty(inventory)
                    row=catalogue([catalogue.index]==indices(ii));row=row(1);
                    entries(ii).Label=row.title;
                    entries(ii).ResultType=NMResultsViewerTools.defaultPerformanceResultType(NM,indices(ii));
                else
                    entries(ii).Label=inventory(ii).label;
                    entries(ii).ResultType=inventory(ii).effectivePerformanceResultType;
                end
            end
            selectedResultType=entries([entries.AnalysisIndex]==selected).ResultType;
            evaluationSources=NMResultsViewerTools.sourcesForAnalysis(NM,selected,selectedResultType);
            context=struct('ContractVersion','NM-REPORT-INVOCATION-CONTEXT-V2','Scope',scope,'AnalysisIndices',indices,'SelectedAnalysisIndex',selected,'AnalysisSelectorAvailable',numel(indices)>1,'Analyses',entries,'NMSelectorAvailable',false,'AnalysisSetLocked',strcmp(scope,'multi_analysis'),'EvaluationSources',evaluationSources);
        end

        function catalogue = featureInspectionPlanCatalogue(payload, varargin)
            % featureInspectionPlanCatalogue  Summarize authoritative feature-report iteration selectors.
            %
            % The optional NM/spec arguments add the binary-decomposition catalogue
            % used by Report Builder. They are resolved from trained BinClass results;
            % the multi-group aggregate classifier is deliberately excluded.
            contexts = payload.featureContexts;
            components = payload.backprojectionComponents;
            backprojectionAvailableMask = logical([contexts.backprojectionAvailable]);
            backprojectionComponentCounts = [contexts.backprojectionComponentCount];
            binaryClassifiers = struct('index',{},'label',{},'enabled',{});
            currentResultType = '';
            if numel(varargin) >= 2
                binaryClassifiers = NMResultsViewerReportTools.binaryClassifierPlanCatalogue(varargin{1}, varargin{2});
                requestSpec = varargin{2};
                if numel(varargin) >= 3, requestSpec = varargin{3}; end
                if numel(varargin) >= 3
                    currentResultType = requestSpec.resultType;
                else
                    currentResultType = NMResultsViewerTools.defaultPerformanceResultType( ...
                        varargin{1},varargin{2}.analysisIndex);
                end
            end
            enabledContextMask = logical([contexts.enabled]);
            enabledContextCount = sum(enabledContextMask);
            binaryClassifierCount = numel(binaryClassifiers);
            classifierScopeAvailable = binaryClassifierCount > 1 || ...
                (binaryClassifierCount > 0 && strcmp(currentResultType,'multiclass'));
            state=[];if numel(varargin)>=4&&isstruct(varargin{4}),state=varargin{4};end
            if ~isempty(state)
                featureAvailable=NMResultsViewerScientificState.hasArtefact(state,'feature_inspection_payload');
                anyModelAvailable=featureAvailable||NMResultsViewerScientificState.hasArtefact(state,'performance_payload')|| ...
                    NMResultsViewerScientificState.hasArtefact(state,'optimization_payload');
                if ~featureAvailable,enabledContextCount=0;backprojectionAvailableMask(:)=false;end
                classifierScopeAvailable=logical(classifierScopeAvailable&&anyModelAvailable);
            end
            catalogue = struct('FeatureContexts',contexts, ...
                'FeatureSourceCount',double(enabledContextCount), ...
                'FeatureSourceScopeAvailable',logical(enabledContextCount>1), ...
                'SelectedFeatureContextId',payload.selectedFeatureContextId, ...
                'BackprojectionComponents',components, ...
                'BackprojectionAvailableInAnyContext',logical(any(backprojectionAvailableMask)), ...
                'BackprojectionAvailableContextCount',double(sum(backprojectionAvailableMask)), ...
                'BackprojectionComponentCountByContext',double(backprojectionComponentCounts), ...
                'SelectedBackprojectionComponentId',payload.selectedBackprojectionComponentId, ...
                'SelectedBackprojectionComponentIndex',payload.selectedBackprojectionComponentIndex, ...
                'BinaryClassifiers',binaryClassifiers, ...
                'BinaryClassifierCount',double(binaryClassifierCount), ...
                'ClassifierScopeAvailable',logical(classifierScopeAvailable), ...
                'CurrentResultType',char(string(currentResultType)), ...
                'SelectedClassifierIndex',payload.classifierIndex, ...
                'AllBinaryDecompositionsAvailable',logical(binaryClassifierCount>1));
        end

        function entries = binaryClassifierPlanCatalogue(NM, spec)
            % binaryClassifierPlanCatalogue  List binary decomposition selector instances.
            %
            % Selector instances come from the authoritative Results Viewer selector
            % authority. Scientific availability remains owned by Scientific State;
            % Report Builder does not traverse GDdims/BinClass to reconstruct it.
            tmpl = struct('index',1,'label','Binary decomposition 1','enabled',true);
            entries = tmpl([]);
            analysisIndex = spec.analysisIndex;
            opts = NMResultsViewerTools.classifierOptions(NM, analysisIndex, 'model_feature_inspection', spec);
            if ~isstruct(opts) || isempty(opts), return; end
            entries = repmat(tmpl,1,numel(opts));
            for ii=1:numel(opts)
                entries(ii).index = double(opts(ii).index);
                entries(ii).label = opts(ii).label;
                entries(ii).enabled = opts(ii).enabled;
            end
        end

        function reportSpec = defaultReportSpec(NM, spec, varargin)
            % defaultReportSpec  Build a reproducible default report specification.
            %
            % reportSpec = NMResultsViewerReportTools.defaultReportSpec(NM, spec)
            % discovers enabled report components for the selected analysis and returns
            % a fixed-schema report specification that can be edited, stored, scripted,
            % passed to buildReport, or generated by the browser from the user's current
            % Results Viewer selections. The specification is component-based rather
            % than viewspace-based, so it can include model performance, model
            % optimization and later visualization/MLI/OOCV components in one report.
            %
            % spec.AnalysisIndex: optional 1-based NM.analysis index for component
            %                     discovery and default payload specs.
            % spec.ModelSource: optional model-optimization model source id.
            % spec.ClassifierIndex: optional learner/classifier index.
            % spec.TargetIndex: optional target/label index.
            % spec.Title: optional report title. Default is "NM Results Viewer report".
            % spec.Description: optional free-text report description.
            %
            % reportSpec.Components: fixed-schema component request array. Each entry
            %                        carries Id, Title, Viewspace, PayloadSpec, Layout
            %                        and Options fields.
            % varargin{1}: optional precomputed component catalogue from
            %              listAvailableComponents. Supplying it avoids duplicate
            %              catalogue discovery in service callers.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end

            if ~isempty(varargin) && isstruct(varargin{1})
                catalogue = varargin{1};
            else
                catalogue = NMResultsViewerReportTools.listAvailableComponents(NM, spec);
            end
            selected = catalogue([catalogue.Enabled]);
            compTmpl = NMResultsViewerReportTools.componentSpecTemplate();
            compSpecs = repmat(compTmpl, 1, numel(selected));
            for ii = 1:numel(selected)
                compSpecs(ii).Id = selected(ii).Id;
                compSpecs(ii).Title = selected(ii).Label;
                compSpecs(ii).Viewspace = selected(ii).Viewspace;
                compSpecs(ii).PayloadSpec = selected(ii).PayloadSpec;
                compSpecs(ii).Layout = selected(ii).DefaultLayout;
                compSpecs(ii).Instance = selected(ii).Instance;
                compSpecs(ii).Options = struct();
                if strcmp(compSpecs(ii).Id,'model_feature_inspection.fractionated_individual')
                    compSpecs(ii).Options=NMResultsViewerReportTools.fractionatedIndividualOptionsTemplate();
                elseif strcmp(compSpecs(ii).Id,'model_feature_inspection.fractionated_population')
                    compSpecs(ii).Options=NMResultsViewerReportTools.fractionatedPopulationOptionsTemplate();
                elseif strcmp(compSpecs(ii).Id,'model_feature_inspection.fractionated_clusters')
                    compSpecs(ii).Options=NMResultsViewerReportTools.fractionatedClusterOptionsTemplate();
                end
                if strcmp(compSpecs(ii).Id,'model_optimization.sequence_diagnostics')
                    compSpecs(ii).Options=struct('CandidatePolicy','winner','CandidateIndex',NaN, ...
                        'MetricIds',{{'criterion','sens','spec'}});
                end
                if ismember(compSpecs(ii).Id,{'model_feature_inspection.correlation_matrix', ...
                        'model_feature_inspection.feature_network'})
                    % New API recipes receive the owner-defined scientific request
                    % and the report's presentation defaults at their producer.
                    compSpecs(ii).Options=NMResultsViewerReportTools.defaultFeatureRelationOptions();
                end
            end

            reportSpec = NMResultsViewerReportTools.reportSpecTemplate();
            reportSpec.Title = NMResultsViewerReportTools.structText(spec, {'Title','title'}, 'NM Results Viewer report');
            reportSpec.Description = NMResultsViewerReportTools.structText(spec, {'Description','description'}, '');
            reportSpec.AnalysisIndex = NMResultsViewerReportTools.structScalar(spec, {'AnalysisIndex','analysisIndex'}, 1);
            reportSpec.Source = NMResultsViewerReportTools.structText(spec, {'Source','source'}, 'cv');
            reportSpec.MultiClassModeIndex = NMResultsViewerReportTools.structScalar(spec, {'MultiClassModeIndex','multiClassModeIndex'}, 1);
            reportSpec.AnalysisPlans = NMResultsViewerReportTools.analysisPlanTemplate();
            reportSpec.AnalysisPlans.AnalysisIndex = reportSpec.AnalysisIndex;
            reportSpec.Components = compSpecs;
            reportSpec.Layout = NMResultsViewerReportTools.defaultReportLayout(numel(compSpecs));
            reportSpec.Metadata = struct('CreatedBy','NMResultsViewerReportTools.defaultReportSpec', ...
                'SchemaVersion',reportSpec.SchemaVersion,'ComponentCount',numel(compSpecs), ...
                'MultiClassModeIndex',reportSpec.MultiClassModeIndex);
        end

        function reportSpec = planReportSpecForBrowser(NM, reportSpec)
            % Purpose: Normalize and plan one canonical Report Builder specification without rendering it.
            % Syntax: reportSpec = NMResultsViewerReportTools.planReportSpecForBrowser(NM,reportSpec)
            % Inputs: Read-only NM and one schema-2 report specification.
            % Outputs: Planned specification whose component Instance identities make repeated planning structurally idempotent.
            % Authority and flow: normalizeReportSpec first converges all analysis-local state into AnalysisPlans; planReportSpec then expands only unplanned classifier-scoped components.
            % Scientific/state contract: Scientific identity remains in authoritative PayloadSpec/Instance metadata; AnalysisPlans owns report-local selector/presentation state only.
            % Invariants: No separate expansion stop flag is required; plan(plan(spec)) preserves component identities, count and order.
            % Materialization and performance: Planning may perform the established compact classifier/feature metadata requests once for an unplanned spec; an already-planned spec returns from structural Instance identity without rematerialization.
            % Failure semantics: Mixed planned/unplanned classifier-scoped component state fails explicitly.
            % Side effects: None beyond request-scoped planning-session mutation.
            % Consumers and dependencies: MATLAB/tabular execution and browser report-plan service.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(reportSpec), reportSpec = NMResultsViewerReportTools.defaultReportSpec(NM, struct()); end
            reportSpec = NMResultsViewerReportTools.normalizeReportSpec(NM, reportSpec);
            session = NMResultsViewerReportTools.reportBuildSession(NM);
            [reportSpec, ~] = NMResultsViewerReportTools.planReportSpec(session, reportSpec);
        end

        function report = buildReport(NM, reportSpec)
            % buildReport  Assemble a JSON-safe Results Viewer report payload.
            %
            % report = NMResultsViewerReportTools.buildReport(NM, reportSpec) builds a
            % read-only report from explicit component requests. The method is intended
            % for both browser use and direct MATLAB/API use. It does not inspect DOM
            % state, does not write files, does not assign variables into the MATLAB base
            % workspace, and does not mutate the caller's NM value. A request-local NM
            % copy may receive derived probability artifacts so calibration and DCA
            % reuse one conversion during the build. Invalid component ids and unavailable
            % artifacts are returned as component-level status records with explicit
            % MissingReason text. Unexpected runtime failures are not silently caught;
            % they propagate to the caller so the browser bridge can route them through
            % the shared NM2 message strip.
            %
            % reportSpec.Title: report title used by browser/HTML/export layers.
            % reportSpec.Description: optional report description.
            % reportSpec.AnalysisIndex: default 1-based analysis index inherited by
            %                           component payload specs when absent.
            % reportSpec.Source: default result source inherited by component payload
            %                    specs when absent, usually "cv".
            % reportSpec.Components: component request array. Each component must expose
            %                        Id, Title, Viewspace, PayloadSpec, Layout and
            %                        Options fields; missing fields are normalized.
            % reportSpec.Layout: optional global layout metadata for browser/report
            %                    renderers. Component Layout fields remain authoritative
            %                    for component placement.
            % reportSpec.AnalysisPlans: canonical per-analysis report-local state.
            %                    FeatureSelection carries public natural selectors;
            %                    FeaturePresentations carries browser representation/view/montage
            %                    requests that NMResultsViewerUI.executeReport must resolve;
            %                    FeatureInspectionPlan carries compiled classifier,
            %                    feature-source and retained-component iteration scope.
            %                    ClassifierScope applies jointly to Model Performance,
            %                    Model Optimization and Model Feature Inspection; the
            %                    historical field name is retained for schema-2 compatibility. The
            %                    planner resolves exact backend classifier identities
            %                    and rejects absent or conflicting selections.
            %
            % report.Components: fixed-schema component payload array. Each component
            %                    includes Payload, Tables, PlotPayload, Layout, Status,
            %                    MissingReason and Warnings fields.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(reportSpec)
                reportSpec = NMResultsViewerReportTools.defaultReportSpec(NM, struct());
            end
            reportSpec = NMResultsViewerReportTools.normalizeReportSpec(NM, reportSpec);
            hasBrowserPresentation = false;
            for pp = 1:numel(reportSpec.AnalysisPlans)
                hasBrowserPresentation = hasBrowserPresentation || ~isempty(reportSpec.AnalysisPlans(pp).FeaturePresentations);
            end
            if hasBrowserPresentation
                error('NMResultsViewerReportTools:UnresolvedBrowserPresentation', ...
                    ['This report recipe requests browser-adapter feature presentations. ' ...
                     'Execute it through NMResultsViewerUI.executeReport so the shared Results Viewer adapters prepare those presentations before buildReport.']);
            end
            NMResultsViewerReportTools.reportProgress('Report Builder', ...
                'Resolving analysis, binary-decomposition and feature-component plan.',56,'plan');
            buildSession = NMResultsViewerReportTools.reportBuildSession(NM);
            [reportSpec, buildSession] = NMResultsViewerReportTools.planReportSpec(buildSession, reportSpec);
            reportSpec = NMResultsViewerReportTools.orderPreparedReportComponents(reportSpec);

            report = NMResultsViewerReportTools.reportTemplate();
            report.Title = reportSpec.Title;
            report.Description = reportSpec.Description;
            report.SchemaVersion = 2;
            report.Context = NMResultsViewerReportTools.reportContextFromSpec(NM, reportSpec);
            report.Layout = reportSpec.Layout;

            compTmpl = NMResultsViewerReportTools.reportComponentTemplate();
            comps = repmat(compTmpl, 1, numel(reportSpec.Components));
            warnings = {};
            errors = {};
            nComponents = numel(reportSpec.Components);
            if nComponents > 0
                NMResultsViewerReportTools.reportProgress('Report Builder', sprintf('Preparing %d report component(s).', nComponents), 60, 'prepare');
            end
            for ii = 1:nComponents
                componentLabel = NMResultsViewerReportTools.reportComponentProgressLabel(reportSpec.Components(ii), ii);
                pct = 62 + 28 * double(ii - 1) / max(1, double(nComponents));
                NMResultsViewerReportTools.reportProgress('Current report component', sprintf('Rendering %s (%d/%d).', componentLabel, ii, nComponents), pct, 'render_component');
                [comps(ii), buildSession] = NMResultsViewerReportTools.buildComponentWithSession(buildSession, reportSpec.Components(ii), reportSpec);
                comps(ii) = NMResultsViewerReportTools.initializeComponentRenderFields(comps(ii));
                if ~isempty(comps(ii).Warnings)
                    warnings = [warnings, comps(ii).Warnings]; %#ok<AGROW>
                end
                if strcmpi(comps(ii).Status, 'error')
                    if ~isempty(comps(ii).MissingReason)
                        errors{end+1} = sprintf('%s: %s', comps(ii).Id, comps(ii).MissingReason); %#ok<AGROW>
                    end
                elseif strcmpi(comps(ii).Status, 'unavailable') && ~isempty(comps(ii).MissingReason)
                    warnings{end+1} = sprintf('%s unavailable: %s', comps(ii).Id, comps(ii).MissingReason); %#ok<AGROW>
                end
            end
            if nComponents > 0
                NMResultsViewerReportTools.reportProgress('Report Builder', 'Finalizing report payload.', 92, 'finalize_report');
            end
            report.Components = comps;
            report.Warnings = warnings;
            report.Errors = errors;
            report.Ok = isempty(errors);
            report.Metadata = struct('CreatedBy','NMResultsViewerReportTools.buildReport', ...
                'SchemaVersion',report.SchemaVersion,'ComponentCount',numel(comps), ...
                'RenderStatusCounts',NMResultsViewerReportTools.renderStatusCounts(comps), ...
                'ExecutionCache',NMResultsViewerReportTools.reportBuildSessionSummary(buildSession), ...
                'Plan',reportSpec.PlanSummary);
        end

        function out = exportReport(NM, reportSpec, exportSpec, varargin)
            % exportReport  Export an API-built Results Viewer report to disk.
            %
            % out = NMResultsViewerReportTools.exportReport(NM, reportSpec,
            % exportSpec) builds the requested report through buildReport and writes
            % a deterministic file artifact without scraping browser DOM state. The
            % method is read-only with respect to NM: it never mutates analyses,
            % workspaces, result payloads or base-workspace variables. Invalid export
            % requests return ok=false with an explicit message; unexpected writer
            % failures propagate to the caller and should be routed by the browser
            % service to the NM2 message strip.
            %
            % reportSpec: component-based specification accepted by buildReport.
            % exportSpec.Format: output format, one of "mat", "json", "csv", "xlsx",
            %                    "html" or "pdf". Default is "html".
            % exportSpec.OutputDirectory: target directory. Defaults to pwd for API
            %                             calls; browser calls should pass the folder
            %                             chosen by the OS-native path picker.
            % exportSpec.OutputFile: optional explicit output path. When supplied, the
            %                        extension is normalized to the selected format.
            % exportSpec.BaseName: optional sanitized base filename used when
            %                      OutputFile is absent.
            % exportSpec.IncludePayloadMat: logical flag. When true, a MAT sidecar with
            %                               report, reportSpec and exportSpec is saved
            %                               for HTML/PDF exports. Default is false.
            % exportSpec.IncludeHtml: logical flag. For PDF export, also keep the
            %                         intermediate static HTML report. Default false.
            % exportSpec.MaxTableRows: maximum rows rendered per table in technical HTML/PDF
            %                          previews. Full table rows remain in MAT/JSON.
            % exportSpec.ReportMode: optional HTML/PDF rendering mode. "summary"
            %                        creates a curated scientific report with compact
            %                        tables and diagnostics; "technical" preserves the
            %                        exhaustive payload-table view; "full" and
            %                        "technical_text" are also explicit supported modes.
            % varargin{1}: optional prebuilt nm_results_viewer_report payload. When
            %              supplied, export reuses it and does not call buildReport
            %              again. Browser callers validate this payload through a
            %              report handle before passing it here.
            %
            % out.ok: logical export status.
            % out.message: explicit export status or diagnostic message.
            % out.format: normalized output format.
            % out.path: primary exported file or directory.
            % out.paths: cell array of all written paths.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(reportSpec)
                reportSpec = NMResultsViewerReportTools.defaultReportSpec(NM, struct());
            end
            if nargin < 3 || isempty(exportSpec), exportSpec = struct(); end

            exportSpec = NMResultsViewerReportTools.normalizeExportSpec(exportSpec);
            if exist(exportSpec.OutputDirectory, 'dir') ~= 7
                out = NMResultsViewerReportTools.exportOut(false, exportSpec.Format, '', {}, ...
                    sprintf('Report export directory does not exist: %s', exportSpec.OutputDirectory));
                return;
            end

            report = struct();
            if ~isempty(varargin) && isstruct(varargin{1}) && ...
                    strcmpi(char(string(NMResultsViewerReportTools.safeField(varargin{1},'Kind',''))),'nm_results_viewer_report')
                report = varargin{1};
                NMResultsViewerReportTools.validatePrebuiltReport(report);
                NMResultsViewerReportTools.reportProgress('Report Builder', 'Reusing validated report payload.', 60, 'reuse_report');
            else
                NMResultsViewerReportTools.reportProgress('Report Builder', 'Building report payload.', 60, 'build_report');
                report = NMResultsViewerReportTools.buildReport(NM, reportSpec);
            end
            fmt = exportSpec.Format;
            NMResultsViewerReportTools.reportProgress('Report export', sprintf('Writing %s report artifact.', upper(fmt)), 94, 'write_export');
            paths = cell(1,0);
            pdfRendererName = '';
            pdfProbeLog = '';
            switch fmt
                case 'mat'
                    primaryPath = NMResultsViewerReportTools.exportPath(exportSpec, 'mat');
                    save(primaryPath, 'report', 'reportSpec', 'exportSpec', '-v7.3');
                    paths{end+1} = primaryPath; %#ok<AGROW>
                case 'json'
                    primaryPath = NMResultsViewerReportTools.exportPath(exportSpec, 'json');
                    txt = jsonencode(report);
                    NMSerializationTools.writeTextUtf8(primaryPath, txt);
                    paths{end+1} = primaryPath; %#ok<AGROW>
                case {'csv','xlsx'}
                    blocks = NMResultsViewerReportTools.reportTableBlocks(NM,report);
                    meta = struct('Report',report.Title,'Analysis',report.Context.AnalysisTitle, ...
                        'Source',report.Context.Source);
                    if strcmp(fmt,'xlsx')
                        primaryPath = NMResultsViewerReportTools.exportPath(exportSpec,'xlsx');
                    else
                        primaryPath = exportSpec.OutputDirectory;
                    end
                    paths = NMResultsViewerTableExportTools.writeCellTables(blocks,fmt,exportSpec.OutputDirectory, ...
                        exportSpec.BaseName,primaryPath,NMResultsViewerReportTools.dataToCell(meta,Inf),meta);
                case 'html'
                    primaryPath = NMResultsViewerReportTools.exportPath(exportSpec, 'html');
                    html = NMResultsViewerReportTools.renderReportHtml(report, exportSpec);
                    NMResultsViewerReportTools.reportProgress('Report export', 'Writing HTML report.', 96, 'write_html');
                    NMSerializationTools.writeTextUtf8(primaryPath, html);
                    paths{end+1} = primaryPath; %#ok<AGROW>
                    if exportSpec.IncludePayloadMat
                        matPath = NMResultsViewerReportTools.sidecarPath(primaryPath, '_payload', 'mat');
                        save(matPath, 'report', 'reportSpec', 'exportSpec', '-v7.3');
                        paths{end+1} = matPath; %#ok<AGROW>
                    end
                case 'pdf'
                    primaryPath = NMResultsViewerReportTools.exportPath(exportSpec, 'pdf');
                    if strcmpi(exportSpec.ReportMode, 'technical_text')
                        NMResultsViewerReportTools.writeSimplePdfReport(report, primaryPath, exportSpec);
                        paths{end+1} = primaryPath; %#ok<AGROW>
                    else
                        % The user-facing static HTML sidecar keeps normal
                        % browser typography. PDF-compacted typography is rendered from a
                        % separate temporary HTML document and must not leak into the sidecar.
                        htmlPath = NMResultsViewerReportTools.sidecarPath(primaryPath, '_static', 'html');
                        htmlSpec = exportSpec;
                        htmlSpec.PdfTarget = false;
                        html = NMResultsViewerReportTools.renderReportHtml(report, htmlSpec);
                        NMSerializationTools.writeTextUtf8(htmlPath, html);
                        if exportSpec.IncludeHtml
                            paths{end+1} = htmlPath; %#ok<AGROW>
                        end
                        renderer = NMResultsViewerReportTools.resolvePdfRenderer(exportSpec);
                        pdfRendererName = renderer.name;
                        pdfProbeLog = renderer.probeLog;
                        pdfOk = false;
                        if renderer.ok
                            pdfHtmlPath = NMResultsViewerReportTools.sidecarPath(primaryPath, '_pdf_render', 'html');
                            pdfHtmlSpec = exportSpec;
                            pdfHtmlSpec.PdfTarget = true;
                            pdfHtml = NMResultsViewerReportTools.renderReportHtml(report, pdfHtmlSpec);
                            NMSerializationTools.writeTextUtf8(pdfHtmlPath, pdfHtml);
                            NMResultsViewerReportTools.reportProgress('Report export', sprintf('Rendering PDF using %s.', renderer.name), 98, 'write_pdf');
                            [pdfOk, pdfMessage] = NMResultsViewerReportTools.writePdfFromHtml(pdfHtmlPath, primaryPath, renderer, exportSpec);
                            if ~pdfOk
                                bundled = NMResultsViewerReportTools.bundledPdfRendererCandidate();
                                [exe, msg] = NMResultsViewerReportTools.resolveExecutable(bundled.executable);
                                if ~isempty(exe) && ~strcmp(exe, renderer.executable)
                                    NMResultsViewerReportTools.reportProgress('Report export', 'System PDF renderer failed; trying bundled Chromium.', 98, 'pdf_fallback');
                                    firstFailure = pdfMessage;
                                    renderer.executable = exe;
                                    renderer.kind = 'chromium';
                                    renderer.name = ['chromium:' exe];
                                    pdfRendererName = renderer.name;
                                    [pdfOk, pdfMessage] = NMResultsViewerReportTools.writePdfFromHtml(pdfHtmlPath, primaryPath, renderer, exportSpec);
                                    if ~pdfOk
                                        pdfMessage = sprintf('%s; bundled fallback failed: %s', firstFailure, pdfMessage);
                                    end
                                end
                            end
                            if pdfOk && isfile(pdfHtmlPath), delete(pdfHtmlPath); end
                        end
                        if exportSpec.IncludePayloadMat
                            matPath = NMResultsViewerReportTools.sidecarPath(primaryPath, '_payload', 'mat');
                            save(matPath, 'report', 'reportSpec', 'exportSpec', '-v7.3');
                            paths{end+1} = matPath; %#ok<AGROW>
                        end
                        if ~renderer.ok || ~pdfOk
                            if ~renderer.ok
                                pdfMessage = sprintf('No usable HTML-to-PDF renderer. Probe log: %s', renderer.probeLog);
                            end
                            bundled = NMResultsViewerReportTools.bundledPdfRendererCandidate();
                            [installed, ~] = NMResultsViewerReportTools.resolveExecutable(bundled.executable);
                            if isempty(installed)
                                pdfMessage = sprintf('%s Optional Chromium Headless Shell is absent. Download the NM2 Chromium installer and run nm2_install_chromium_shell in MATLAB; if automatic download fails, supply an alternate HTTPS URL or a local ZIP as its second argument.', pdfMessage);
                            end
                            out = NMResultsViewerReportTools.exportOut(false, fmt, '', paths, ...
                                sprintf('Report PDF export failed; static HTML was written. %s', pdfMessage));
                            out.pdfRenderer = renderer.name;
                            out.pdfProbeLog = renderer.probeLog;
                            return;
                        end
                        paths = [{primaryPath} paths];
                        if ~exportSpec.IncludeHtml && exist(htmlPath, 'file') == 2
                            delete(htmlPath);
                        end
                    end
                otherwise
                    out = NMResultsViewerReportTools.exportOut(false, fmt, '', {}, ...
                        sprintf('Unsupported report export format "%s".', fmt));
                    return;
            end
            NMResultsViewerReportTools.reportProgress('Report export', 'Report export completed.', 100, 'done');
            out = NMResultsViewerReportTools.exportOut(true, fmt, primaryPath, paths, ...
                sprintf('Results Viewer report exported as %s.', upper(fmt)));
            if strcmpi(fmt, 'pdf')
                out.pdfRenderer = pdfRendererName;
                out.pdfProbeLog = pdfProbeLog;
            end
        end

        function scriptText = scriptFromReportSpec(reportSpec, scriptSpec)
            % scriptFromReportSpec  Generate an educational MATLAB Report Builder recipe.
            %
            % The editable sections expose the scientific report model: analysis,
            % report components, feature payload/source/component selection and browser
            % presentations. Internal feature-context ids, backprojection ids, complete
            % browser state and rendered raster artifacts are never presented as inputs.
            if nargin < 1 || isempty(reportSpec), reportSpec = NMResultsViewerReportTools.reportSpecTemplate(); end
            if nargin < 2 || isempty(scriptSpec), scriptSpec = struct(); end

            scriptSpec = NMResultsViewerUI.requestScriptSpec(struct('scriptSpec',scriptSpec));
            nmVar = NMResultsViewerReportTools.validMatlabIdentifier(scriptSpec.NMVariableName, 'NM');
            specVar = NMResultsViewerReportTools.validMatlabIdentifier(scriptSpec.ReportSpecVariableName, 'reportSpec');
            reportVar = NMResultsViewerReportTools.validMatlabIdentifier(scriptSpec.ReportVariableName, 'report');
            executionVar = NMResultsViewerReportTools.validMatlabIdentifier(scriptSpec.ExecutionVariableName, 'execution');
            outputMat = scriptSpec.OutputMatFile;
            includeHeader = scriptSpec.IncludeHeader;
            failIfMissing = scriptSpec.FailIfNMNotFound;
            hasExportSpec = ~isempty(fieldnames(scriptSpec.ExportSpec));
            exportVar = NMResultsViewerReportTools.validMatlabIdentifier(scriptSpec.ExportSpecVariableName, 'exportSpec');
            exportOutVar = NMResultsViewerReportTools.validMatlabIdentifier(scriptSpec.ExportOutputVariableName, 'exportOut');
            includeSettingsCompanion = scriptSpec.IncludeSettingsCompanion;
            settingsFunctionName = NMResultsViewerReportTools.validMatlabIdentifier(scriptSpec.SettingsFunctionName, 'NMResultsViewerReport_settings');

            isMultiAnalysis = numel(reportSpec.AnalysisPlans) > 1;
            rawComponents = reportSpec.Components;
            if ~isstruct(rawComponents), rawComponents = NMResultsViewerReportTools.componentSpecTemplate([]); end
            analysisPlans = reportSpec.AnalysisPlans;
            if ~isstruct(analysisPlans) || isempty(analysisPlans)
                error('NMResultsViewerReportTools:MissingAnalysisPlan', ...
                    'Canonical report scripts require at least one AnalysisPlans entry.');
            end
            primaryPlan = NMResultsViewerReportTools.copyMissingFields(analysisPlans(1),NMResultsViewerReportTools.analysisPlanTemplate());
            featureSelection = primaryPlan.FeatureSelection;
            featurePresentations = primaryPlan.FeaturePresentations;
            presentationState = primaryPlan.PresentationState;
            globalPresentationState = reportSpec.PresentationState;
            if ~isstruct(globalPresentationState) || ~isscalar(globalPresentationState), globalPresentationState=struct('OutputOrder',{{}}); end

            featureMetricMask = false(1,numel(rawComponents));
            inferredPayloads = {};
            for ii=1:numel(rawComponents)
                inst=rawComponents(ii).Instance;
                featureMetricMask(ii)=strcmp(inst.ComponentType,'feature_metric');
                metricId=inst.MetricId;
                if featureMetricMask(ii)
                    if isempty(metricId)
                        error('NMResultsViewerReportTools:MissingFeatureMetricIdentity', ...
                            'Feature metric component %s has no structured MetricId.',rawComponents(ii).Id);
                    end
                    inferredPayloads{end+1}=metricId; %#ok<AGROW>
                end
            end
            if ~isMultiAnalysis && isempty(NMResultsViewerReportTools.safeCellstr(featureSelection.Payloads)) && ~isempty(inferredPayloads)
                featureSelection.Payloads = unique(inferredPayloads,'stable');
            end
            if ~isMultiAnalysis && ~isempty(featureSelection.Payloads), featureSelection.Enabled=true; end

            components = rawComponents(~featureMetricMask | ~logical(featureSelection.Enabled));
            keep = false(1,numel(components)); seen = {};
            for ii=1:numel(components)
                id = components(ii).Id;
                keep(ii) = ~isempty(id) && ~any(strcmp(seen,id));
                if keep(ii), seen{end+1}=id; end %#ok<AGROW>
            end
            components = components(keep);
            if isMultiAnalysis, components = rawComponents; end
            firstPayload = struct();
            if ~isempty(rawComponents), firstPayload = rawComponents(1).PayloadSpec; end
            metadata = reportSpec.Metadata;

            lines = {};
            if includeHeader
                lines = {'%% NM Results Viewer report recipe', ...
                    '% Generated by NMResultsViewerReportTools.scriptFromReportSpec.', ...
                    '% Edit Sections 1-4 to customize report content and presentation.', ...
                    '% Section 5 preserves the exact viewer snapshot and may apply an optional user-facing settings companion.', ...
                    '% Section 6 executes the same browser adapters used by the interactive Report Builder when visual presentations are requested.',''};
            end
            if failIfMissing
                lines{end+1} = sprintf('if ~exist(''%s'', ''var'')', nmVar); %#ok<AGROW>
                lines{end+1} = sprintf('    error(''NMResultsViewerReportTools:MissingNM'', ''Variable %s is required to build the Results Viewer report.'');', nmVar); %#ok<AGROW>
                lines{end+1} = 'end'; lines{end+1} = ''; %#ok<AGROW>
            end

            lines{end+1} = '%% 1. Report context'; %#ok<AGROW>
            lines{end+1} = '% AnalysisIndex, ClassifierIndex and TargetIndex are 1-based.'; %#ok<AGROW>
            lines{end+1} = 'reportContext = struct();'; %#ok<AGROW>
            context = struct('AnalysisIndex',reportSpec.AnalysisIndex, ...
                'Source',reportSpec.Source, ...
                'MultiClassModeIndex',reportSpec.MultiClassModeIndex, ...
                'Title',reportSpec.Title, ...
                'Description',reportSpec.Description);
            resultType = '';
            if isstruct(metadata), resultType = char(string(NMResultsViewerReportTools.safeField(metadata,'BrowserResultType',''))); end
            if isempty(resultType) && isstruct(firstPayload), resultType = char(string(NMResultsViewerReportTools.safeField(firstPayload,'resultType',''))); end
            if ~isempty(resultType), context.ResultType = resultType; end
            contextFields = {'modelSource','classifierIndex','targetIndex','maxFeatures','maxComponents'};
            contextNames = {'ModelSource','ClassifierIndex','TargetIndex','MaxFeatures','MaxComponents'};
            for ii=1:numel(contextFields)
                field=contextFields{ii}; name=contextNames{ii};
                if ~isstruct(firstPayload) || ~isfield(firstPayload,field) || isempty(firstPayload.(field)), continue; end
                context.(name)=firstPayload.(field);
            end
            names = fieldnames(context);
            for ii=1:numel(names)
                lines{end+1}=sprintf('reportContext.%s = %s;',names{ii},NMResultsViewerReportTools.scriptValueLiteral(context.(names{ii}))); %#ok<AGROW>
            end
            lines{end+1}=sprintf('%s = NMResultsViewerReportTools.defaultReportSpec(%s, reportContext);',specVar,nmVar); %#ok<AGROW>
            lines{end+1}=sprintf('%s.AnalysisPlans = jsondecode(%s);',specVar,NMResultsViewerReportTools.matlabStringLiteral(jsonencode(analysisPlans))); %#ok<AGROW>
            if isMultiAnalysis
                % The browser already selected and identified all analysis-local and
                % cross-analysis components. A single-analysis default catalogue
                % cannot reconstruct that request or its global OutputOrder.
                lines{end+1}=sprintf('%s.Components = jsondecode(%s);',specVar,NMResultsViewerReportTools.matlabStringLiteral(jsonencode(rawComponents))); %#ok<AGROW>
                lines{end+1}=sprintf('%s.Layout = jsondecode(%s);',specVar,NMResultsViewerReportTools.matlabStringLiteral(jsonencode(reportSpec.Layout))); %#ok<AGROW>
                lines{end+1}=sprintf('%s.Metadata = jsondecode(%s);',specVar,NMResultsViewerReportTools.matlabStringLiteral(jsonencode(metadata))); %#ok<AGROW>
            end
            lines{end+1}=''; %#ok<AGROW>

            if isMultiAnalysis
                lines{end+1}='%% 2. Component instances (all analysis identities are preserved)'; %#ok<AGROW>
                lines{end+1}='% To change a selection, edit reportSpec.Components and clear PresentationState.OutputOrder.'; %#ok<AGROW>
                for ii=1:numel(rawComponents)
                    lines{end+1}=sprintf('%% %d: %s | %s',ii,rawComponents(ii).Viewspace,rawComponents(ii).Id); %#ok<AGROW>
                end
            else
            lines{end+1}='%% 2. Report sections other than feature payloads'; %#ok<AGROW>
            lines{end+1}='% Add or remove these report sections. Feature payloads are selected separately in Section 3; backend scientific ordering remains authoritative.'; %#ok<AGROW>
            lines{end+1}='componentIds = {'; %#ok<AGROW>
            for ii=1:numel(components)
                id=char(string(components(ii).Id)); title=regexprep(char(string(NMResultsViewerReportTools.safeField(components(ii),'Title',id))),'[\r\n]+',' ');
                lines{end+1}=sprintf('    %s  %% %s',NMResultsViewerReportTools.matlabStringLiteral(id),title); %#ok<AGROW>
            end
            lines{end+1}='};'; %#ok<AGROW>
            lines{end+1}=sprintf('availableIds = {%s.Components.Id};',specVar); %#ok<AGROW>
            lines{end+1}='[componentAvailable, componentIndex] = ismember(componentIds, availableIds);'; %#ok<AGROW>
            lines{end+1}='if any(~componentAvailable)'; %#ok<AGROW>
            lines{end+1}='    error(''NMResultsViewerReportTools:UnavailableScriptComponent'', ...'; %#ok<AGROW>
            lines{end+1}='        ''Requested report component(s) are unavailable: %s'', strjoin(componentIds(~componentAvailable), '', ''));'; %#ok<AGROW>
            lines{end+1}='end'; %#ok<AGROW>
            lines{end+1}=sprintf('%s.Components = %s.Components(componentIndex);',specVar,specVar); %#ok<AGROW>
            lines{end+1}=''; %#ok<AGROW>

            end
            if ~isMultiAnalysis
            lines{end+1}='%% 3. Feature payloads and scientific expansion'; %#ok<AGROW>
            lines{end+1}='% Select feature sources by natural modality index, retained components by their original component index,'; %#ok<AGROW>
            lines{end+1}='% and payloads by stable scientific metric id. No internal feature-context ids are required.'; %#ok<AGROW>
            lines{end+1}='% To inspect available report components and feature sources interactively, call:'; %#ok<AGROW>
            lines{end+1}=sprintf('%% [availableComponents, featureCatalogue] = NMResultsViewerReportTools.listAvailableComponents(%s, reportContext);',nmVar); %#ok<AGROW>
            lines{end+1}=sprintf('%s.AnalysisPlans(1).FeatureSelection.Enabled = %s;',specVar,NMResultsViewerReportTools.scriptValueLiteral(logical(featureSelection.Enabled))); %#ok<AGROW>
            fields={'Classifiers','Modalities','IncludeCombined','Components','Payloads','IncludeFusionOverview'};
            for ii=1:numel(fields)
                field=fields{ii};
                lines{end+1}=sprintf('%s.AnalysisPlans(1).FeatureSelection.%s = %s;',specVar,field,NMResultsViewerReportTools.scriptValueLiteral(featureSelection.(field))); %#ok<AGROW>
            end
            lines{end+1}='% Examples:'; %#ok<AGROW>
            lines{end+1}=sprintf('%% %s.AnalysisPlans(1).FeatureSelection.Modalities = [1 2];    %% exact physical modalities',specVar); %#ok<AGROW>
            lines{end+1}=sprintf('%% %s.AnalysisPlans(1).FeatureSelection.Components = ''all''; %% all retained/backprojected components',specVar); %#ok<AGROW>
            lines{end+1}=sprintf('%% %s.AnalysisPlans(1).FeatureSelection.Payloads = {''cross_validation_ratio'',''sign_consistency_logq''};',specVar); %#ok<AGROW>
            lines{end+1}=''; %#ok<AGROW>

            lines{end+1}='%% 4. Feature presentations'; %#ok<AGROW>
            lines{end+1}='% Each requested representation is rendered by the same browser adapter used interactively.'; %#ok<AGROW>
            lines{end+1}=sprintf('%s.AnalysisPlans(1).FeaturePresentations = %s.AnalysisPlans(1).FeaturePresentations([]);',specVar,specVar); %#ok<AGROW>
            for ii=1:numel(featurePresentations)
                pr=NMResultsViewerReportTools.copyMissingFields(featurePresentations(ii),NMResultsViewerReportTools.featurePresentationTemplate());
                lines{end+1}='presentation = struct();'; %#ok<AGROW>
                lines{end+1}=sprintf('presentation.Representation = %s;',NMResultsViewerReportTools.scriptValueLiteral(pr.Representation)); %#ok<AGROW>
                lines{end+1}=sprintf('presentation.SupportDomain = %s;',NMResultsViewerReportTools.scriptValueLiteral(pr.SupportDomain)); %#ok<AGROW>
                lines{end+1}=sprintf('presentation.ViewMode = %s;',NMResultsViewerReportTools.scriptValueLiteral(pr.ViewMode)); %#ok<AGROW>
                lines{end+1}=sprintf('presentation.CanonicalViews = %s;',NMResultsViewerReportTools.scriptValueLiteral(pr.CanonicalViews)); %#ok<AGROW>
                lines{end+1}='presentation.Montage = struct();'; %#ok<AGROW>
                montage=pr.Montage;
                if isstruct(montage)
                    montageNames=fieldnames(montage);
                    for jj=1:numel(montageNames)
                        field=montageNames{jj};
                        lines{end+1}=sprintf('presentation.Montage.%s = %s;',field,NMResultsViewerReportTools.scriptValueLiteral(montage.(field))); %#ok<AGROW>
                    end
                end
                lines{end+1}=sprintf('%s.AnalysisPlans(1).FeaturePresentations(end+1) = presentation;',specVar); %#ok<AGROW>
                lines{end+1}=''; %#ok<AGROW>
            end
            if isempty(featurePresentations)
                lines{end+1}='% No browser feature presentation was selected; feature payload components will use their MATLAB/tabular presentation.'; %#ok<AGROW>
                lines{end+1}=''; %#ok<AGROW>
            end
            end
            lines{end+1}='%% 5. Advanced reproducibility snapshot'; %#ok<AGROW>
            lines{end+1}='% This compact state reproduces thresholds, colour scales, camera/anatomy/lighting and connectivity settings.'; %#ok<AGROW>
            lines{end+1}='% It contains no feature arrays and no rendered images. Most users do not need to edit it.'; %#ok<AGROW>
            if ~isMultiAnalysis
                if isempty(fieldnames(presentationState))
                    lines{end+1}=sprintf('%s.AnalysisPlans(1).PresentationState = struct();',specVar); %#ok<AGROW>
                else
                    lines{end+1}=sprintf('%s.AnalysisPlans(1).PresentationState = jsondecode(%s);',specVar,NMResultsViewerReportTools.matlabStringLiteral(jsonencode(presentationState))); %#ok<AGROW>
                end
            end
            lines{end+1}=sprintf('%s.PresentationState = jsondecode(%s);',specVar,NMResultsViewerReportTools.matlabStringLiteral(jsonencode(globalPresentationState))); %#ok<AGROW>
            if includeSettingsCompanion
                lines{end+1}=sprintf('%% Public appearance overrides for analysis plan 1 are kept in %s.m.',settingsFunctionName); %#ok<AGROW>
                lines{end+1}=sprintf('%s.AnalysisPlans(1).DisplayOverrides = %s();',specVar,settingsFunctionName); %#ok<AGROW>
            elseif ~isMultiAnalysis
                lines{end+1}=sprintf('%s.AnalysisPlans(1).DisplayOverrides = struct();',specVar); %#ok<AGROW>
            end
            lines{end+1}=''; %#ok<AGROW>

            lines{end+1}='%% 6. Execute the Report Builder recipe'; %#ok<AGROW>
            lines{end+1}='% Visual requests run in an isolated headless browser process owned by MATLAB; no Results Viewer window is opened.'; %#ok<AGROW>
            lines{end+1}='% Verbose=true reports browser preparation and MATLAB report-building stages to the MATLAB command window.'; %#ok<AGROW>
            lines{end+1}='executionOptions = struct();'; %#ok<AGROW>
            lines{end+1}='executionOptions.Headless = true;'; %#ok<AGROW>
            lines{end+1}='executionOptions.Verbose = true;'; %#ok<AGROW>
            lines{end+1}='% Optional: choose the rendering engine explicitly when the platform default is unavailable:'; %#ok<AGROW>
            lines{end+1}='% executionOptions.BrowserTarget = ''browser-edge'';    % Windows Edge'; %#ok<AGROW>
            lines{end+1}='% executionOptions.BrowserTarget = ''browser-chrome'';  % Chrome/Chromium'; %#ok<AGROW>
            lines{end+1}='% executionOptions.BrowserTarget = ''browser-firefox''; % Firefox'; %#ok<AGROW>
            lines{end+1}=sprintf('[%s, %s] = NMResultsViewerUI.executeReport(%s, %s, executionOptions);',reportVar,executionVar,nmVar,specVar); %#ok<AGROW>
            lines{end+1}=''; lines{end+1}='%% 7. Export'; %#ok<AGROW>
            if hasExportSpec
                lines{end+1}=sprintf('%s = struct();',exportVar); %#ok<AGROW>
                names=fieldnames(scriptSpec.ExportSpec);
                for ii=1:numel(names), lines{end+1}=sprintf('%s.%s = %s;',exportVar,names{ii},NMResultsViewerReportTools.scriptValueLiteral(scriptSpec.ExportSpec.(names{ii}))); end %#ok<AGROW>
                lines{end+1}=sprintf('%s = NMResultsViewerReportTools.exportReport(%s, %s.PreparedReportSpec, %s, %s);',exportOutVar,nmVar,executionVar,exportVar,reportVar); %#ok<AGROW>
            else
                lines{end+1}='exportSpec = struct(''Format'',''pdf'',''OutputDirectory'',pwd,''BaseName'',''NM_results_viewer_report'');'; %#ok<AGROW>
                lines{end+1}=sprintf('exportOut = NMResultsViewerReportTools.exportReport(%s, %s.PreparedReportSpec, exportSpec, %s);',nmVar,executionVar,reportVar); %#ok<AGROW>
            end
            if ~isempty(outputMat), lines{end+1}=sprintf('save(%s, ''%s'', ''%s'', ''%s'');',NMResultsViewerReportTools.matlabStringLiteral(outputMat),reportVar,specVar,executionVar); end %#ok<AGROW>
            scriptText=strjoin(lines,newline);
        end

        function S = defaultDisplayOverrides()
            % defaultDisplayOverrides  Create the public Report Builder appearance-override schema.
            %
            % The fields are intentionally user-facing and contain no browser context
            % ids. Empty fields mean "retain the exact PresentationState snapshot".
            % Payloads and Contexts are cells so users can append heterogeneous
            % settings without MATLAB dissimilar-structure assignment failures.
            S = struct('Imaging2D',struct(),'Imaging3D',struct(),'Surface',struct(), ...
                'Volume',struct(),'Connectivity',struct(),'Payloads',{{}},'Contexts',{{}});
        end

        function settingsText = settingsCompanionFromReportSpec(reportSpec, scriptSpec)
            % settingsCompanionFromReportSpec  Generate an editable public appearance-settings function.
            if nargin < 1 || isempty(reportSpec), reportSpec=NMResultsViewerReportTools.reportSpecTemplate(); end
            if nargin < 2 || isempty(scriptSpec), scriptSpec=struct(); end
            scriptSpec = NMResultsViewerUI.requestScriptSpec(struct('scriptSpec',scriptSpec));
            fn = NMResultsViewerReportTools.validMatlabIdentifier(scriptSpec.SettingsFunctionName, 'NMResultsViewerReport_settings');
            plans = reportSpec.AnalysisPlans;
            if isstruct(plans) && ~isempty(plans)
                overrides = plans(1).DisplayOverrides;
            else
                overrides = struct();
            end
            if ~isstruct(overrides) || ~isscalar(overrides), overrides=struct(); end
            overrides = NMResultsViewerReportTools.copyMissingFields(overrides,NMResultsViewerReportTools.defaultDisplayOverrides());
            lines={sprintf('function S = %s()',fn), ...
                sprintf('%%%s Public appearance settings for an NM Results Viewer report.',upper(fn)), ...
                '%', ...
                '% Edit values in this file to customize viewer appearance without', ...
                '% changing scientific feature selection or report composition.', ...
                '% Empty or removed values retain the exact PresentationState snapshot.', ...
                '% Invalid/unknown settings fail explicitly during browser-adapter execution.', ...
                '%', ...
                '% Documentation: docs/NM_RESULTS_VIEWER_REPORT_API.md', ...
                '% Machine-readable catalogue: docs/NM_RESULTS_VIEWER_REPORT_API_CATALOG.json', ...
                '', ...
                'S = NMResultsViewerReportTools.defaultDisplayOverrides();'};
            groups={'Imaging2D','Imaging3D','Surface','Volume','Connectivity','Payloads','Contexts'};
            labels={'2-D imaging','Shared 3-D camera and clipping','3-D surface','3-D volume','Connectivity','Payload-specific display semantics','Context-specific overrides'};
            for ii=1:numel(groups)
                field=groups{ii};
                if ~isfield(overrides,field), continue; end
                lines{end+1}=''; %#ok<AGROW>
                lines{end+1}=sprintf('%%%% %s',labels{ii}); %#ok<AGROW>
                groupLines=NMResultsViewerReportTools.displayOverrideAssignmentLines(overrides.(field),['S.' field],true);
                lines=[lines groupLines]; %#ok<AGROW>
            end
            lines{end+1}=''; lines{end+1}='end'; %#ok<AGROW>
            settingsText=strjoin(lines,newline);
        end

        function diagnostic = validateReportBuilder(NM, spec)
            % validateReportBuilder  Smoke-test Results Viewer report components and renderers.
            %
            % diagnostic = NMResultsViewerReportTools.validateReportBuilder(NM, spec)
            % exercises the report-builder catalogue, per-component payload builders,
            % static HTML/SVG renderers, script generation and PDF-renderer probing for
            % the selected Results Viewer context. The method is read-only with respect
            % to NM. It is intended for developer/runtime diagnostics after Results
            % Viewer renderer changes, especially when browser, HTML and PDF exports
            % must remain aligned.
            %
            % spec.AnalysisIndex / analysisIndex: selected NM analysis. Default 1.
            % spec.ResultType / resultType: selected performance result type. Default
            %     is inferred from the analysis when model-performance components are
            %     requested.
            % spec.Source / source: selected performance source, usually "cv".
            % spec.ModelSource / modelSource: optimization model-source selector.
            % spec.ClassifierIndex / classifierIndex: selected learner/classifier.
            % spec.TargetIndex / targetIndex: selected target/label.
            % spec.MultiClassModeIndex / multiClassModeIndex: selected legacy
            %     multi-class mode, where 1 is the aggregate multi-group display and
            %     values >1 are class-vs-rest entries.
            % spec.ReportSpec: optional explicit report specification. When absent,
            %     the enabled catalogue components define the full-report smoke test.
            % spec.IncludeDisabled: logical. If true, disabled catalogue components are
            %     also checked and should remain unavailable with explicit reasons.
            % spec.IncludePdfProbe: logical. If true, probe Edge/Chrome/Chromium or
            %     wkhtmltopdf without writing a PDF. Default true.
            % spec.ExportSpec: optional export/rendering options. ReportMode defaults
            %     to "summary" and Format defaults to "html".
            %
            % Output fields:
            %   diagnostic.ok: true if catalogue, full report, script generation and
            %       all checked enabled components completed without errors.
            %   diagnostic.summary: scalar status summary.
            %   diagnostic.details.componentTable: per-component build/render table.
            %   diagnostic.details.messageTable: warnings/errors with source and stack.
            %   diagnostic.details.catalogueTable: catalogue schema/readiness table.
            %   diagnostic.details.parityTable: report renderer payload-field checks.
            %   diagnostic.pdfProbe: renderer discovery result and probe log.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end

            spec = NMResultsViewerReportTools.validationSpecDefaults(spec);
            exportSpec = NMResultsViewerReportTools.validationExportSpec(spec);
            diagnostic = NMResultsViewerReportTools.validationTemplate();
            diagnostic.createdAt = datestr(now, 30);
            diagnostic.inputSpec = spec;
            diagnostic.exportSpec = exportSpec;

            messageCells = cell(1,0);
            catalogue = NMResultsViewerReportTools.componentTemplate();
            catalogue = catalogue([]);
            catalogueOk = false;
            fullBuildOk = false;
            fullHtmlOk = false;
            scriptOk = false;

            try
                catalogue = NMResultsViewerReportTools.listAvailableComponents(NM, spec);
                catalogueOk = true;
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'catalogue', 'info', '', '', 'Catalogue discovery completed.', []);
            catch ME
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'catalogue', 'error', '', ME.identifier, ME.message, ME);
            end

            [catRows, compRows] = NMResultsViewerReportTools.validationCatalogueRows(catalogue);
            fullReport = NMResultsViewerReportTools.reportTemplate();
            reportSpec = NMResultsViewerReportTools.validationReportSpec(NM, spec);
            diagnostic.reportSpec = reportSpec;

            try
                scriptText = NMResultsViewerReportTools.scriptFromReportSpec(reportSpec, struct('NMVariableName','NM'));
                scriptOk = ~isempty(scriptText);
                if scriptOk
                    messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'script', 'info', '', '', 'MATLAB script generation completed.', []);
                else
                    messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'script', 'warning', '', '', 'MATLAB script generation returned empty text.', []);
                end
            catch ME
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'script', 'error', '', ME.identifier, ME.message, ME);
            end

            try
                fullReport = NMResultsViewerReportTools.buildReport(NM, reportSpec);
                fullBuildOk = isstruct(fullReport) && isfield(fullReport,'Components');
                if fullBuildOk
                    messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'full_report', 'info', '', '', 'Full report payload build completed.', []);
                else
                    messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'full_report', 'warning', '', '', 'Full report payload build did not return component data.', []);
                end
            catch ME
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'full_report', 'error', '', ME.identifier, ME.message, ME);
            end

            if fullBuildOk
                try
                    html = NMResultsViewerReportTools.renderReportHtml(fullReport, exportSpec);
                    fullHtmlOk = ischar(html) || isstring(html);
                    fullHtmlOk = fullHtmlOk && strlength(string(html)) > 0;
                    if fullHtmlOk
                        messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'full_html', 'info', '', '', 'Full static HTML rendering completed.', []);
                    else
                        messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'full_html', 'warning', '', '', 'Full static HTML rendering returned empty content.', []);
                    end
                catch ME
                    messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'full_html', 'error', '', ME.identifier, ME.message, ME);
                end
            end

            if catalogueOk && ~isempty(catalogue)
                includeDisabled = NMResultsViewerReportTools.structLogical(spec, {'IncludeDisabled','includeDisabled'}, false);
                for ii = 1:numel(catalogue)
                    enabled = logical(catalogue(ii).Enabled);
                    if ~enabled && ~includeDisabled
                        compRows(ii).Checked = false;
                        compRows(ii).BuildOk = true;
                        compRows(ii).HtmlOk = true;
                        compRows(ii).ComponentStatus = 'skipped_disabled';
                        compRows(ii).RenderStatus = 'skipped_disabled';
                        compRows(ii).MissingReason = catalogue(ii).MissingReason;
                        continue;
                    end
                    compRows(ii).Checked = true;
                    oneSpec = NMResultsViewerReportTools.validationOneComponentReportSpec(reportSpec, catalogue(ii));
                    try
                        oneReport = NMResultsViewerReportTools.buildReport(NM, oneSpec);
                        [row, componentMessageCells] = NMResultsViewerReportTools.validationInspectOneReport(oneReport, catalogue(ii), exportSpec, enabled);
                        compRows(ii) = NMResultsViewerReportTools.validationMergeComponentRow(compRows(ii), row);
                        messageCells = [messageCells componentMessageCells]; %#ok<AGROW>
                    catch ME
                        compRows(ii).BuildOk = false;
                        compRows(ii).HtmlOk = false;
                        compRows(ii).ComponentStatus = 'error';
                        compRows(ii).RenderStatus = 'error';
                        compRows(ii).ErrorCount = compRows(ii).ErrorCount + 1;
                        compRows(ii).Message = ME.message;
                        messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, char(string(compRows(ii).ComponentId)), 'error', 'build/render', ME.identifier, ME.message, ME);
                    end
                end
            end

            parityRows = NMResultsViewerReportTools.validationParityRows(fullReport);
            pdfProbe = NMResultsViewerReportTools.validationPdfProbe(spec, exportSpec);
            if isfield(pdfProbe,'message') && ~isempty(pdfProbe.message)
                level = 'info';
                if isfield(pdfProbe,'ok') && ~logical(pdfProbe.ok), level = 'warning'; end
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, 'pdf_probe', level, '', '', pdfProbe.message, []);
            end

            messageRows = NMResultsViewerReportTools.validationMessagesFromCells(messageCells);
            summary = NMResultsViewerReportTools.validationSummary(catalogueOk, fullBuildOk, fullHtmlOk, scriptOk, compRows, messageRows, pdfProbe);
            diagnostic.ok = logical(summary.Ok);
            diagnostic.message = summary.Message;
            diagnostic.summary = summary;
            diagnostic.pdfProbe = pdfProbe;
            diagnostic.details.catalogueRows = catRows;
            diagnostic.details.componentRows = compRows;
            diagnostic.details.messageRows = messageRows;
            diagnostic.details.parityRows = parityRows;
            diagnostic.details.catalogueTable = NMResultsViewerReportTools.validationStructTable(catRows);
            diagnostic.details.componentTable = NMResultsViewerReportTools.validationStructTable(compRows);
            diagnostic.details.messageTable = NMResultsViewerReportTools.validationStructTable(messageRows);
            diagnostic.details.parityTable = NMResultsViewerReportTools.validationStructTable(parityRows);
        end

        function components = modelFeatureInspectionComponents(payload, payloadSpec, firstRow, state)
            % modelFeatureInspectionComponents  Build Feature Inspection catalogue from Scientific State.
            %
            % Scientific State is authoritative for capability availability. The
            % normalized Feature Inspection payload is consulted only to enumerate
            % parameterized metric instances exposed by an available capability
            % family; it no longer decides whether the scientific family exists.
            if nargin < 2 || ~isstruct(payloadSpec), payloadSpec=struct();end
            if nargin < 3 || isempty(firstRow),firstRow=1;end
            if ~isfield(payloadSpec,'resultType'),payloadSpec.resultType='model_feature_inspection';end
            if nargin < 4 || isempty(state),state=NMResultsViewerScientificState.fromPayloads({payload},payloadSpec);end

            featureRows=payload.featureTable;
            metricSpecs=NMResultsViewerReportTools.modelFeatureInspectionMetricSpecs(payload,featureRows);
            barAvailable=NMResultsViewerScientificState.hasVisualization(state,'feature_metric_bar');
            distributionAvailable=NMResultsViewerScientificState.hasVisualization(state,'feature_metric_distribution');
            relationshipAvailable=NMResultsViewerScientificState.hasVisualization(state,'feature_metric_relationship');

            ids=cell(1,0);labels=cell(1,0);enabled=false(1,0);reasons=cell(1,0);required=cell(1,0);
            componentTypes=cell(1,0);metricIds=cell(1,0);yMetricIds=cell(1,0);
            fixed={ ...
                'model_feature_inspection.modality_contribution','Modality contribution',{'modality contribution artefact'}; ...
                'model_feature_inspection.component_summary','Component statistics',{'component statistics artefact'}; ...
                'model_feature_inspection.fractionated_decision','Fractionated decision scores',{'out-of-sample fractionated decision scores'}; ...
                'model_feature_inspection.fractionated_individual','Individual Dx contributions',{'subject-by-component fractionated decision scores'}; ...
                'model_feature_inspection.fractionated_population','Population profiles',{'population-level fractionated decision profiles'}; ...
                'model_feature_inspection.fractionated_clusters','Subject clusters',{'fractionated decision clustering of subjects'}; ...
                'model_feature_inspection.component_modality_matrix','Component × modality',{'component-by-modality artefact'}; ...
                'model_feature_inspection.feature_ranking','Feature ranking',{'feature ranking artefact'}; ...
                'model_feature_inspection.feature_metric_table','Feature metric table',{'feature metric table artefact'}};
            fixedTypes={'modality_contribution','component_summary','fractionated_decision','fractionated_individual','fractionated_population','fractionated_clusters','component_modality_matrix','feature_ranking','feature_metric_table'};
            for ii=1:size(fixed,1)
                ids{end+1}=fixed{ii,1};labels{end+1}=fixed{ii,2};required{end+1}=fixed{ii,3}; %#ok<AGROW>
                componentTypes{end+1}=fixedTypes{ii};metricIds{end+1}='';yMetricIds{end+1}=''; %#ok<AGROW>
                enabled(end+1)=NMResultsViewerReportTools.scientificStateComponentAvailable(state,fixed{ii,1}); %#ok<AGROW>
                reasons{end+1}=NMResultsViewerReportTools.stateReasonIfUnavailable(fixed{ii,1},enabled(end)); %#ok<AGROW>
            end
            for mm=1:numel(metricSpecs)
                ids{end+1}=['model_feature_inspection.feature_metric_bar.' metricSpecs(mm).metricId]; %#ok<AGROW>
                labels{end+1}=[metricSpecs(mm).label ' feature payload'];required{end+1}={['Metric values for ' metricSpecs(mm).label]}; %#ok<AGROW>
                componentTypes{end+1}='feature_metric';metricIds{end+1}=metricSpecs(mm).metricId;yMetricIds{end+1}=''; %#ok<AGROW>
                enabled(end+1)=barAvailable&&metricSpecs(mm).available; %#ok<AGROW>
                if enabled(end),reasons{end+1}='';elseif ~barAvailable,reasons{end+1}='Scientific State does not expose visualization feature_metric_bar in the selected analysis context.';else,reasons{end+1}='No finite values are available for this feature metric.';end %#ok<AGROW>

                ids{end+1}=['model_feature_inspection.feature_metric_distribution.' metricSpecs(mm).metricId]; %#ok<AGROW>
                labels{end+1}=[metricSpecs(mm).label ' distribution'];required{end+1}={sprintf('At least %d finite feature values for %s',NMResultsViewerReportTools.minFeatureMetricHistogramCount(),metricSpecs(mm).label)}; %#ok<AGROW>
                componentTypes{end+1}='feature_metric_distribution';metricIds{end+1}=metricSpecs(mm).metricId;yMetricIds{end+1}=''; %#ok<AGROW>
                finiteMetricN=NMResultsViewerReportTools.countFiniteRowsForField(featureRows,metricSpecs(mm).field);
                if isempty(featureRows)&&isfield(payload,'contexts')&&isstruct(payload.contexts)&&~isempty(payload.contexts),finiteMetricN=max([payload.contexts.nFeatures]);end
                enabled(end+1)=distributionAvailable&&metricSpecs(mm).available&&finiteMetricN>=NMResultsViewerReportTools.minFeatureMetricHistogramCount(); %#ok<AGROW>
                if enabled(end),reasons{end+1}='';elseif ~distributionAvailable,reasons{end+1}='Scientific State does not expose visualization feature_metric_distribution in the selected analysis context.';else,reasons{end+1}=NMResultsViewerReportTools.featureMetricHistogramMissingReason(finiteMetricN);end %#ok<AGROW>
            end
            pairRows=NMResultsViewerReportTools.modelFeatureInspectionRelationshipPresets(metricSpecs);
            for pp=1:numel(pairRows)
                ids{end+1}=['model_feature_inspection.feature_metric_relationship.' pairRows(pp).xMetricId '__' pairRows(pp).yMetricId]; %#ok<AGROW>
                labels{end+1}=['Feature metric relationship: ' pairRows(pp).label];required{end+1}={['Feature-level values for ' pairRows(pp).label]}; %#ok<AGROW>
                componentTypes{end+1}='feature_metric_relationship';metricIds{end+1}=pairRows(pp).xMetricId;yMetricIds{end+1}=pairRows(pp).yMetricId; %#ok<AGROW>
                enabled(end+1)=relationshipAvailable&&pairRows(pp).enabled; %#ok<AGROW>
                if enabled(end),reasons{end+1}='';elseif ~relationshipAvailable,reasons{end+1}='Scientific State does not expose visualization feature_metric_relationship in the selected analysis context.';else,reasons{end+1}='The selected feature-metric relationship requires two metrics with finite paired values.';end %#ok<AGROW>
            end
            tail={ ...
                'model_feature_inspection.correlation_matrix','Feature-correlation matrix',{'feature-relation matrix'}; ...
                'model_feature_inspection.feature_network','Feature-relation graph',{'feature-relation graph'}; ...
                'model_feature_inspection.extra_label_generalization','Extra-label generalization',{'extra-label generalization artefact'}; ...
                'model_feature_inspection.spatial_map_summary','Spatial feature-map summary',{'spatial feature-map artefact'}; ...
                'model_feature_inspection.payload','Feature-inspection payload',{'feature-inspection payload'}};
            tailTypes={'feature_relations_matrix','feature_relations_graph','extra_label_generalization','spatial_provenance','technical_payload'};
            for ii=1:size(tail,1)
                ids{end+1}=tail{ii,1};labels{end+1}=tail{ii,2};required{end+1}=tail{ii,3}; %#ok<AGROW>
                componentTypes{end+1}=tailTypes{ii};metricIds{end+1}='';yMetricIds{end+1}=''; %#ok<AGROW>
                enabled(end+1)=NMResultsViewerReportTools.scientificStateComponentAvailable(state,tail{ii,1}); %#ok<AGROW>
                reasons{end+1}=NMResultsViewerReportTools.stateReasonIfUnavailable(tail{ii,1},enabled(end)); %#ok<AGROW>
            end

            tmpl=NMResultsViewerReportTools.componentTemplate();components=repmat(tmpl,1,numel(ids));
            for ii=1:numel(ids)
                components(ii).Id=ids{ii};components(ii).Label=labels{ii};components(ii).Viewspace='model_feature_inspection';
                components(ii).Enabled=logical(enabled(ii));components(ii).MissingReason=reasons{ii};components(ii).RequiredArtifacts=required{ii};
                components(ii).DefaultLayout=NMResultsViewerReportTools.componentLayoutTemplate();components(ii).DefaultLayout.Row=firstRow+ii-1;components(ii).DefaultLayout.Order=firstRow+ii-1;components(ii).DefaultLayout.Group='model_feature_inspection';
                components(ii).PayloadSpec=payloadSpec;components(ii).PayloadSpec.resultType='model_feature_inspection';
                components(ii).Instance.ComponentType=componentTypes{ii};
                components(ii).Instance.MetricId=metricIds{ii};
                components(ii).Instance.YMetricId=yMetricIds{ii};
            end
        end

        function [component, session] = buildModelFeatureInspectionComponentWithSession(session, compSpec, reportSpec, component)
            % buildModelFeatureInspectionComponentWithSession  Build one Model feature inspection report component.
            %
            % [component,session] = NMResultsViewerReportTools.buildModelFeatureInspectionComponentWithSession(session, compSpec, reportSpec, component)
            % builds a component from the public Model feature inspection payload API.
            % The function is read-only: it calls
            % NMResultsViewerTools.getModelFeatureInspectionPayload, selects the
            % requested table/plot subpayload, and returns fixed-schema component fields
            % for browser rendering, report export, generated MATLAB scripts and
            % direct API callers. It does not recompute VIS models, mutate NM, write
            % files, open figures or inspect browser DOM state.
            %
            % compSpec.Id selects one model_feature_inspection.* component. The returned
            % component exposes Tables for CSV/XLSX/MAT/JSON sidecars and PlotPayload
            % placeholders for Stage 10A.3/10A.4 renderers. Unsupported substreams are
            % returned as unavailable with explicit MissingReason text.
            if nargin < 4 || ~isstruct(component)
                component = NMResultsViewerReportTools.reportComponentTemplate();
                if nargin >= 2 && isstruct(compSpec)
                    component.Id = compSpec.Id;
                    component.Title = compSpec.Title;
                    component.Viewspace = compSpec.Viewspace;
                    component.Layout = compSpec.Layout;
                end
            end
            if nargin < 3 || ~isstruct(reportSpec), reportSpec = NMResultsViewerReportTools.reportSpecTemplate(); end
            id = compSpec.Id;
            [baseId, metricId, yMetricId] = NMResultsViewerReportTools.modelFeatureInspectionComponentIdentity(compSpec);
            payloadSpec = NMResultsViewerReportTools.componentPayloadSpec(compSpec, reportSpec, 'model_feature_inspection');
            payloadSpec.resultType = 'model_feature_inspection';
            if strcmp(baseId, 'model_feature_inspection.feature_metric_relationship') && ~isfield(payloadSpec, 'maxFeatures')
                payloadSpec.maxFeatures = 2000;
            end
            [payload, session] = NMResultsViewerReportTools.reportSessionPayload(session, 'model_feature_inspection', payloadSpec);
            component.Payload = NMResultsViewerReportTools.modelFeatureInspectionPayloadSummary(payload);
            component.Tables = struct();
            component.SidecarTables = struct();
            component.PlotPayload = struct('componentScopeLabel','','componentSourceLabel','', ...
                'componentSortLabel','','componentSourceRowCount',NaN,'componentTopK',NaN);
            component.Options = compSpec.Options;

            payloadOk = isstruct(payload) && isfield(payload,'kind') && strcmpi(char(string(payload.kind)), 'model_feature_inspection') && ...
                (payload.ok || NMResultsViewerReportTools.payloadHasAny(payload, {'featureTable','matrixPayloads','networkPayloads','spatialMaps'}));
            if ~payloadOk
                component.Status = 'unavailable';
                component.MissingReason = NMResultsViewerReportTools.payloadMessage(payload, 'Model feature inspection payload is unavailable.');
                return;
            end

            featureRows = payload.featureTable;
            matrixPayloads = payload.matrixPayloads;
            networkPayloads = payload.networkPayloads;
            spatialMaps = payload.spatialMaps;
            componentAnalysis = payload.componentAnalysis;
            metricSpecs = NMResultsViewerReportTools.modelFeatureInspectionMetricSpecs(payload, featureRows);
            capturedState = NMResultsViewerReportTools.featureInspectionViewState(component.Options);
            switch baseId
                case 'model_feature_inspection.feature_ranking'
                    rows = NMResultsViewerReportTools.modelFeatureInspectionRowsForFields(featureRows, {'featureName','displayValue','displaySE','thresholdPassed','sortAbsRank','sortSignedRank','tooltipSourceField','tooltipProvenanceSummary'});
                    component.Tables.featureRanking = rows;
                    component.PlotPayload.featureRows = rows;
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No feature-ranking rows are available.');
                case 'model_feature_inspection.feature_metric_table'
                    rows = NMResultsViewerReportTools.modelFeatureInspectionMetricTableRows(featureRows, metricSpecs);
                    if payload.selectedFeatureContext.isCombined
                        for rr=1:numel(rows)
                            member=payload.contexts(strcmp({payload.contexts.contextId},featureRows(rr).contextId));
                            rows(rr).modality=member.modalityLabel;
                        end
                    end
                    component.Tables.featureMetricTable = rows;
                    component.SidecarTables.featureRows = featureRows;
                    component.SidecarTables.availableMetrics = metricSpecs;
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No feature-level metric values are available.');
                case 'model_feature_inspection.feature_metric_bar'
                    [metricSpec, foundMetric] = NMResultsViewerReportTools.modelFeatureInspectionMetricById(metricSpecs, metricId);
                    instance = component.Instance;
                    representationId = strtrim(instance.RepresentationId);
                    supportDomain = strtrim(instance.SupportDomain);
                    presentationMode = strtrim(instance.PresentationMode);
                    artifactRequired = instance.PresentationArtifactRequired;
                    hasArtifact = isfield(component.Options,'ReportPresentationArtifact') && ~isempty(component.Options.ReportPresentationArtifact);
                    if isempty(representationId) || isempty(supportDomain) || isempty(presentationMode)
                        error('NMResultsViewerReportTools:MissingFeatureRepresentationIdentity', ...
                            'Feature metric %s requires structured Instance.RepresentationId, SupportDomain and PresentationMode.',metricId);
                    end
                    if artifactRequired
                        if ~hasArtifact
                            error('NMResultsViewerReportTools:MissingFeaturePresentationArtifact', ...
                                'Feature metric %s requires representation %s in support domain %s, but no report presentation artifact was supplied.',metricId,representationId,supportDomain);
                        end
                        [artifactOk,artifactMessage,artifact] = NMResultsViewerExportTools.validateArtifact(component.Options.ReportPresentationArtifact);
                        if ~artifactOk || ~strcmp(NMSerializationTools.textField(artifact,'kind',''),'visual')
                            if artifactOk, artifactMessage='The supplied report presentation is not visual.'; end
                            error('NMResultsViewerReportTools:InvalidFeaturePresentationArtifact','%s',artifactMessage);
                        end
                        sidecarFields = {'featureIndex','featureName','featureKind',metricSpec.field}; if ~isempty(metricSpec.seField), sidecarFields{end+1}=metricSpec.seField; end
                        rows = NMResultsViewerReportTools.modelFeatureInspectionRowsForFields(featureRows,sidecarFields);
                        rows = NMResultsViewerReportTools.modelFeatureInspectionRowsWithFiniteField(rows,metricSpec.field);
                        component.SidecarTables.featureMetricRows = rows;
                        component.PlotPayload.reportPresentationArtifact = artifact;
                        component.PlotPayload.representationRequirement = struct('representationId',representationId,'supportDomain',supportDomain,'presentationMode',presentationMode);
                        if foundMetric
                            presentationLabel = NMResultsViewerReportTools.safeField(component.Options,'ReportPresentationLabel','viewer presentation');
                            component.Title = sprintf('%s · %s',metricSpec.label,char(string(presentationLabel)));
                        end
                    else
                        if hasArtifact
                            error('NMResultsViewerReportTools:UnexpectedFeaturePresentationArtifact', ...
                                'Feature metric %s declares non-artifact representation %s but also supplies a visual artifact.',metricId,representationId);
                        end
                        if ~strcmp(representationId,'feature.metric_bar') || ~strcmp(supportDomain,'tabular') || ~strcmp(presentationMode,'bar')
                            error('NMResultsViewerReportTools:InvalidTabularFeatureRepresentation', ...
                                'Feature metric %s may render a bar only when representation feature.metric_bar, support domain tabular and presentation mode bar are explicitly selected.',metricId);
                        end
                        % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
                        metricOptions = NMResultsViewerReportTools.featureMetricOptionsFromComponentOptions(component.Options, capturedState.panels, metricId);
                        metricOptions.ApplyPagination = true;
                        [rows, metricSpec] = NMResultsViewerReportTools.modelFeatureInspectionRowsForMetric(featureRows, metricSpec, metricOptions);
                        component.Options = NMResultsViewerReportTools.mergeStructs(component.Options, metricOptions);
                        component.Tables.featureMetricBars = rows;
                        component.SidecarTables.featureMetricRows = rows;
                        component.PlotPayload.featureRows = rows;
                        component.PlotPayload.metricSpec = metricSpec;
                        component.PlotPayload.representationRequirement = struct('representationId',representationId,'supportDomain',supportDomain,'presentationMode',presentationMode);
                        if isfield(metricSpec,'displayContract')
                            component.PlotPayload.displayContract = metricSpec.displayContract;
                        end
                        if foundMetric, component.Title = [metricSpec.label ' bar plot']; end
                    end
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No finite values are available for the selected feature metric.');
                case 'model_feature_inspection.feature_metric_distribution'
                    [metricSpec, foundMetric] = NMResultsViewerReportTools.modelFeatureInspectionMetricById(metricSpecs, metricId);
                    % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
                    metricOptions = NMResultsViewerReportTools.featureMetricOptionsFromComponentOptions(component.Options, capturedState.panels, metricId);
                    metricOptions.ApplyPagination = false;
                    [rows, metricSpec] = NMResultsViewerReportTools.modelFeatureInspectionRowsForMetric(featureRows, metricSpec, metricOptions);
                    component.Options = NMResultsViewerReportTools.mergeStructs(component.Options, metricOptions);
                    component.Tables.featureMetricDistribution = NMResultsViewerReportTools.modelFeatureInspectionDistributionSummaryRows(rows, 'displayValue');
                    component.SidecarTables.featureMetricRows = rows;
                    component.PlotPayload.featureRows = rows;
                    component.PlotPayload.metricSpec = metricSpec;
                    if isfield(metricSpec,'displayContract')
                        component.PlotPayload.displayContract = metricSpec.displayContract;
                    end
                    if foundMetric
                        component.Title = [metricSpec.label ' distribution'];
                    end
                    finiteMetricN = NMResultsViewerReportTools.countFiniteRowsForField(rows, 'displayValue');
                    if finiteMetricN < NMResultsViewerReportTools.minFeatureMetricHistogramCount()
                        component.Status = 'unavailable';
                        component.MissingReason = NMResultsViewerReportTools.featureMetricHistogramMissingReason(finiteMetricN);
                    else
                        component.Status = NMResultsViewerReportTools.statusForRows(rows);
                        component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No finite values are available for the selected feature metric distribution.');
                    end
                case 'model_feature_inspection.feature_metric_relationship'
                    [xSpec, okX] = NMResultsViewerReportTools.modelFeatureInspectionMetricById(metricSpecs, metricId);
                    [ySpec, okY] = NMResultsViewerReportTools.modelFeatureInspectionMetricById(metricSpecs, yMetricId);
                    % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
                    xOptions = NMResultsViewerReportTools.featureMetricOptionsFromComponentOptions(component.Options, capturedState.panels, metricId);
                    % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
                    yOptions = NMResultsViewerReportTools.featureMetricOptionsFromComponentOptions(component.Options, capturedState.panels, yMetricId);
                    [rows, xSpec, ySpec] = NMResultsViewerReportTools.modelFeatureInspectionRelationshipRows( ...
                        featureRows, xSpec, ySpec, xOptions, yOptions);
                    component.Tables.featureMetricRelationship = rows;
                    component.SidecarTables.featureMetricRelationshipRows = rows;
                    component.PlotPayload.pointRows = rows;
                    component.PlotPayload.xMetricSpec = xSpec;
                    component.PlotPayload.yMetricSpec = ySpec;
                    if isfield(xSpec,'displayContract') && isfield(ySpec,'displayContract')
                        component.PlotPayload.xDisplayContract = xSpec.displayContract;
                        component.PlotPayload.yDisplayContract = ySpec.displayContract;
                    end
                    if okX && okY
                        component.Title = sprintf('Feature metric relationship: %s vs %s', xSpec.label, ySpec.label);
                    end
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'The selected pair of feature metrics does not expose finite paired values.');
                case 'model_feature_inspection.correlation_matrix'
                    [relationOptions, relationState, panelVisible] = ...
                        NMResultsViewerReportTools.modelFeatureRelationOptionsFromComponentOptions(component.Options, capturedState.panels, 'relationMatrix');
                    component.Options = NMResultsViewerReportTools.mergeStructs(component.Options, relationOptions);
                    if ~panelVisible
                        component.Status = 'unavailable';
                        component.MissingReason = 'The Feature-correlation matrix panel was hidden in the captured browser state and is therefore excluded from Report Builder output.';
                        return;
                    end
                    relationSpec = payloadSpec;
                    relationSpec.resultType = 'model_feature_inspection';
                    relationSpec.relationState = relationState;
                    [relationPayload, session] = NMResultsViewerReportTools.reportSessionPayload(session, 'model_feature_relation', relationSpec);
                    relationPayload = NMResultsViewerReportTools.attachRelationDisplayContract(relationPayload,relationOptions,'matrix');
                    component.PlotPayload.relationPayload = relationPayload;
                    component.PlotPayload.displayContract = NMResultsViewerReportTools.safeField( ...
                        NMResultsViewerReportTools.safeField(relationPayload,'view',struct()),'displayContract',struct());
                    component.Tables.featureRelationDetails = NMResultsViewerReportTools.modelFeatureRelationDetailsRows(relationPayload, relationOptions, capturedState, 'matrix');
                    if relationPayload.ok && ...
                            relationPayload.view.available
                        component.Status = 'ok';
                        component.MissingReason = '';
                    else
                        component.Status = 'unavailable';
                        component.MissingReason = NMResultsViewerReportTools.payloadMessage(relationPayload, ...
                            'The captured Feature-correlation matrix state could not be materialized.');
                    end
                case 'model_feature_inspection.feature_network'
                    [relationOptions, relationState, panelVisible, capturedRobustness] = ...
                        NMResultsViewerReportTools.modelFeatureRelationOptionsFromComponentOptions(component.Options, capturedState.panels, 'relationGraph');
                    component.Options = NMResultsViewerReportTools.mergeStructs(component.Options, relationOptions);
                    if ~panelVisible
                        component.Status = 'unavailable';
                        component.MissingReason = 'The Feature-relation graph panel was hidden in the captured browser state and is therefore excluded from Report Builder output.';
                        return;
                    end
                    relationSpec = payloadSpec;
                    relationSpec.resultType = 'model_feature_inspection';
                    relationSpec.relationState = relationState;
                    [relationPayload, session] = NMResultsViewerReportTools.reportSessionPayload(session, 'model_feature_relation', relationSpec);
                    relationPayload = NMResultsViewerReportTools.attachRelationDisplayContract(relationPayload,relationOptions,'graph');
                    component.PlotPayload.relationPayload = relationPayload;
                    component.PlotPayload.displayContract = NMResultsViewerReportTools.safeField( ...
                        NMResultsViewerReportTools.safeField(relationPayload,'view',struct()),'displayContract',struct());
                    component.PlotPayload.graphRobustness = NMResultsViewerReportTools.validCapturedGraphRobustness(capturedRobustness, relationPayload);
                    relationOptions.GraphRobustnessValid = NMResultsViewerReportTools.safeLogicalDefault(component.PlotPayload.graphRobustness,'available',false) && ...
                        NMResultsViewerReportTools.safeLogicalDefault(component.PlotPayload.graphRobustness,'enabled',false);
                    relationOptions.GraphRobustnessSelectedDensity = NMResultsViewerReportTools.safeField(component.PlotPayload.graphRobustness,'selectedDensity',NaN);
                    component.Options = NMResultsViewerReportTools.mergeStructs(component.Options, relationOptions);
                    component.Tables.featureRelationDetails = NMResultsViewerReportTools.modelFeatureRelationDetailsRows(relationPayload, relationOptions, capturedState, 'graph');
                    component.Tables.graphSummary = NMResultsViewerReportTools.modelFeatureGraphSummaryRows(relationPayload);
                    component.Tables.nodeStatistics = NMResultsViewerReportTools.modelFeatureGraphNodeRows(relationPayload);
                    component.Tables.relationPatterns = NMResultsViewerReportTools.modelFeatureRelationPatternRows(relationPayload);
                    view = relationPayload.view;
                    graph = view.graph;
                    if relationPayload.ok && ...
                            graph.available
                        component.Status = 'ok';
                        component.MissingReason = '';
                    else
                        component.Status = 'unavailable';
                        component.MissingReason = NMResultsViewerReportTools.payloadMessage(relationPayload, ...
                            'The captured Feature-relation graph state could not be materialized.');
                    end
                case 'model_feature_inspection.extra_label_generalization'
                    extra = payload.extraLabelGeneralization;
                    rows = extra.rows;
                    component.Payload.extraLabelGeneralization = extra;
                    component.Tables.extraLabelGeneralization = rows;
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, extra.message);
                case {'model_feature_inspection.fractionated_individual','model_feature_inspection.fractionated_decision'}
                    % Both report components consume the same authoritative Dx matrices.
                    isIndividual=strcmp(component.Id,'model_feature_inspection.fractionated_individual');
                    scope='selected';
                    if isIndividual,scope='all';end
                    scores=NMResultsViewerTools.getModelFeatureInspectionFractionatedDecisionPayload( ...
                        session.CurrentNM,payload,scope);
                    if ~scores.ok
                        component.Status='unavailable';component.MissingReason=scores.message;return;
                    end
                    rows=NMResultsViewerReportTools.fractionatedDecisionReportRows(scores);
                    component.Status=NMResultsViewerReportTools.statusForRows(rows);
                    if isIndividual
                        % A blank Case ID is an explicit all-subject matrix request.
                        % Restrict exported rows only when the user supplies Case IDs
                        % or a subject limit; never choose subject one by default.
                        opts=component.Options;
                        if isempty(opts.CaseId)
                            selected=1:numel(scores.caseIds);
                        else
                            requested=strtrim(strsplit(opts.CaseId,','));
                            if any(cellfun(@isempty,requested))
                                error('NMResultsViewerReportTools:InvalidFractionatedCaseList', ...
                                    'Individual Dx Case ID list contains an empty identifier.');
                            end
                            if numel(unique(requested))~=numel(requested)
                                error('NMResultsViewerReportTools:InvalidFractionatedCaseList', ...
                                    'Individual Dx Case IDs must be unique.');
                            end
                            [matched,selected]=ismember(requested,scores.caseIds);
                            if ~all(matched)
                                error('NMResultsViewerReportTools:UnknownFractionatedIndividualCase', ...
                                    'Individual Dx Case ID %s is not on the canonical analysis case axis.',requested{find(~matched,1)});
                            end
                        end
                        if opts.MaxSubjects>0,selected=selected(1:min(numel(selected),opts.MaxSubjects));end
                        nCases=numel(scores.caseIds);
                        nComponents=numel(scores.componentIndices);
                        component.Tables.fractionatedIndividual=rows;
                        showProfile=numel(selected)==1;
                        if isempty(opts.CaseId),showProfile=false;end
                        if showProfile
                            profile=rows(selected:nCases:end);
                            switch opts.ProfileSort
                                case 'absolute_desc', [~,order]=sort(abs([profile.meanDecisionFraction]),'descend','MissingPlacement','last');
                                case 'absolute_asc', [~,order]=sort(abs([profile.meanDecisionFraction]),'ascend','MissingPlacement','last');
                                case 'signed_desc', [~,order]=sort([profile.meanDecisionFraction],'descend','MissingPlacement','last');
                                case 'signed_asc', [~,order]=sort([profile.meanDecisionFraction],'ascend','MissingPlacement','last');
                                case 'retained_asc',order=1:nComponents;
                                case 'retained_desc',order=nComponents:-1:1;
                            end
                            component.PlotPayload.fractionatedIndividualProfile=profile(order);
                        else
                            component.PlotPayload.fractionatedIndividualMatrix=struct( ...
                                'values',scores.mean(selected,:), ...
                                'caseIds',{scores.caseIds(selected)}, ...
                                'componentLabels',{scores.componentLabels});
                        end
                        component.Payload.fractionatedIndividual=struct('contextId',scores.contextId, ...
                            'caseIds',{scores.caseIds(selected)},'caseCount',numel(selected), ...
                            'componentCount',nComponents,'coverageAvailable',scores.coverageAvailable, ...
                            'stateSource',opts.StateSource);
                        missingReason='No subject-by-component decision contributions are available.';
                    else
                        col=scores.selectedColumn;
                        component.Tables.fractionatedDecision=rows;
                        component.Payload.fractionatedDecision=struct('contextId',scores.contextId, ...
                            'componentIndex',scores.componentIndices(col), ...
                            'componentLabel',scores.componentLabels{col}, ...
                            'coverageAvailable',scores.coverageAvailable, ...
                            'sourceFields',{{'FracDec_CV2_mean','FracDec_CV2_sd','FracDec_CV2_se'}});
                        missingReason='No subject-level fractionated decision contributions are available.';
                    end
                    component.MissingReason=NMResultsViewerReportTools.reasonIfUnavailable(component.Status,missingReason);
                case 'model_feature_inspection.fractionated_population'
                    scores=NMResultsViewerTools.getModelFeatureInspectionFractionatedDecisionPayload( ...
                        session.CurrentNM,payload,'all');
                    if ~scores.ok
                        component.Status='unavailable';component.MissingReason=scores.message;return;
                    end
                    opts=component.Options;rows=scores.populationRows;
                    orderBy=opts.SortBy;
                    if strcmp(orderBy,'component'),orderBy='index';end
                    if opts.SortAscending
                        order=scores.populationOrder.(orderBy).ascending;
                    else
                        order=scores.populationOrder.(orderBy).descending;
                    end
                    rows=rows(order);
                    component.Tables.fractionatedPopulation=rows;
                    component.Payload.fractionatedPopulation=struct('contextId',scores.contextId, ...
                        'caseCount',numel(scores.caseIds),'componentCount',numel(scores.componentIndices), ...
                        'metric',opts.Metric,'sortBy',opts.SortBy,'sortAscending',opts.SortAscending, ...
                        'stateSource',opts.StateSource);
                    component.Status=NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason=NMResultsViewerReportTools.reasonIfUnavailable(component.Status, ...
                        'No population-level decision contributions are available.');
                case 'model_feature_inspection.fractionated_clusters'
                    opts=component.Options;
                    if ~strcmp(payloadSpec.source,'cv')
                        component.Status='unavailable';
                        component.MissingReason='Subject clustering requires the CV Feature Inspection source.';return;
                    end
                    auto=[];
                    if strcmp(opts.Selection,'auto')
                        auto=struct('minClusters',opts.MinClusters,'maxClusters',opts.MaxClusters, ...
                            'criterion',opts.Criterion,'bootstrapIterations',opts.BootstrapIterations);
                    end
                    clusters=NMResultsViewerTools.getModelFeatureInspectionFractionatedClusters( ...
                        session.CurrentNM,payload,payloadSpec,opts.Mode,opts.ClusterCount,auto);
                    if ~clusters.ok
                        component.Status='unavailable';component.MissingReason=clusters.message;return;
                    end
                    component.Tables.clusterSubjects=clusters.subjectRows;
                    component.Tables.clusterGroups=clusters.groups;
                    component.Tables.clusterProfiles=clusters.componentProfiles;
                    ks=clusters.optimization.testedClusters;
                    component.Tables.clusterOptimization=struct('k',num2cell(ks(:)'), ...
                        'criterionValue',num2cell(clusters.optimization.values(:)'), ...
                        'selected',num2cell(ks(:)'==clusters.clusterCount));
                    consensus=clusters.consensusHeatmap;
                    if ~isempty(consensus.values)
                        [rr,cc]=ndgrid(1:size(consensus.values,1));
                        component.Tables.clusterConsensus=struct('rowBin',num2cell(rr(:)), ...
                            'columnBin',num2cell(cc(:)), ...
                            'frequency',num2cell(consensus.values(:)));
                    end
                    component.PlotPayload.clusterProfileOrder=clusters.profileComponentOrder;
                    component.Payload.fractionatedClusters=struct('clusterCount',clusters.clusterCount, ...
                        'performanceMetric',clusters.performanceMetric,'distanceDefinition',clusters.distanceDefinition, ...
                        'message',clusters.message,'optimization',clusters.optimization, ...
                        'consensusBinEdges',consensus.binEdges);
                    component.Status='ok';
                case 'model_feature_inspection.component_summary'
                    component.Options = NMResultsViewerReportTools.modelFeatureInspectionFusionPanelOptions( ...
                        component.Options, capturedState.panels, 'component_statistics');
                    [rows,componentMetric,sourceRows,scopeLabel,sourceLabel,sortLabel,topK] = ...
                        NMResultsViewerReportTools.modelFeatureInspectionComponentRowsForOptions(componentAnalysis, component.Options, capturedState.selectedFeatureContext);
                    component.Tables.componentSummary = rows;
                    component.SidecarTables.componentStatisticsNormalized = sourceRows;
                    component.PlotPayload.componentRows = rows;
                    component.PlotPayload.componentMetric = componentMetric;
                    component.PlotPayload.componentScopeLabel = scopeLabel;
                    component.PlotPayload.componentSourceLabel = sourceLabel;
                    component.PlotPayload.componentSortLabel = sortLabel;
                    component.PlotPayload.componentSourceRowCount = numel(sourceRows);
                    component.PlotPayload.componentTopK = topK;
                    component.Metadata = NMResultsViewerReportTools.mergeStructs(component.Metadata, ...
                        NMResultsViewerReportTools.modelFeatureInspectionReportMetadata(payload, capturedState.schemaVersion));
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No component statistics are available for the selected normalized scope and source.');
                case 'model_feature_inspection.modality_contribution'
                    rows = componentAnalysis.modalityShareTable;
                    rows = NMResultsViewerReportTools.modelFeatureInspectionSortRows(rows, 'medianShare', 'descend');
                    component.Tables.modalityContribution = rows;
                    component.PlotPayload.modalityRows = rows;
                    component.Metadata = NMResultsViewerReportTools.mergeStructs(component.Metadata, ...
                        NMResultsViewerReportTools.modelFeatureInspectionReportMetadata(payload, capturedState.schemaVersion));
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No modality-contribution rows are available.');
                case 'model_feature_inspection.component_modality_matrix'
                    rows = componentAnalysis.componentModalityTable;
                    component.Tables.componentModalityMatrix = rows;
                    component.PlotPayload.componentModalityRows = rows;
                    component.PlotPayload.matrixStatistic = NMResultsViewerReportTools.modelFeatureInspectionMatrixStatisticOption(component.Options, capturedState.panels);
                    component.Metadata = NMResultsViewerReportTools.mergeStructs(component.Metadata, ...
                        NMResultsViewerReportTools.modelFeatureInspectionReportMetadata(payload, capturedState.schemaVersion));
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No component-by-modality contribution rows are available.');
                case 'model_feature_inspection.spatial_map_summary'
                    rows = NMResultsViewerReportTools.modelFeatureInspectionSpatialSummaryRows(spatialMaps);
                    component.Tables.spatialMapSummary = rows;
                    component.PlotPayload.spatialMaps = spatialMaps;
                    component.Status = NMResultsViewerReportTools.statusForRows(rows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No spatial feature-map descriptors are available.');
                case 'model_feature_inspection.payload'
                    component.Payload = payload;
                    component.SidecarTables.featureTable = payload.featureTable;
                    component.SidecarTables.measures = payload.measures;
                    component.SidecarTables.contexts = payload.contexts;
                    component.Status = 'ok';
                otherwise
                    error('NMResultsViewerReportTools:UnknownModelFeatureInspectionComponentId', ...
                        'Unknown Model feature inspection report component id "%s".',id);
            end
        end

        function [html, renderStatus] = renderFeatureInspectionComponentHtml(component, exportSpec)
            % renderFeatureInspectionComponentHtml  Render Stage 10A feature-inspection components as static HTML.
            %
            % [html, renderStatus] = NMResultsViewerReportTools.renderFeatureInspectionComponentHtml(component, exportSpec)
            % renders Model feature inspection components built from the normalized
            % payload contract. Stage 10A.3 renders compact static SVG summaries for feature bars,
            % distributions, volcano plots, matrix/network views and component
            % summaries where a suitable payload exists. It remains public so API
            % users and generated scripts can produce static reports without invoking
            % browser-only code.
            exportSpec = NMResultsViewerReportTools.copyMissingFields(exportSpec, ...
                NMResultsViewerReportTools.exportSpecDefaults());
            maxRows = exportSpec.MaxSummaryRows;
            compOptions = component.Options;
            if isstruct(compOptions) && isfield(compOptions,'TableRowCount') && isnumeric(compOptions.TableRowCount) && ~isempty(compOptions.TableRowCount) && isfinite(compOptions.TableRowCount(1))
                maxRows = max(1, min(500, round(double(compOptions.TableRowCount(1)))));
            end
            id = component.Id;
            if strcmp(id, 'model_feature_inspection.payload')
                renderStatus = 'sidecar_only';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'Full Model feature inspection payload is available in MAT/JSON sidecars; it is not dumped into the scientific report body.');
                return;
            end
            fig = '';
            tableHtml = '';
            body = '';
            [baseId, ~, ~] = NMResultsViewerReportTools.modelFeatureInspectionComponentIdentity(component);
            switch baseId
                case 'model_feature_inspection.feature_metric_bar'
                    rows = NMResultsViewerReportTools.componentTable(component, 'featureMetricBars');
                    plotPayload = component.PlotPayload;
                    metricSpec = NMResultsViewerReportTools.safeField(plotPayload, 'metricSpec', struct());
                    artifact = NMResultsViewerReportTools.safeField(plotPayload,'reportPresentationArtifact',struct());
                    if isstruct(artifact) && ~isempty(fieldnames(artifact))
                        fig = NMResultsViewerExportTools.artifactHtml(artifact);
                        tableHtml = '';
                    else
                        figOpts = NMResultsViewerReportTools.featureMetricFigureOptions(component, exportSpec, metricSpec);
                        distRows = NMResultsViewerReportTools.safeField(plotPayload, 'distributionRows', []);
                        if isstruct(distRows) && ~isempty(distRows)
                            fig = NMResultsViewerReportFigureTools.featureInspectionMetricPanelSvg(rows, distRows, figOpts);
                        else
                            fig = NMResultsViewerReportFigureTools.featureInspectionBarsSvg(rows, figOpts);
                        end
                        tableHtml = NMResultsViewerReportTools.featureMetricCompactTableHtml(rows, maxRows);
                    end
                case 'model_feature_inspection.feature_metric_distribution'
                    rows = component.SidecarTables.featureMetricRows;
                    metricSpec = component.PlotPayload.metricSpec;
                    figOpts = NMResultsViewerReportTools.featureMetricFigureOptions(component, exportSpec, metricSpec);
                    figOpts.Title = 'Distribution';
                    figOpts.XLabel = metricSpec.label;
                    fig = NMResultsViewerReportFigureTools.featureInspectionHistogramSvg(rows, 'displayValue', figOpts);
                    tableHtml = '';
                case 'model_feature_inspection.feature_metric_relationship'
                    rows = component.Tables.featureMetricRelationship;
                    xSpec = component.PlotPayload.xMetricSpec;
                    ySpec = component.PlotPayload.yMetricSpec;
                    fig = NMResultsViewerReportFigureTools.featureInspectionRelationshipSvg(rows, 'Title',component.Title, 'PlotTitle','Relationship plot', 'XLabel',xSpec.label, 'YLabel',ySpec.label, 'XMetricSpec',xSpec, 'YMetricSpec',ySpec);
                    tableHtml = NMResultsViewerReportTools.structRowsHtml(rows, {'featureName','xValue','yValue'}, {'Feature','X value','Y value'}, maxRows);
                case 'model_feature_inspection.feature_metric_table'
                    rows = component.Tables.featureMetricTable;
                    [fields, labels] = NMResultsViewerReportTools.featureMetricVisibleTableColumns(rows);
                    tableHtml = NMResultsViewerReportTools.structRowsHtml(rows, fields, labels, maxRows);
                case 'model_feature_inspection.correlation_matrix'
                    relationPayload = component.PlotPayload.relationPayload;
                    body = NMResultsViewerReportTools.modelFeatureRelationMatrixReportHtml(component, relationPayload, maxRows);
                    fig = body; % The body contains a deterministic matrix figure and is not table-only.
                case 'model_feature_inspection.feature_network'
                    relationPayload = component.PlotPayload.relationPayload;
                    robustness = component.PlotPayload.graphRobustness;
                    body = NMResultsViewerReportTools.modelFeatureGraphReportHtml(component, relationPayload, robustness, maxRows);
                    fig = body; % The body contains the full graph and optional pattern/robustness figures.
                case 'model_feature_inspection.fractionated_individual'
                    rows=component.Tables.fractionatedIndividual;
                    selected=component.Payload.fractionatedIndividual.caseIds;
                    showProfile=numel(selected)==1;
                    if isempty(component.Options.CaseId),showProfile=false;end
                    if showProfile
                        profile=component.PlotPayload.fractionatedIndividualProfile;
                        nPlot=min(numel(profile),component.Options.MaxPlotComponents);
                        fig=NMResultsViewerReportFigureTools.componentShareSvg(profile(1:nPlot), ...
                            'Title',['Individual decision contributions: ' selected{1}], ...
                            'ValueField','meanDecisionFraction','LabelField','componentLabel', ...
                            'XLabel','Signed normalized-margin contribution', ...
                            'CategoricalY',true,'MaxRows',nPlot);
                        tableHtml=NMResultsViewerReportTools.structRowsHtml(profile, ...
                            {'caseId','componentIndex','componentLabel','meanDecisionFraction','sdDecisionFraction','seDecisionFraction','nValid'}, ...
                            {'Subject','Component #','Component','Mean Dx','SD','SE','Valid models'},maxRows);
                    else
                        matrix=component.PlotPayload.fractionatedIndividualMatrix;
                        fig=NMResultsViewerReportFigureTools.continuousMatrixHtml( ...
                            matrix.values,matrix.caseIds,matrix.componentLabels, ...
                            struct('ValueLabel','Signed normalized-margin contribution', ...
                            'RowHeading','Case ID','ColumnHeading','retained component indices', ...
                            'Signed',true,'DisplayValues',false,'HighlightRow',NaN));
                        tableHtml='';
                    end
                    note=sprintf('<p class="small">%d displayed subjects × %d retained components (%d displayed Dx cells). Complete subject-by-component data are retained in the numerical report table and MAT/JSON/CSV/XLSX output. NaN denotes an unavailable contribution.</p>', ...
                        component.Payload.fractionatedIndividual.caseCount, ...
                        component.Payload.fractionatedIndividual.componentCount,component.Payload.fractionatedIndividual.caseCount*component.Payload.fractionatedIndividual.componentCount);
                    body=[fig note tableHtml];
                case 'model_feature_inspection.fractionated_population'
                    rows=component.Tables.fractionatedPopulation;
                    metric=component.Options.Metric;
                    labels=struct('concentration','Concentration S','effectiveSubjects','Effective N', ...
                        'meanAbsoluteDx','Mean |Dx|','positivePct','Positive %','negativePct','Negative %', ...
                        'zeroPct','Zero %','observed','Finite N','coveragePct','Coverage %');
                    plotRows=rows(isfinite([rows.(metric)]));
                    nPlot=min(numel(plotRows),component.Options.MaxPlotComponents);
                    fig=NMResultsViewerReportFigureTools.componentShareSvg(plotRows(1:nPlot), ...
                        'Title','Population profiles of fractionated decision scores', ...
                        'ValueField',metric,'LabelField','component', ...
                        'XLabel',labels.(metric),'CategoricalY',true,'MaxRows',nPlot);
                    tableHtml=NMResultsViewerReportTools.structRowsHtml(rows, ...
                        {'index','component','meanAbsoluteDx','concentration','effectiveSubjects', ...
                        'positivePct','negativePct','zeroPct','observed','coveragePct'}, ...
                        {'#','Component','Mean |Dx|','Concentration S','Effective N', ...
                        'Positive %','Negative %','Zero %','Finite N','Coverage %'},maxRows);
                    note=sprintf(['<p class=small>%d subjects; %d retained components. ' ...
                        'Concentration S = 1 - effective N / finite N, with effective N = ' ...
                        '(sum |Dx|)^2 / sum Dx^2. NaN Dx is excluded; finite zero counts toward N. ' ...
                        'All-zero and all-missing components have undefined concentration. ' ...
                        'Coverage is finite subjects / total subjects, not model-count coverage. ' ...
                        'The table retains all components; the chart shows at most %d. ' ...
                        'All measures are descriptive.</p>'], ...
                        component.Payload.fractionatedPopulation.caseCount, ...
                        component.Payload.fractionatedPopulation.componentCount,nPlot);
                    body=[fig note tableHtml];
                case 'model_feature_inspection.fractionated_clusters'
                    profiles=component.Tables.clusterProfiles;
                    opts=component.Options;
                    indices=component.PlotPayload.clusterProfileOrder;
                    indices=indices(1:min(numel(indices),opts.MaxPlotComponents));
                    selected=profiles(ismember([profiles.componentIndex],indices));
                    [~,positions]=ismember([selected.componentIndex],indices);
                    [~,rowOrder]=sortrows([positions(:),[selected.cluster]']);
                    selected=selected(rowOrder);
                    k=component.Payload.fractionatedClusters.clusterCount;
                    values=reshape([selected.(opts.ProfileMetric)],k,[])';
                    rowLabels={selected(1:k:end).componentLabel};
                    columnLabels=arrayfun(@(c)sprintf('Cluster %d',c),1:k,'UniformOutput',false);
                    labels=struct('signedMean','Mean signed Dx', ...
                        'difference','Difference from population mean', ...
                        'absoluteMean','Mean absolute Dx');
                    fig=NMResultsViewerReportFigureTools.continuousMatrixHtml( ...
                        values,rowLabels,columnLabels, ...
                        struct('ValueLabel',labels.(opts.ProfileMetric),'RowHeading','Component', ...
                        'ColumnHeading','cluster','Signed',~strcmp(opts.ProfileMetric,'absoluteMean'), ...
                        'DisplayValues',true,'HighlightRow',NaN));
                    optimization=component.Payload.fractionatedClusters.optimization;
                    if ~isempty(component.Tables.clusterOptimization)
                        curveRows=component.Tables.clusterOptimization;
                        plotData=struct('label',arrayfun(@(v)sprintf('k=%d',v),[curveRows.k],'UniformOutput',false), ...
                            'value',num2cell([curveRows.criterionValue]));
                        fig=[fig NMResultsViewerReportFigureTools.componentShareSvg(plotData, ...
                            'Title',sprintf('%s optimization · selected k=%d', ...
                            upper(optimization.criterion),optimization.selectedClusters), ...
                            'ValueField','value','LabelField','label', ...
                            'XLabel',upper(optimization.criterion), ...
                            'CategoricalY',true,'MaxRows',numel(plotData))];
                    end
                    if ~isempty(component.Payload.fractionatedClusters.consensusBinEdges)
                        fig=[fig NMResultsViewerReportFigureTools.partitionHeatmapsSvg( ...
                            component.Tables.clusterConsensus,'cluster_consensus') ...
                            sprintf(['<p class="small">Selected-k consensus for %d subjects (up to 72 contiguous ordered bins); ' ...
                                'each cell is a MATLAB-produced block-average co-clustering frequency.</p>'], ...
                                numel(component.Tables.clusterSubjects))];
                    end
                    note=sprintf(['<p class="small">Contribution space: %s; selected k=%d. %s %s ' ...
                        'Missing Dx is not imputed; performance associations (%s) are descriptive.</p>'], ...
                        opts.Mode,component.Payload.fractionatedClusters.clusterCount, ...
                        component.Payload.fractionatedClusters.distanceDefinition, ...
                        component.Payload.fractionatedClusters.message, ...
                        component.Payload.fractionatedClusters.performanceMetric);
                    groupTable=NMResultsViewerReportTools.structRowsHtml(component.Tables.clusterGroups, ...
                        {'cluster','subjects','performanceN','meanScore','errorMetric'}, ...
                        {'Cluster','Subjects','Performance N','Mean score','Mean error'},maxRows);
                    summary=['<h3>Cluster summary</h3>' groupTable];
                    if ~isempty(component.Tables.clusterOptimization)
                        summary=[summary '<h3>k optimization</h3>' ...
                            NMResultsViewerReportTools.structRowsHtml(component.Tables.clusterOptimization, ...
                            {'k','criterionValue','selected'}, ...
                            {'k','Criterion value','Selected'},maxRows)];
                    end
                    note=[note '<p class="small">Full Case-ID memberships and component profiles are available in CSV/XLSX/MAT/JSON exports.</p>'];
                    body=[fig note summary];
                case 'model_feature_inspection.fractionated_decision'
                    rows = component.Tables.fractionatedDecision;
                    plotIndices = find(isfinite([rows.meanDecisionFraction]),40,'first');
                    nPlot = numel(plotIndices);
                    fig = NMResultsViewerReportFigureTools.componentShareSvg(rows(plotIndices), ...
                        'Title','Fractionated decision scores (CV2 out-of-sample)', ...
                        'ValueField','meanDecisionFraction','LabelField','caseId', ...
                        'XLabel','Signed normalized-margin contribution', ...
                        'LoField','loSE','HiField','hiSE','IntervalLabel','mean +/- 1 SE', ...
                        'CategoricalY',true,'MaxRows',nPlot);
                    tableHtml = NMResultsViewerReportTools.structRowsHtml(rows, ...
                        {'caseId','componentLabel','meanDecisionFraction','sdDecisionFraction','seDecisionFraction','nValid'}, ...
                        {'Subject','Component','Mean contribution','SD','SE','Valid models'},maxRows);
                    note = '<p class="small">Whiskers indicate mean +/- 1 SE, not a 95% confidence interval. Contributions are conditional on component presence.</p>';
                    if ~component.Payload.fractionatedDecision.coverageAvailable
                        note = [note '<p class="small">Valid-model counts were not persisted in this visualization result.</p>'];
                    end
                    body = [fig note tableHtml];
                case 'model_feature_inspection.component_summary'
                    rows = component.Tables.componentSummary;
                    plotPayload = component.PlotPayload;
                    metricField = plotPayload.componentMetric;
                    metricLabel = NMResultsViewerReportTools.modelFeatureInspectionComponentMetricLabel(metricField);
                    [loField,hiField] = NMResultsViewerReportTools.modelFeatureInspectionComponentMetricIntervalFields(metricField);
                    metadata = component.Metadata;
                    selectedComponentIndex = metadata.backprojectionComponentIndex;
                    capturedState = NMResultsViewerReportTools.featureInspectionViewState(component.Options);
                    if isfinite(capturedState.selectedBackprojectionComponentIndex)
                        selectedComponentIndex = capturedState.selectedBackprojectionComponentIndex;
                    end
                    fig = NMResultsViewerReportFigureTools.componentShareSvg(rows, 'Title','Component statistics','ValueField',metricField,'LabelField','componentLabel','XLabel',metricLabel,'YAxisLabel','Component','LoField',loField,'HiField',hiField,'SelectedComponentIndex',selectedComponentIndex,'MaxRows',numel(rows));
                    tableHtml = NMResultsViewerReportTools.modelFeatureInspectionComponentReportTableHtml(rows, metricField, metricLabel, maxRows);
                    contextHtml = NMResultsViewerReportTools.modelFeatureInspectionFusionReportContextHtml(component, metricLabel);
                    body = NMResultsViewerReportTools.modelFeatureInspectionFusionPanelReportHtml(fig, tableHtml, contextHtml);
                case 'model_feature_inspection.modality_contribution'
                    rows = component.Tables.modalityContribution;
                    fig = NMResultsViewerReportFigureTools.componentShareSvg(rows, 'Title','Modality contribution','ValueField','medianShare','LabelField','modalityLabel','XLabel','Median Lp share','LoField','lo95','HiField','hi95','MaxRows',numel(rows),'CategoricalY',true,'BaseColor','#2563eb');
                    tableHtml = NMResultsViewerReportTools.modelFeatureInspectionModalityReportTableHtml(rows, maxRows);
                    contextHtml = NMResultsViewerReportTools.modelFeatureInspectionFusionReportContextHtml(component, 'Median Lp share');
                    body = NMResultsViewerReportTools.modelFeatureInspectionFusionPanelReportHtml(fig, tableHtml, contextHtml);
                case 'model_feature_inspection.component_modality_matrix'
                    rows = component.Tables.componentModalityMatrix;
                    matrixField = component.PlotPayload.matrixStatistic;
                    matrixLabel = 'Median Lp share'; if strcmp(matrixField,'meanShare'), matrixLabel='Mean Lp share'; end
                    metadata = component.Metadata;
                    selectedComponentIndex = metadata.backprojectionComponentIndex;
                    fig='';
                    if ~isempty(rows)
                        % R.comp_by_mod writes complete component-major × modality-minor rows.
                        nModalities=rows(end).modalityIndex;
                        modLabels={rows(1:nModalities).modalityLabel};
                        compLabels={rows(1:nModalities:end).componentLabel};
                        values=reshape([rows.(matrixField)],nModalities,[])';
                        selectedRow=find([rows(1:nModalities:end).componentIndex]==selectedComponentIndex,1);
                        if isempty(selectedRow),selectedRow=NaN;end
                        fig=NMResultsViewerReportFigureTools.continuousMatrixHtml( ...
                            values,compLabels,modLabels,struct('ValueLabel',matrixLabel, ...
                            'RowHeading','Component','ColumnHeading','modality', ...
                            'Signed',any(values(:)<0),'DisplayValues',true,'HighlightRow',selectedRow));
                    end
                    tableHtml = NMResultsViewerReportTools.modelFeatureInspectionComponentModalityReportTableHtml(rows, matrixField, matrixLabel, maxRows);
                    contextHtml = NMResultsViewerReportTools.modelFeatureInspectionFusionReportContextHtml(component, matrixLabel);
                    body=[contextHtml fig tableHtml]; % Allow rows to fragment across print pages.
                case 'model_feature_inspection.feature_ranking'
                    rows = component.Tables.featureRanking;
                    tableHtml = NMResultsViewerReportTools.structRowsHtml(rows, ...
                        {'featureName','displayValue','displaySE','sortAbsRank','sortSignedRank'}, ...
                        {'Feature','Value','SE','Abs. rank','Signed rank'}, maxRows, {{'displaySE'}});
                otherwise
                    tableHtml = NMResultsViewerReportTools.componentTablesHtml(component, maxRows);
            end
            if isempty(body), body = [fig tableHtml]; end
            if isempty(body)
                renderStatus = 'sidecar_only';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'Component payload is available through sidecars, but no compact Stage 10A static summary could be rendered.');
            else
                if isempty(fig)
                    renderStatus = 'table_only';
                else
                    renderStatus = 'rendered';
                end
                html = NMResultsViewerReportTools.figureComponentHtml(component, body, renderStatus);
            end
        end

        function instance = componentInstanceTemplate()
            % componentInstanceTemplate  Create stable modality/component instance metadata.
            % Public so the browser ingress (NMResultsViewerUI.requestReportSpec) can
            % restore numeric fields that JSON transport turned into [].
            instance = struct('Id','','IsOverview',false,'ClassifierId','', ...
                'ClassifierIndex',NaN,'ClassifierLabel','', ...
                'OOCVSubgroupIndex',NaN,'OOCVSubgroupLabel','', ...
                'ComponentType','','MetricId','','YMetricId','', ...
                'FeatureContextId','','FeatureContextLabel','','FeatureKind','','SupportDomain','','IsCombinedContext',false, ...
                'BackprojectionComponentId','','BackprojectionComponentLabel','', ...
                'BackprojectionComponentIndex',NaN,'RetainedComponentColumn',NaN, ...
                'RepresentationId','','PresentationMode','','PresentationArtifactRequired',false);
        end
    end

    methods (Static, Access = private)
        function opts = defaultFeatureRelationOptions()
            % Report Builder relation defaults shared by API and browser recipes.
            opts = struct('PanelVisible',true, ...
                'RelationState',NMResultsViewerFeatureRelationTools.relationViewRequestTemplate(), ...
                'GraphLabelMode','auto','GraphMaxLabels',20, ...
                'SelectedRelationPatternId',0,'RelationPanelsSynchronized',true, ...
                'PositiveColor','#dc2626','NegativeColor','#2563eb', ...
                'SubthresholdColor','#d1d5db','MatrixReportIncluded',false);
        end

        function lines = displayOverrideAssignmentLines(value, path, declare)
            % displayOverrideAssignmentLines  Render nested public settings as readable MATLAB assignments.
            if nargin < 3, declare=true; end
            lines={};
            if isstruct(value) && isscalar(value)
                if declare, lines{end+1}=sprintf('%s = struct();',path); end %#ok<AGROW>
                names=fieldnames(value);
                for ii=1:numel(names)
                    field=names{ii};
                    lines=[lines NMResultsViewerReportTools.displayOverrideAssignmentLines(value.(field),[path '.' field],true)]; %#ok<AGROW>
                end
                return;
            end
            if isstruct(value) && numel(value) > 1
                lines{end+1}=sprintf('%s = cell(1,%d);',path,numel(value)); %#ok<AGROW>
                for ii=1:numel(value)
                    lines=[lines NMResultsViewerReportTools.displayOverrideAssignmentLines(value(ii),sprintf('%s{%d}',path,ii),true)]; %#ok<AGROW>
                end
                return;
            end
            if iscell(value)
                lines{end+1}=sprintf('%s = cell(1,%d);',path,numel(value)); %#ok<AGROW>
                for ii=1:numel(value)
                    lines=[lines NMResultsViewerReportTools.displayOverrideAssignmentLines(value{ii},sprintf('%s{%d}',path,ii),true)]; %#ok<AGROW>
                end
                return;
            end
            lines{end+1}=sprintf('%s = %s;',path,NMResultsViewerReportTools.scriptValueLiteral(value)); %#ok<AGROW>
        end



        function spec = validationSpecDefaults(spec)
            % validationSpecDefaults  Normalize report-diagnostic user options.
            if nargin < 1 || ~isstruct(spec), spec = struct(); end
            if ~isfield(spec,'AnalysisIndex') && ~isfield(spec,'analysisIndex'), spec.AnalysisIndex = 1; end
            if ~isfield(spec,'Source') && ~isfield(spec,'source'), spec.Source = 'cv'; end
            if ~isfield(spec,'MultiClassModeIndex') && ~isfield(spec,'multiClassModeIndex'), spec.MultiClassModeIndex = 1; end
            if ~isfield(spec,'IncludeDisabled') && ~isfield(spec,'includeDisabled'), spec.IncludeDisabled = false; end
            if ~isfield(spec,'IncludePdfProbe') && ~isfield(spec,'includePdfProbe'), spec.IncludePdfProbe = true; end
        end

        function exportSpec = validationExportSpec(spec)
            % validationExportSpec  Resolve HTML/PDF diagnostic export options.
            if isstruct(spec) && isfield(spec,'ExportSpec') && isstruct(spec.ExportSpec)
                exportSpec = spec.ExportSpec;
            else
                exportSpec = struct();
            end
            if ~isfield(exportSpec,'Format') && ~isfield(exportSpec,'format'), exportSpec.Format = 'html'; end
            if ~isfield(exportSpec,'ReportMode') && ~isfield(exportSpec,'reportMode'), exportSpec.ReportMode = 'summary'; end
            if ~isfield(exportSpec,'OutputDirectory') && ~isfield(exportSpec,'outputDirectory'), exportSpec.OutputDirectory = pwd; end
            exportSpec = NMResultsViewerReportTools.normalizeExportSpec(exportSpec);
        end

        function diagnostic = validationTemplate()
            % validationTemplate  Create fixed-schema report-diagnostic output.
            diagnostic = struct('ok',false,'message','Not run','createdAt','', ...
                'inputSpec',struct(),'exportSpec',struct(),'reportSpec',struct(), ...
                'summary',struct(),'pdfProbe',struct(), ...
                'details',struct('catalogueRows',[],'componentRows',[], ...
                    'messageRows',[],'parityRows',[],'catalogueTable',[], ...
                    'componentTable',[],'messageTable',[],'parityTable',[]));
        end

        function reportSpec = validationReportSpec(NM, spec)
            % validationReportSpec  Resolve the full-report spec used by diagnostics.
            if isstruct(spec) && isfield(spec,'ReportSpec') && isstruct(spec.ReportSpec)
                reportSpec = NMResultsViewerReportTools.normalizeReportSpec(NM, spec.ReportSpec);
                return;
            end
            reportSpec = NMResultsViewerReportTools.defaultReportSpec(NM, spec);
        end

        function oneSpec = validationOneComponentReportSpec(reportSpec, catalogueEntry)
            % validationOneComponentReportSpec  Build a one-component report spec.
            oneSpec = reportSpec;
            compSpec = NMResultsViewerReportTools.componentSpecTemplate();
            compSpec.Id = catalogueEntry.Id;
            compSpec.Title = catalogueEntry.Label;
            compSpec.Viewspace = catalogueEntry.Viewspace;
            ps = catalogueEntry.PayloadSpec;
            if ~isstruct(ps), ps = struct(); end
            compSpec.PayloadSpec = ps;
            compSpec.Instance = catalogueEntry.Instance;
            layout = catalogueEntry.DefaultLayout;
            if ~isstruct(layout), layout = NMResultsViewerReportTools.componentLayoutTemplate(); end
            compSpec.Layout = layout;
            compSpec.Options = struct();
            oneSpec.Components = compSpec;
            oneSpec.Layout = NMResultsViewerReportTools.defaultReportLayout(1);
        end

        function [rows, componentRows] = validationCatalogueRows(catalogue)
            % Build both diagnostic projections from each canonical component catalogue row once.
            rowTemplate = struct('ComponentId','','Label','','Viewspace','','Enabled',false, ...
                'HasUserLabel',false,'HasPayloadSpec',false,'HasLayout',false, ...
                'HasMissingReason',false,'MissingReason','');
            componentTemplate = struct('ComponentId','','Title','','Viewspace','','Enabled',false, ...
                'Checked',false,'BuildOk',false,'HtmlOk',false, ...
                'ComponentStatus','','RenderStatus','','WarningCount',0,'ErrorCount',0, ...
                'MissingReason','','Message','');
            rows = rowTemplate([]);
            componentRows = componentTemplate([]);
            if ~isstruct(catalogue) || isempty(catalogue), return; end
            rows = repmat(rowTemplate,1,numel(catalogue));
            componentRows = repmat(componentTemplate,1,numel(catalogue));
            for ii = 1:numel(catalogue)
                entry = catalogue(ii);
                rows(ii).ComponentId = entry.Id;
                rows(ii).Label = entry.Label;
                rows(ii).Viewspace = entry.Viewspace;
                rows(ii).Enabled = logical(entry.Enabled);
                rows(ii).HasUserLabel = ~isempty(entry.Label) && ~strcmp(entry.Label,upper(entry.Label));
                rows(ii).HasPayloadSpec = isstruct(entry.PayloadSpec);
                rows(ii).HasLayout = isstruct(entry.DefaultLayout);
                rows(ii).MissingReason = entry.MissingReason;
                rows(ii).HasMissingReason = ~entry.Enabled && ~isempty(entry.MissingReason);
                componentRows(ii).ComponentId = entry.Id;
                componentRows(ii).Title = entry.Label;
                componentRows(ii).Viewspace = entry.Viewspace;
                componentRows(ii).Enabled = logical(entry.Enabled);
                componentRows(ii).MissingReason = entry.MissingReason;
            end
        end

        function [row, messageCells] = validationInspectOneReport(oneReport, catalogueEntry, exportSpec, enabled)
            % validationInspectOneReport  Validate one built component and its HTML.
            [~, row] = NMResultsViewerReportTools.validationCatalogueRows(catalogueEntry);
            row.Checked = true;
            row.BuildOk = isstruct(oneReport) && isfield(oneReport,'Components') && ~isempty(oneReport.Components);
            row.HtmlOk = false;
            messageCells = cell(1,0);
            if ~row.BuildOk
                row.ComponentStatus = 'error';
                row.RenderStatus = 'error';
                row.ErrorCount = row.ErrorCount + 1;
                row.Message = 'buildReport returned no component payload.';
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, row.ComponentId, 'error', 'build', '', row.Message, []);
                return;
            end
            comp = oneReport.Components(1);
            row.ComponentStatus = comp.Status;
            row.RenderStatus = comp.RenderStatus;
            row.MissingReason = comp.MissingReason;
            row.WarningCount = numel(comp.Warnings);
            if enabled && ~strcmpi(row.ComponentStatus, 'ok')
                row.ErrorCount = row.ErrorCount + 1;
                if isempty(row.MissingReason), row.MissingReason = 'Enabled component did not build an ok payload.'; end
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, row.ComponentId, 'error', 'payload', '', row.MissingReason, []);
            elseif ~enabled && strcmpi(row.ComponentStatus, 'ok')
                row.ErrorCount = row.ErrorCount + 1;
                row.Message = 'Disabled catalogue component unexpectedly produced an ok payload.';
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, row.ComponentId, 'error', 'payload', '', row.Message, []);
            end
            try
                [html, renderStatus] = NMResultsViewerReportTools.renderComponentHtml(comp, exportSpec);
                row.RenderStatus = renderStatus;
                row.HtmlOk = (ischar(html) || isstring(html)) && strlength(string(html)) > 0;
                if enabled && ~row.HtmlOk
                    row.ErrorCount = row.ErrorCount + 1;
                    messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, row.ComponentId, 'error', 'render', '', 'Renderer returned empty HTML for an enabled component.', []);
                elseif enabled && strcmpi(renderStatus, 'fallback')
                    messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, row.ComponentId, 'warning', 'render', '', 'Renderer used fallback/static status output.', []);
                end
            catch ME
                row.HtmlOk = false;
                row.RenderStatus = 'error';
                row.ErrorCount = row.ErrorCount + 1;
                row.Message = ME.message;
                messageCells = NMResultsViewerReportTools.validationAddMessage(messageCells, row.ComponentId, 'error', 'render', ME.identifier, ME.message, ME);
            end
        end

        function out = validationMergeComponentRow(baseRow, updateRow)
            % validationMergeComponentRow  Merge fixed-schema component diagnostic rows.
            out = baseRow;
            names = fieldnames(updateRow);
            for ii = 1:numel(names)
                out.(names{ii}) = updateRow.(names{ii});
            end
        end

        function rows = validationParityRows(report)
            % validationParityRows  Check report-side payload fields used by plot renderers.
            tmpl = struct('PlotType','','ComponentId','','ReportPayloadFields','', ...
                'ComponentPresent',false,'RequiredFieldsPresent',false,'Notes','');
            specs = {
                'Primary performance plot','model_performance.primary_plot','classPlot, regressionPlot, multiClassPlot';
                'ROC curve','model_performance.roc','roc';
                'Calibration','model_performance.calibration','calibration';
                'Decision curve','model_performance.dca','dca';
                'Model permutation histogram','model_performance.model_permutation','modelPermutation';
                'Alternative-label permutation histograms','model_performance.extra_label_permutation_gallery','modelPermutation';
                'Probability/score distribution','model_performance.probability_distribution','pies, scoreColumns, scoreRows, multiClassSummaryVisuals';
                'Confusion matrix','model_performance.confusion_matrix','confusion';
                'Optimization curve','model_optimization.selected_metric','metricValues';
                'CV partition matrices','model_optimization.cv_partitions','cvPartitions';
                'Optimization dashboard','model_optimization.metric_dashboard','metricValues, cvPartitions';
                '2D parameter surfaces','model_optimization.parameter_surface','parameterSurface';
                'Metric scatter/Pareto','model_optimization.scatter_comparison','associations, scatterRows';
                'Feature ranking','model_feature_inspection.feature_ranking','featureRanking';
                'Feature metric table','model_feature_inspection.feature_metric_table','featureMetricTable';
                'Feature metric bar plot','model_feature_inspection.feature_metric_bar.cross_validation_ratio','featureMetricBars';
                'Feature metric relationship plot','model_feature_inspection.feature_metric_relationship.cross_validation_ratio__sign_consistency_logp','featureMetricRelationship';
                'Feature-correlation matrix','model_feature_inspection.correlation_matrix','relationPayload';
                'Feature-relation graph','model_feature_inspection.feature_network','relationPayload';
                'Component-wise analysis','model_feature_inspection.component_summary','componentSummary';
                'Spatial map summary','model_feature_inspection.spatial_map_summary','spatialMapSummary'
                };
            rows = repmat(tmpl, 1, size(specs,1));
            comps = [];
            if isstruct(report) && isfield(report,'Components'), comps = report.Components; end
            for ii = 1:size(specs,1)
                rows(ii).PlotType = specs{ii,1};
                rows(ii).ComponentId = specs{ii,2};
                rows(ii).ReportPayloadFields = specs{ii,3};
                comp = NMResultsViewerReportTools.componentById(comps, rows(ii).ComponentId);
                rows(ii).ComponentPresent = ~isempty(comp) && isstruct(comp);
                rows(ii).RequiredFieldsPresent = NMResultsViewerReportTools.validationComponentHasAnyPayloadField(comp, strtrim(strsplit(rows(ii).ReportPayloadFields, ',')));
                if ~rows(ii).ComponentPresent
                    rows(ii).Notes = 'Component was not included in the full report specification.';
                elseif ~rows(ii).RequiredFieldsPresent
                    rows(ii).Notes = 'The component was present but none of the expected report-side payload fields were populated.';
                else
                    rows(ii).Notes = 'Report-side renderer has a populated payload field for this plot type.';
                end
            end
        end

        function tf = validationComponentHasAnyPayloadField(comp, fields)
            % validationComponentHasAnyPayloadField  Check Payload and PlotPayload fields.
            tf = false;
            if isempty(comp) || ~isstruct(comp), return; end
            payload = comp.Payload;
            plotPayload = comp.PlotPayload;
            for ii = 1:numel(fields)
                f = strtrim(char(string(fields{ii})));
                if isempty(f), continue; end
                if (isstruct(payload) && isfield(payload,f) && ~isempty(payload.(f))) || ...
                        (isstruct(plotPayload) && isfield(plotPayload,f) && ~isempty(plotPayload.(f))) || ...
                        (isstruct(comp) && isfield(comp,'Tables') && isstruct(comp.Tables) && isfield(comp.Tables,f) && ~isempty(comp.Tables.(f)))
                    tf = true;
                    return;
                end
            end
        end

        function pdfProbe = validationPdfProbe(spec, exportSpec)
            % validationPdfProbe  Probe PDF renderer availability without exporting.
            pdfProbe = struct('ok',false,'name','','command','','probeLog','', ...
                'message','PDF probe was not requested.','errorId','', ...
                'errorSource','','stackFrame1','','stackFrame2','');
            if ~NMResultsViewerReportTools.structLogical(spec, {'IncludePdfProbe','includePdfProbe'}, true), return; end
            try
                renderer = NMResultsViewerReportTools.resolvePdfRenderer(exportSpec);
                pdfProbe.ok = logical(renderer.ok);
                pdfProbe.name = renderer.name;
                pdfProbe.command = renderer.command;
                pdfProbe.probeLog = renderer.probeLog;
                if pdfProbe.ok
                    pdfProbe.message = sprintf('PDF renderer probe succeeded: %s.', pdfProbe.name);
                else
                    pdfProbe.message = sprintf('PDF renderer probe failed: %s', pdfProbe.probeLog);
                end
            catch ME
                pdfProbe.ok = false;
                pdfProbe.name = 'error';
                pdfProbe.errorId = ME.identifier;
                [pdfProbe.errorSource, pdfProbe.stackFrame1, pdfProbe.stackFrame2] = NMResultsViewerReportTools.validationExceptionFrames(ME);
                pdfProbe.probeLog = ME.message;
                pdfProbe.message = sprintf('PDF renderer probe raised %s: %s', ME.identifier, ME.message);
            end
        end

        function rows = validationMessagesFromCells(messageCells)
            % validationMessagesFromCells  Convert message cell list to fixed struct rows.
            tmpl = NMResultsViewerReportTools.validationMessageTemplate();
            rows = tmpl([]);
            if isempty(messageCells), return; end
            rows = repmat(tmpl, 1, numel(messageCells));
            for ii = 1:numel(messageCells)
                rows(ii) = NMResultsViewerReportTools.copyMissingFields(messageCells{ii}, tmpl);
            end
        end

        function row = validationMessageTemplate()
            % validationMessageTemplate  Fixed-schema diagnostic message row.
            row = struct('ComponentId','','Level','','Stage','','ErrorId','', ...
                'Message','','ErrorSource','','StackFrame1','','StackFrame2','');
        end

        function messageCells = validationAddMessage(messageCells, componentId, level, stage, errorId, message, ME)
            % validationAddMessage  Append one diagnostic message with error-stack context.
            if nargin < 7, ME = []; end
            row = NMResultsViewerReportTools.validationMessageTemplate();
            row.ComponentId = char(string(componentId));
            row.Level = char(string(level));
            row.Stage = char(string(stage));
            row.ErrorId = char(string(errorId));
            row.Message = char(string(message));
            if isa(ME, 'MException')
                [row.ErrorSource, row.StackFrame1, row.StackFrame2] = NMResultsViewerReportTools.validationExceptionFrames(ME);
            end
            messageCells{end+1} = row; %#ok<AGROW>
        end

        function [source, frame1, frame2] = validationExceptionFrames(ME)
            % validationExceptionFrames  Format exact error source and top stack frames.
            source = '';
            frame1 = '';
            frame2 = '';
            if ~isa(ME, 'MException') || isempty(ME.stack), return; end
            source = NMResultsViewerReportTools.validationStackFrame(ME.stack(1));
            frame1 = source;
            if numel(ME.stack) >= 2
                frame2 = NMResultsViewerReportTools.validationStackFrame(ME.stack(2));
            end
        end

        function txt = validationStackFrame(frame)
            % validationStackFrame  Format one MATLAB error stack frame.
            txt = '';
            if ~isstruct(frame), return; end
            name = '';
            file = '';
            line = NaN;
            if isfield(frame,'name'), name = char(string(frame.name)); end
            if isfield(frame,'file'), file = char(string(frame.file)); end
            if isfield(frame,'line') && isnumeric(frame.line) && ~isempty(frame.line), line = double(frame.line(1)); end
            if isfinite(line)
                txt = sprintf('%s, line %.0f (%s)', name, line, file);
            else
                txt = sprintf('%s (%s)', name, file);
            end
        end

        function summary = validationSummary(catalogueOk, fullBuildOk, fullHtmlOk, scriptOk, compRows, messageRows, pdfProbe)
            % validationSummary  Summarize the Results Viewer report diagnostic.
            checked = false(1, numel(compRows));
            failed = false(1, numel(compRows));
            warnings = 0;
            for ii = 1:numel(compRows)
                checked(ii) = logical(compRows(ii).Checked);
                failed(ii) = checked(ii) && (~logical(compRows(ii).BuildOk) || ~logical(compRows(ii).HtmlOk) || double(compRows(ii).ErrorCount) > 0);
                warnings = warnings + double(compRows(ii).WarningCount);
            end
            msgErr = 0;
            msgWarn = 0;
            for ii = 1:numel(messageRows)
                if strcmpi(char(string(messageRows(ii).Level)), 'error'), msgErr = msgErr + 1; end
                if strcmpi(char(string(messageRows(ii).Level)), 'warning'), msgWarn = msgWarn + 1; end
            end
            ok = logical(catalogueOk) && logical(fullBuildOk) && logical(fullHtmlOk) && logical(scriptOk) && ~any(failed) && msgErr == 0;
            if ok
                message = sprintf('Report Builder diagnostic passed: %d component(s) checked, %d warning(s).', sum(checked), warnings + msgWarn);
            else
                message = sprintf('Report Builder diagnostic exposed %d failure(s), %d error message(s), %d warning(s).', sum(failed), msgErr, warnings + msgWarn);
            end
            summary = struct('Ok',ok,'Message',message, ...
                'CatalogueOk',logical(catalogueOk),'FullReportBuildOk',logical(fullBuildOk), ...
                'FullHtmlOk',logical(fullHtmlOk),'ScriptOk',logical(scriptOk), ...
                'ComponentCount',numel(compRows),'CheckedComponentCount',sum(checked), ...
                'FailedComponentCount',sum(failed),'MessageErrorCount',msgErr, ...
                'MessageWarningCount',msgWarn,'ComponentWarningCount',warnings, ...
                'PdfProbeOk',logical(NMResultsViewerReportTools.safeField(pdfProbe,'ok',false)));
        end

        function tbl = validationStructTable(rows)
            % validationStructTable  Convert diagnostic rows to tables when possible.
            if isempty(rows)
                tbl = table();
                return;
            end
            tbl = struct2table(rows);
        end

        function spec = reportSpecTemplate()

            % Purpose: Create the fixed schema-2 Report Builder recipe including optional per-analysis plans.

            % Syntax: see method signature above.

            % Inputs: No scientific inputs.

            % Outputs: Scalar report specification template with Components, AnalysisPlans, feature/presentation plans and layout metadata.

            % Authority and flow: Defines report-plan schema only; Scientific State and component payload authorities remain separate.

            % Scientific/state contract: Scientific State answers what exists; Report Builder records only composition/presentation state and preserves explicit scientific identities.

            % Invariants: No raw NM result discovery is introduced here; ordinary components retain explicit analysisIndex and set-level components retain explicit AnalysisIndices.

            % Materialization and performance: Compact report metadata/planning unless delegated existing component planners materialize established payload metadata; no new feature-scale work is introduced.

            % Resource declaration: This method itself reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices, and creates no feature-scale arrays; delegated established authorities retain their own contracts.

            % Interactive/retained use: Intended for explicit Report Builder catalogue/planning actions; it does not introduce a retained scientific rematerialization loop.
            % Failure semantics: Invalid schema, analysis identity or planning state fails explicitly through existing Report Builder errors; invalid scientific state is never substituted.

            % Side effects: None except request-scoped session/cache mutation where explicitly passed by planReportSpec.

            % Consumers and dependencies: Browser/API Report Builder, existing component planners/materializers, Scientific State and Cross-analysis report integration.
            spec = struct('SchemaVersion',2,'Title','','Description','','AnalysisIndex',1, ...
                'Source','cv','MultiClassModeIndex',1,'Components',NMResultsViewerReportTools.componentSpecTemplate([]), ...
                'AnalysisPlans',NMResultsViewerReportTools.analysisPlanTemplate([]), ...
                'PresentationState',struct('OutputOrder',{{}}), ...
                'Layout',NMResultsViewerReportTools.defaultReportLayout(0),'Metadata',struct(),'PlanSummary',struct());
        end

        function plan = analysisPlanTemplate(emptyFlag)

            % Purpose: Create one analysis-local planning record for a mixed multi-analysis report.

            % Syntax: see method signature above.

            % Inputs: Optional emptyFlag requests an empty struct array.

            % Outputs: AnalysisIndex plus the established feature/presentation planning fields for one analysis.

            % Authority and flow: This is report-plan state only; scientific availability and identity remain in Scientific State/component PayloadSpec.

            % Scientific/state contract: Scientific State answers what exists; Report Builder records only composition/presentation state and preserves explicit scientific identities.

            % Invariants: No raw NM result discovery is introduced here; ordinary components retain explicit analysisIndex and set-level components retain explicit AnalysisIndices.

            % Materialization and performance: Compact report metadata/planning unless delegated existing component planners materialize established payload metadata; no new feature-scale work is introduced.

            % Resource declaration: This method itself reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices, and creates no feature-scale arrays; delegated established authorities retain their own contracts.

            % Failure semantics: Invalid schema, analysis identity or planning state fails explicitly through existing Report Builder errors; invalid scientific state is never substituted.

            % Side effects: None except request-scoped session/cache mutation where explicitly passed by planReportSpec.

            % Consumers and dependencies: Browser/API Report Builder, existing component planners/materializers, Scientific State and Cross-analysis report integration.
            plan=struct('AnalysisIndex',1,'FeatureSelection',NMResultsViewerReportTools.featureSelectionTemplate(), ...
                'FeaturePresentations',NMResultsViewerReportTools.featurePresentationTemplate([]),'PresentationState',struct(), ...
                'DisplayOverrides',struct(),'FeatureInspectionPlan',NMResultsViewerReportTools.featureInspectionPlanTemplate(), ...
                'OOCVGroupPlan',NMResultsViewerReportTools.oocvGroupPlanTemplate(), ...
                'EvaluationSourcePlan',NMResultsViewerReportTools.evaluationSourcePlanTemplate());
            if nargin>0&&(isempty(emptyFlag)||isequal(emptyFlag,[])),plan=plan([]);end
        end

        function plan = oocvGroupPlanTemplate()
            % oocvGroupPlanTemplate  Create the analysis-local OOCV comparison export policy.
            plan = struct('Mode','current','SelectedSubgroupIndices',[], 'SelectedSubgroupLabels',{{}});
        end

        function plan = evaluationSourcePlanTemplate()
            % Report-local evaluation selection; source identities are produced by sourcesForAnalysis.
            plan = struct('Mode','current','SelectedSourceIds',{{}});
        end

        function layout = defaultReportLayout(nComponents)
            % defaultReportLayout  Create global report layout metadata.
            if nargin < 1 || isempty(nComponents), nComponents = 0; end
            layout = struct('Mode','stacked','Columns',1,'ComponentCount',double(nComponents));
        end

        function rows = fractionatedDecisionReportRows(scores)
            % One canonical long-form export for selected or all retained Dx columns.
            [ss,cc]=ndgrid(1:numel(scores.caseIds),1:numel(scores.componentIndices));
            cases=scores.caseIds(:);indices=scores.componentIndices(:);labels=scores.componentLabels(:);
            counts=nan(size(scores.mean));
            if scores.coverageAvailable,counts=scores.nValid;end
            rows=struct('caseIndex',num2cell(ss(:)),'caseId',cases(ss(:)), ...
                'componentIndex',num2cell(indices(cc(:))), ...
                'componentLabel',labels(cc(:)), ...
                'meanDecisionFraction',num2cell(scores.mean(:)), ...
                'sdDecisionFraction',num2cell(scores.sd(:)), ...
                'seDecisionFraction',num2cell(scores.se(:)), ...
                'nValid',num2cell(counts(:)), ...
                'loSE',num2cell(scores.mean(:)-scores.se(:)), ...
                'hiSE',num2cell(scores.mean(:)+scores.se(:)));
        end

        function opts = fractionatedIndividualOptionsTemplate()
            % Canonical Report Builder presentation defaults. The selected Case ID is
            % resolved from the authoritative Dx case axis at materialization.
            opts=struct('StateSource','report','CaseId','', ...
                'ProfileSort','absolute_desc','MaxPlotComponents',20,'MaxSubjects',0);
        end

        function opts = fractionatedPopulationOptionsTemplate()
            % Purely presentational; every report exports all canonical component rows.
            opts=struct('StateSource','report','Metric','concentration', ...
                'SortBy','concentration','SortAscending',false,'MaxPlotComponents',25);
        end

        function opts = fractionatedClusterOptionsTemplate()
            % Report-only modifiers; cluster calculations remain with the existing Dx producer.
            opts=struct('StateSource','report','Mode','relative','Selection','fixed', ...
                'ClusterCount',3,'MinClusters',2,'MaxClusters',8,'Criterion','silhouette', ...
                'BootstrapIterations',16,'ProfileMetric','signedMean','MaxPlotComponents',25);
        end

        function spec = componentSpecTemplate(emptyFlag)
            % componentSpecTemplate  Create a fixed-schema component request struct.
            if nargin < 1, emptyFlag = false; end
            layout = NMResultsViewerReportTools.componentLayoutTemplate();
            spec = struct('Id','','Title','','Viewspace','','PayloadSpec',struct(), ...
                'Layout',layout,'Options',struct(),'Instance',NMResultsViewerReportTools.componentInstanceTemplate());
            if nargin > 0 && (isempty(emptyFlag) || isequal(emptyFlag, []))
                spec = spec([]);
            end
        end

        function layout = componentLayoutTemplate()
            % componentLayoutTemplate  Create per-component layout defaults.
            layout = struct('Row',1,'Column',1,'Width',12,'Height',4,'Order',1,'Group','');
        end

        function selection = featureSelectionTemplate()
            % featureSelectionTemplate  Create the natural user-facing feature selector.
            %
            % Modalities contains 1-based modality indices; IncludeCombined adds the
            % combined fusion context when available. Components contains original
            % retained/backprojection component indices or the text "all". Payloads
            % contains stable scientific metric ids such as cross_validation_ratio.
            selection = struct('Enabled',false,'Classifiers',[], ...
                'Modalities',[],'IncludeCombined',false,'Components',[], ...
                'Payloads',{{}},'IncludeFusionOverview',true);
        end

        function presentation = featurePresentationTemplate(emptyFlag)
            % featurePresentationTemplate  Create one natural browser-presentation request.
            if nargin < 1, emptyFlag = false; end
            presentation = struct('Representation','','SupportDomain','','ViewMode','current', ...
                'CanonicalViews',{{}},'Montage',struct());
            if nargin > 0 && (isempty(emptyFlag) || isequal(emptyFlag, []))
                presentation = presentation([]);
            end
        end

        function plan = featureInspectionPlanTemplate()
            % featureInspectionPlanTemplate  Create declarative decomposition and feature-report iteration defaults.
            %
            % ClassifierScope is shared by Model Performance, Model Optimization and
            % Model Feature Inspection. Supported values are current, selected and
            % all_binary.
            % SelectedClassifierIndices is required for selected scope. The remaining
            % fields apply only to Model Feature Inspection. selected_modalities is the
            % compiled form of the public FeatureSelection.Modalities selector.
            plan = struct('ClassifierScope','current', ...
                'FeatureSourceScope','current', ...
                'SelectedClassifierIndices',[], ...
                'SelectedFeatureContextIds',{{}}, ...
                'SelectedModalityIndices',[], ...
                'IncludeCombinedFeatureContext',false, ...
                'ComponentScope','current', ...
                'SelectedBackprojectionComponentIds',{{}}, ...
                'SelectedBackprojectionComponentIndices',[], ...
                'IncludeFusionOverview',true, ...
                'MaxExpandedComponents',250);
        end

        function report = reportTemplate()
            % reportTemplate  Create the fixed-schema report payload root.
            report = struct('Kind','nm_results_viewer_report','SchemaVersion',2,'Ok',false, ...
                'Title','','Description','','Context',struct(),'Layout',struct(), ...
                'Components',NMResultsViewerReportTools.reportComponentTemplate([]), ...
                'Warnings',{{}},'Errors',{{}},'Metadata',struct());
        end

        function comp = reportComponentTemplate(emptyFlag)
            % reportComponentTemplate  Create a fixed-schema built component payload.
            if nargin < 1, emptyFlag = false; end
            comp = struct('Id','','Title','','Viewspace','','Status','unavailable', ...
                'RenderStatus','unavailable','MissingReason','', ...
                'Layout',NMResultsViewerReportTools.componentLayoutTemplate(), ...
                'Instance',NMResultsViewerReportTools.componentInstanceTemplate(), ...
                'Payload',struct(),'Tables',struct(),'SidecarTables',struct(), ...
                'PlotPayload',struct(),'Render',struct('HTML',''), ...
                'Options',struct(),'Warnings',{{}},'Metadata',struct());
            if nargin > 0 && (isempty(emptyFlag) || isequal(emptyFlag, []))
                comp = comp([]);
            end
        end


        function ctx = reportContextFromSpec(NM, reportSpec)
            % reportContextFromSpec  Build the summary-report cover context.
            %
            % The method reads only explicit reportSpec selections and stable NM
            % analysis metadata. It does not mutate NM and does not inspect browser
            % state. Decomposition fields describe the shared Model Performance /
            % Model Optimization / Model Feature Inspection scope resolved by
            % planReportSpec.
            analysisIndex = reportSpec.AnalysisIndex;
            firstPayload = struct();
            if ~isempty(reportSpec.Components)
                firstPayload = reportSpec.Components(1).PayloadSpec;
            end
            analysisCatalogue=NMResultsViewerTools.listAnalyses(NM);
            analysisPlans=reportSpec.AnalysisPlans;
            selectedIndices=[analysisPlans.AnalysisIndex];
            if isempty(selectedIndices),selectedIndices=analysisIndex;end
            labels=cell(1,numel(selectedIndices));
            for cc=1:numel(selectedIndices)
                hit=find([analysisCatalogue.index]==selectedIndices(cc),1,'first');
                if ~isempty(hit),labels{cc}=char(string(analysisCatalogue(hit).title));else,labels{cc}=sprintf('Analysis %d',selectedIndices(cc));end
            end
            if numel(labels)>1,title=sprintf('Multi-analysis: %s',strjoin(labels,'; '));elseif ~isempty(labels),title=labels{1};else,title=sprintf('Analysis %d',analysisIndex);end
            taskType = NMResultsViewerTools.defaultPerformanceResultType(NM, analysisIndex);
            included = NMResultsViewerReportTools.reportIncludedSectionLabels(reportSpec);
            planSummary = reportSpec.PlanSummary;
            classifierScope = NMResultsViewerReportTools.structText(planSummary, {'classifierScope'}, 'current');
            classifierIndices = NMResultsViewerReportTools.safeField(planSummary,'classifierIndices',[]);
            classifierLabels = NMResultsViewerReportTools.safeCellstr( ...
                NMResultsViewerReportTools.safeField(planSummary,'classifierLabels',{}));
            ctx = struct('AnalysisIndex',analysisIndex, ...
                'AnalysisTitle',title, ...
                'AnalysisIndices',selectedIndices, ...
                'AnalysisLabels',{labels}, ...
                'Source',reportSpec.Source, ...
                'ResultType',taskType, ...
                'IncludedSections',{included}, ...
                'ModelSource',NMResultsViewerReportTools.structText(firstPayload, {'modelSource','ModelSource'}, ''), ...
                'ClassifierIndex',NMResultsViewerReportTools.structScalar(firstPayload, {'classifierIndex','ClassifierIndex'}, NaN), ...
                'TargetIndex',NMResultsViewerReportTools.structScalar(firstPayload, {'targetIndex','TargetIndex'}, NaN), ...
                'MultiClassModeIndex',NMResultsViewerReportTools.structScalar(firstPayload, {'multiClassModeIndex','MultiClassModeIndex'}, NMResultsViewerReportTools.structScalar(reportSpec, {'MultiClassModeIndex','multiClassModeIndex'}, 1)), ...
                'MultiClassModeLabel',NMResultsViewerReportTools.reportMetadataText(reportSpec, 'ActiveMultiClassModeLabel', ''), ...
                'ClassifierScope',classifierScope, ...
                'ClassifierIndices',classifierIndices, ...
                'ClassifierLabels',{classifierLabels}, ...
                'FeatureClassifierScope',classifierScope, ...
                'FeatureClassifierIndices',classifierIndices, ...
                'FeatureClassifierLabels',{classifierLabels}, ...
                'CreatedBy','NMResultsViewerReportTools.buildReport');
        end

        function labels = reportIncludedSectionLabels(reportSpec)
            % reportIncludedSectionLabels  List unique scientific report sections in order.
            labels = cell(1,0);
            for ii=1:numel(reportSpec.Components)
                label = NMResultsViewerReportTools.viewspaceTitle(reportSpec.Components(ii).Viewspace);
                if ~isempty(label) && ~any(strcmp(labels,label)), labels{end+1}=label; end %#ok<AGROW>
            end
        end

        function txt = reportMetadataText(reportSpec, fieldName, fallback)
            % reportMetadataText  Read a textual report metadata value without errors.
            if nargin < 3, fallback = ''; end
            txt = fallback;
            if ~isstruct(reportSpec) || ~isfield(reportSpec,'Metadata') || ~isstruct(reportSpec.Metadata)
                return;
            end
            if isfield(reportSpec.Metadata, fieldName) && ~isempty(reportSpec.Metadata.(fieldName))
                txt = char(string(reportSpec.Metadata.(fieldName)));
            end
        end

        function component = initializeComponentRenderFields(component)
            % initializeComponentRenderFields  Ensure report components expose render contract fields.
            if isempty(component.RenderStatus) || strcmpi(component.RenderStatus, 'unavailable')
                if strcmpi(component.Status, 'ok')
                    plotPayload = component.PlotPayload;
                    hasPresentation = isstruct(plotPayload) && isfield(plotPayload,'reportPresentationArtifact') && ...
                        isstruct(plotPayload.reportPresentationArtifact) && ~isempty(fieldnames(plotPayload.reportPresentationArtifact));
                    id = component.Id;
                    if hasPresentation
                        component.RenderStatus = 'rendered';
                    elseif any(strcmp(id, {'model_performance.summary','model_performance.primary_plot','model_performance.confusion_matrix', ...
                            'model_performance.roc','model_performance.probability_distribution','model_performance.calibration','model_performance.dca','model_performance.model_permutation','model_performance.extra_label_permutation_gallery', ...
                            'model_optimization.selected_metric','model_optimization.metric_dashboard','model_optimization.cv_partitions','model_optimization.parameter_surface','model_optimization.sequence_diagnostics'}))
                        component.RenderStatus = 'rendered';
                    elseif any(strcmp(id, {'model_performance.payload','model_optimization.parameter_grid','model_optimization.scatter_comparison','model_optimization.pareto_summary'}))
                        component.RenderStatus = 'sidecar_only';
                    else
                        component.RenderStatus = 'table_only';
                    end
                else
                    component.RenderStatus = 'unavailable';
                end
            end
        end

        function counts = renderStatusCounts(comps)
            % renderStatusCounts  Count component RenderStatus values for audit metadata.
            labels = {'rendered','table_only','sidecar_only','unavailable','skipped_noninformative'};
            counts = struct('rendered',0,'table_only',0,'sidecar_only',0,'unavailable',0,'skipped_noninformative',0,'other',0);
            for ii=1:numel(comps)
                st = comps(ii).RenderStatus;
                hit = false;
                for jj=1:numel(labels)
                    if strcmpi(st, labels{jj})
                        counts.(labels{jj}) = counts.(labels{jj}) + 1;
                        hit = true;
                        break;
                    end
                end
                if ~hit, counts.other = counts.other + 1; end
            end
        end

        function available = scientificStateComponentAvailable(state,componentId)
            [kind,id]=NMResultsViewerReportTools.scientificStateTarget(componentId);
            if isempty(kind),available=false;return;end
            if strcmp(kind,'artefact'),available=NMResultsViewerScientificState.hasArtefact(state,id);
            else,available=NMResultsViewerScientificState.hasVisualization(state,id);end
        end

        function reason = stateReasonIfUnavailable(componentId,available)
            if available,reason='';else,reason=NMResultsViewerReportTools.scientificStateMissingReason(componentId);end
        end

        function reason = scientificStateMissingReason(componentId)
            [kind,id]=NMResultsViewerReportTools.scientificStateTarget(componentId);
            if isempty(kind),reason='The component is presentation-only and has no Scientific State capability.';
            else,reason=sprintf('Scientific State does not expose %s %s in the selected analysis context.',kind,id);end
        end

        function [kind,id,parameterized] = scientificStateTarget(component)
            kind='';id='';parameterized=false;
            if isstruct(component)
                componentId=component.Id;
                inst=component.Instance;
                componentType=inst.ComponentType;
                switch componentType
                    case 'feature_metric',kind='visualization';id='feature_metric_bar';parameterized=true;return;
                    case 'feature_metric_distribution',kind='visualization';id='feature_metric_distribution';parameterized=true;return;
                    case 'feature_metric_relationship',kind='visualization';id='feature_metric_relationship';parameterized=true;return;
                end
            else
                componentId=char(string(component));
            end
            exact={ ...
                'model_performance.summary','visualization','performance_summary_view'; ...
                'model_performance.primary_plot','visualization','primary_performance_plot'; ...
                'model_performance.confusion_matrix','visualization','confusion_matrix'; ...
                'model_performance.roc','visualization','roc_curve'; ...
                'model_performance.probability_distribution','visualization','probability_distribution'; ...
                'model_performance.calibration','visualization','calibration_curve'; ...
                'model_performance.dca','visualization','decision_curve'; ...
                'model_performance.model_permutation','visualization','model_permutation_histogram'; ...
                'model_performance.extra_label_permutation_gallery','visualization','extra_label_permutation_gallery'; ...
                'model_performance.payload','artefact','performance_payload'; ...
                'model_optimization.selected_metric','artefact','optimization_selected_metric'; ...
                'model_optimization.cv_partitions','artefact','optimization_cv_partitions'; ...
                'model_optimization.metric_dashboard','visualization','optimization_metric_dashboard'; ...
                'model_optimization.sequence_diagnostics','visualization','optimization_sequence_diagnostics'; ...
                'model_optimization.parameter_surface','visualization','optimization_parameter_surface'; ...
                'model_optimization.scatter_comparison','visualization','optimization_scatter_comparison'; ...
                'model_optimization.pareto_summary','visualization','optimization_pareto_summary'; ...
                'model_optimization.metric_registry','artefact','optimization_metric_registry'; ...
                'model_optimization.parameter_grid','artefact','optimization_parameter_grid'; ...
                'model_feature_inspection.modality_contribution','visualization','feature_modality_contribution_view'; ...
                'model_feature_inspection.component_summary','visualization','feature_component_summary_view'; ...
                'model_feature_inspection.fractionated_decision','artefact','feature_fractionated_decision'; ...
                'model_feature_inspection.fractionated_individual','visualization','feature_fractionated_individual_view'; ...
                'model_feature_inspection.fractionated_population','visualization','feature_fractionated_population_view'; ...
                'model_feature_inspection.fractionated_clusters','visualization','feature_fractionated_clusters_view'; ...
                'model_feature_inspection.component_modality_matrix','visualization','feature_component_modality_view'; ...
                'model_feature_inspection.feature_ranking','visualization','feature_ranking_view'; ...
                'model_feature_inspection.feature_metric_table','visualization','feature_metric_table_view'; ...
                'model_feature_inspection.correlation_matrix','visualization','feature_relation_matrix_view'; ...
                'model_feature_inspection.feature_network','visualization','feature_network'; ...
                'model_feature_inspection.extra_label_generalization','visualization','feature_extra_label_generalization_view'; ...
                'model_feature_inspection.spatial_map_summary','visualization','spatial_feature_map_summary'; ...
                'model_feature_inspection.payload','artefact','feature_inspection_payload'};
            hit=find(strcmp(exact(:,1),componentId),1);
            if ~isempty(hit),kind=exact{hit,2};id=exact{hit,3};return;end
            if strcmp(componentId,'model_feature_inspection.feature_metric_relationship')
                kind='visualization';id='feature_metric_relationship';parameterized=true;
            end
        end

        function component = componentTemplate()
            % componentTemplate  Create a fixed-schema component catalogue entry.
            component = struct('Id','','Label','','Viewspace','','Enabled',false, ...
                'MissingReason','','RequiredArtifacts',{{}}, ...
                'DefaultLayout',NMResultsViewerReportTools.componentLayoutTemplate(), ...
                'PayloadSchemaVersion',1,'PayloadSpec',struct(),'Instance',NMResultsViewerReportTools.componentInstanceTemplate());
        end

        function components = crossAnalysisComponents(analysisSetState,reportContext,spec,firstRow)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Declare set-level Cross-analysis performance/statistical/visual report artefacts from the queried Scientific State analysis_set inventory.
            % Syntax: components = NMResultsViewerReportTools.crossAnalysisComponents(analysisSetState,reportContext,spec,firstRow)
            % Inputs: Resident analysisSetState, fixed multi-analysis reportContext, caller selector spec and first report row.
            % Outputs: Performance Table, Statistical Comparison and Visual Comparison component catalogue entries with explicit fixed analysis-set payload specifications.
            % Authority and flow: Scientific State owns set membership, capabilities and nk_GetAnalysisStatus-derived CV groups; numerical materialization remains delegated to NMResultsViewerCrossAnalysisTools.
            % Scientific/state contract: Statistical Comparison is offered only when every selected analysis exposes Model Optimization and all belong to one Scientific State CV-equivalence group. Report Builder Visual Comparison requires Model Performance capability in at least two selected analyses, records unavailable members as exclusions and deliberately has no CV-equivalence gate; task-specific metric availability remains owned by NMResultsViewerCrossAnalysisTools/Model Performance. Report composition choices are not written into Scientific State.
            % Invariants: No raw NM/CV/result discovery occurs here; ordinary components remain analysis-local while these components retain explicit AnalysisIndices.
            % Materialization and performance: O(A) compact inventory planning only; no result matrices, files/XML/atlas/annotation/mesh resources, voxel/vertex scans or feature-scale arrays.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays; explicit Report Builder catalogue planning only.
            % Failure semantics: Invalid/mismatched analysis_set scope disables components with explicit reasons; no fallback compatibility inference is used.
            % Side effects: None.
            % Consumers and dependencies: Multi-analysis Report Builder catalogue; Scientific State and NMResultsViewerCrossAnalysisTools.
            if nargin<4||isempty(firstRow),firstRow=1;end
            if nargin<3||~isstruct(spec),spec=struct();end
            tmpl=NMResultsViewerReportTools.componentTemplate();components=repmat(tmpl,1,3);
            indices=double(reportContext.AnalysisIndices);
            inventory=analysisSetState.inventory;
            stateIndices=[];performanceMask=false(1,numel(inventory));optimizationMask=false(1,numel(inventory));cvGroups=zeros(1,numel(inventory));
            for ii=1:numel(inventory)
                stateIndices(end+1)=round(inventory(ii).analysisIndex); %#ok<AGROW>
                caps=inventory(ii).capabilities;
                performanceMask(ii)=caps.modelPerformance;
                optimizationMask(ii)=caps.modelOptimization;
                cvGroups(ii)=inventory(ii).cvGroup;
            end
            validScope=strcmp(analysisSetState.scope.type,'analysis_set')&&isequal(stateIndices,indices);
            % nm2-allow: crossAnalysisSource is written by NMResultsViewerCrossAnalysis.js; viewer specs carry source from viewerPlotOptions.
            payloadSpec=struct('resultType','comparison','analysisIndices',indices,'crossAnalysisSource',NMResultsViewerReportTools.structText(spec,{'crossAnalysisSource','source'},'cv'));
            copyFields={'metricIds','analysisAliases','targetIndex','modelSource','classifierIndex','referenceAnalysisIndex','referenceAnalysisIndices', ...
                'visualContextMode', ...
                'visualTargetIndex','visualModelSource','visualClassifierIndex','visualMultiClassModeIndex','multiClassModeIndex','visualMetricIds','visualPlotMode','visualSort','visualSeparateAxisMetricIds','visualMetricColors'};
            for ff=1:numel(copyFields),name=copyFields{ff};if isfield(spec,name),payloadSpec.(name)=spec.(name);end,end

            components(1).Id='cross_analysis.performance_table';components(1).Label='Cross-analysis performance table';components(1).Viewspace='cross_analysis';
            components(1).Enabled=validScope&&sum(performanceMask)>=2;
            if ~validScope,components(1).MissingReason='The fixed Report Builder analysis set has no matching Scientific State analysis_set inventory.';elseif sum(performanceMask)<2,components(1).MissingReason='Cross-analysis performance reporting requires Model Performance capability in at least two selected analyses.';end
            components(1).RequiredArtifacts={'analysis_set Scientific State inventory','annotated model-performance payloads from at least two selected analyses'};
            components(1).DefaultLayout=NMResultsViewerReportTools.componentLayoutTemplate();components(1).DefaultLayout.Row=firstRow;components(1).DefaultLayout.Order=firstRow;components(1).DefaultLayout.Group='cross_analysis';components(1).PayloadSpec=payloadSpec;

            components(2).Id='cross_analysis.statistical_comparison';components(2).Label='Cross-analysis statistical comparison';components(2).Viewspace='cross_analysis';
            components(2).Enabled=validScope&&numel(indices)>=2&&all(optimizationMask)&&numel(unique(cvGroups))==1;
            if ~validScope,components(2).MissingReason='The fixed Report Builder analysis set has no matching Scientific State analysis_set inventory.';elseif numel(indices)<2,components(2).MissingReason='Statistical comparison requires at least two selected analyses.';elseif ~all(optimizationMask),components(2).MissingReason='Statistical comparison requires Model Optimization capability in every selected analysis.';elseif numel(unique(cvGroups))~=1,components(2).MissingReason='Selected analyses are CV-incompatible according to the nk_GetAnalysisStatus-backed Scientific State inventory.';end
            components(2).RequiredArtifacts={'analysis_set Scientific State inventory with one CV-equivalence group','matched Model Optimization CV2 criterion matrices'};
            components(2).DefaultLayout=NMResultsViewerReportTools.componentLayoutTemplate();components(2).DefaultLayout.Row=firstRow+1;components(2).DefaultLayout.Order=firstRow+1;components(2).DefaultLayout.Group='cross_analysis';components(2).PayloadSpec=payloadSpec;


            components(3).Id='cross_analysis.visual_comparison';components(3).Label='Cross-analysis visual comparison';components(3).Viewspace='cross_analysis';
            components(3).Enabled=validScope&&sum(performanceMask)>=2;
            if ~validScope,components(3).MissingReason='The fixed Report Builder analysis set has no matching Scientific State analysis_set inventory.';elseif sum(performanceMask)<2,components(3).MissingReason='Visual comparison requires Model Performance capability in at least two selected analyses.';end
            components(3).RequiredArtifacts={'analysis_set Scientific State inventory','annotated aggregate CV/OOT Model Performance metrics'};
            visualPayloadSpec=payloadSpec;visualPayloadSpec.visualContextMode='per_analysis_default';
            components(3).DefaultLayout=NMResultsViewerReportTools.componentLayoutTemplate();components(3).DefaultLayout.Row=firstRow+2;components(3).DefaultLayout.Order=firstRow+2;components(3).DefaultLayout.Group='cross_analysis';components(3).PayloadSpec=visualPayloadSpec;
        end

        function components = modelOptimizationComponentsFromState(payloadSpec,state,firstRow,optPayload)
            % modelOptimizationComponentsFromState  Project Scientific State into fixed RB Optimization entries.
            if nargin < 3 || isempty(firstRow),firstRow=1;end
            ids = {'model_optimization.selected_metric', ...
                'model_optimization.cv_partitions', ...
                'model_optimization.metric_dashboard', ...
                'model_optimization.sequence_diagnostics', ...
                'model_optimization.parameter_surface', ...
                'model_optimization.scatter_comparison', ...
                'model_optimization.pareto_summary', ...
                'model_optimization.metric_registry', ...
                'model_optimization.parameter_grid'};
            labels = {'Selected optimization metric', ...
                'CV partition matrices', ...
                'Optimization metric dashboard', ...
                'SEQOPT stage-wise diagnostic curves and tables', ...
                '2D parameter surfaces', ...
                'Metric-vs-metric scatter comparison', ...
                'Pareto/frontier summary', ...
                'Optimization metric registry', ...
                'Parameter grid'};
            required = {{'selected optimization metric'}, {'CV partition artefact'}, ...
                {'optimization metric dashboard'}, {'SEQOPT normalized stage-wise diagnostic metrics'}, {'parameter-surface artefact'}, ...
                {'metric comparison artefact'}, {'Pareto/frontier artefact'}, ...
                {'optimization metric registry'}, {'parameter grid'}};
            keep=~strcmp(ids,'model_optimization.sequence_diagnostics') | ...
                NMResultsViewerReportTools.scientificStateComponentAvailable(state,'model_optimization.sequence_diagnostics');
            if optPayload.grid.nCombinations==1
                keep=keep & ismember(ids,{'model_optimization.cv_partitions','model_optimization.metric_registry','model_optimization.sequence_diagnostics'});
            end
            ids=ids(keep);labels=labels(keep);required=required(keep);
            tmpl=NMResultsViewerReportTools.componentTemplate();components=repmat(tmpl,1,numel(ids));
            for ii=1:numel(ids)
                available=NMResultsViewerReportTools.scientificStateComponentAvailable(state,ids{ii});
                components(ii).Id=ids{ii};components(ii).Label=labels{ii};components(ii).Viewspace='model_optimization';components(ii).Enabled=available;
                if ~available,components(ii).MissingReason=NMResultsViewerReportTools.scientificStateMissingReason(ids{ii});end
                components(ii).RequiredArtifacts=required{ii};components(ii).DefaultLayout=NMResultsViewerReportTools.componentLayoutTemplate();
                components(ii).DefaultLayout.Row=firstRow+ii-1;components(ii).DefaultLayout.Order=firstRow+ii-1;components(ii).DefaultLayout.Group='model_optimization';
                components(ii).PayloadSpec=payloadSpec;components(ii).PayloadSpec.resultType='model_optimization';
            end
        end

        function components = modelPerformanceComponentsFromState(payloadSpec,state,firstRow)
            % modelPerformanceComponentsFromState  Project Scientific State into fixed RB Performance entries.
            if nargin < 3 || isempty(firstRow), firstRow=1; end
            ids = {'model_performance.summary', ...
                'model_performance.primary_plot', ...
                'model_performance.confusion_matrix', ...
                'model_performance.roc', ...
                'model_performance.probability_distribution', ...
                'model_performance.calibration', ...
                'model_performance.dca', ...
                'model_performance.model_permutation', ...
                'model_performance.extra_label_permutation_gallery', ...
                'model_performance.payload'};
            labels = {'Model performance summary', ...
                'Primary model-performance plot', ...
                'Confusion matrix', ...
                'ROC curve', ...
                'Probability/score distribution', ...
                'Calibration component', ...
                'Decision-curve component', ...
                'Model permutation histogram', ...
                'Alternative-label permutation histograms', ...
                'Full model-performance payload'};
            required = {{'performance summary'}, {'primary performance plot'}, ...
                {'confusion analysis'}, {'ROC analysis'}, {'score/probability distribution'}, ...
                {'calibration analysis'}, {'decision-curve analysis'}, ...
                {'model permutation result'}, {'extra-label permutation result'}, {'performance payload'}};
            tmpl=NMResultsViewerReportTools.componentTemplate();
            components=repmat(tmpl,1,numel(ids));
            for ii=1:numel(ids)
                available=NMResultsViewerReportTools.scientificStateComponentAvailable(state,ids{ii});
                components(ii).Id=ids{ii}; components(ii).Label=labels{ii}; components(ii).Viewspace='model_performance';
                components(ii).Enabled=available;
                if ~available,components(ii).MissingReason=NMResultsViewerReportTools.scientificStateMissingReason(ids{ii});end
                components(ii).RequiredArtifacts=required{ii}; components(ii).DefaultLayout=NMResultsViewerReportTools.componentLayoutTemplate();
                components(ii).DefaultLayout.Row=firstRow+ii-1; components(ii).DefaultLayout.Order=firstRow+ii-1; components(ii).DefaultLayout.Group='model_performance';
                components(ii).PayloadSpec=payloadSpec;
            end
        end

        function tf = payloadHasAny(payload, fields)
            % payloadHasAny  Test whether a Results Viewer payload contains any non-empty field.
            tf = false;
            if ~isstruct(payload), return; end
            for ii = 1:numel(fields)
                f = fields{ii};
                if isfield(payload, f) && ~isempty(payload.(f))
                    tf = true;
                    return;
                end
            end
        end

        function session = reportBuildSession(NM)
            % reportBuildSession  Create a request-scoped report execution cache.
            %
            % The session is intentionally not serialized into the report. It stores
            % payload/action maps and a request-local NM value so probability
            % calibration generated by one component is visible to later components
            % without mutating the caller's workspace variable.
            if nargin < 1 || isempty(NM), NM = struct(); end
            session = struct();
            session.CurrentNM = NM;
            session.PayloadCache = containers.Map('KeyType','char','ValueType','any');
            session.ActionCache = containers.Map('KeyType','char','ValueType','any');
            session.ProbabilityCache = containers.Map('KeyType','char','ValueType','any');
            session.Stats = struct('payloadHits',0,'payloadMisses',0,'actionHits',0,'actionMisses',0, ...
                'probabilityHits',0,'probabilityMisses',0,'probabilityPersistEvents',0);
        end

        function [payload, session] = reportSessionPayload(session, family, payloadSpec)
            % reportSessionPayload  Resolve a scientific payload through the build-session cache.
            key = NMResultsViewerReportTools.reportPayloadCacheKey(family, payloadSpec);
            if isKey(session.PayloadCache, key)
                payload = session.PayloadCache(key);
                session.Stats.payloadHits = session.Stats.payloadHits + 1;
                return;
            end
            doProfile = NMRuntimeProgressTools.profileEnabled(); t = tic;
            switch lower(char(string(family)))
                case 'model_performance'
                    payload = NMResultsViewerTools.getPayload(session.CurrentNM, payloadSpec);
                case 'model_optimization'
                    payload = NMResultsViewerTools.getModelOptimizationPayload(session.CurrentNM, payloadSpec);
                case 'model_feature_inspection'
                    payload = NMResultsViewerTools.getModelFeatureInspectionPayload(session.CurrentNM, payloadSpec);
                case 'model_feature_relation'
                    payload = NMResultsViewerTools.getModelFeatureRelationPayload(session.CurrentNM, payloadSpec);
                otherwise
                    error('NMResultsViewerReportTools:UnknownPayloadFamily', 'Unknown report payload family "%s".', char(string(family)));
            end
            if doProfile, fprintf('[nm-prof]     report session payload family=%s: %.3fs\n',char(string(family)),toc(t)); end
            session.PayloadCache(key) = payload;
            session.Stats.payloadMisses = session.Stats.payloadMisses + 1;
        end

        function [actionPayload, session] = reportSessionActionPayload(session, payloadSpec, compSpec, action)
            % reportSessionActionPayload  Build calibration/DCA payloads with probability reuse.
            opts = struct();
            if isstruct(compSpec) && isfield(compSpec,'Options') && isstruct(compSpec.Options), opts = compSpec.Options; end
            actionSpec = payloadSpec;
            actionSpec.action = char(string(action));
            actionSpec.calibrationMethod = NMResultsViewerReportTools.structText(opts, {'CalibrationMethod','calibrationMethod'}, NMResultsViewerReportTools.structText(actionSpec, {'calibrationMethod','CalibrationMethod'}, 'platt'));
            actionSpec.forceRecomputeProbability = NMResultsViewerReportTools.structLogical(opts, {'ForceRecomputeProbability','forceRecomputeProbability'}, false);
            if strcmpi(char(string(action)), 'calibration')
                actionSpec.numBins = round(NMResultsViewerReportTools.structScalar(opts, {'NumBins','numBins'}, 10));
                actionSpec.smoothCurve = NMResultsViewerReportTools.structLogical(opts, {'SmoothCurve','smoothCurve'}, false);
                actionSpec.calibrationMetric = NMResultsViewerReportTools.structText(opts, {'CalibrationMetric','calibrationMetric'}, 'ECE');
            elseif strcmpi(char(string(action)), 'dca')
                actionSpec.maxProb = NMResultsViewerReportTools.structScalar(opts, {'MaxProb','maxProb'}, NaN);
                actionSpec.stepSize = NMResultsViewerReportTools.structScalar(opts, {'StepSize','stepSize'}, 0.05);
            end
            % Component options overwrite the normalized parent specification.
            % Re-materialize this report action exactly once before caching or
            % invoking the classification/regression action consumer.
            if isfield(actionSpec,'canonicalSpecVersion') % nm2-allow: the report action producer must invalidate a cached schema marker after mutating authoritative action fields.
                actionSpec = rmfield(actionSpec,'canonicalSpecVersion');
            end
            [~,actionSpec] = NMResultsViewerTools.viewerPlotOptions(actionSpec);
            key = NMResultsViewerReportTools.reportActionCacheKey(actionSpec);
            if isKey(session.ActionCache, key)
                actionPayload = session.ActionCache(key);
                session.Stats.actionHits = session.Stats.actionHits + 1;
                return;
            end
            probabilityKey = NMResultsViewerReportTools.reportProbabilityCacheKey(actionSpec);
            probabilityHit = isKey(session.ProbabilityCache, probabilityKey);
            if probabilityHit
                % Force-recompute is a once-per-build intent. After the first
                % canonical probability bundle has been derived, later Calibration
                % and DCA components reuse it through the request-local NM artifact.
                actionSpec.forceRecomputeProbability = false;
                session.Stats.probabilityHits = session.Stats.probabilityHits + 1;
            else
                session.Stats.probabilityMisses = session.Stats.probabilityMisses + 1;
            end
            [actionPayload, updatedNM, didPersist] = NMResultsViewerTools.getClassificationActionPayload(session.CurrentNM, actionSpec);
            if didPersist
                session.CurrentNM = updatedNM;
                session.Stats.probabilityPersistEvents = session.Stats.probabilityPersistEvents + 1;
            end
            if actionPayload.ok
                session.ProbabilityCache(probabilityKey) = true;
            end
            session.ActionCache(key) = actionPayload;
            session.Stats.actionMisses = session.Stats.actionMisses + 1;
        end

        function key = reportPayloadCacheKey(family, spec)
            % reportPayloadCacheKey  Hash the complete payload specification contract.
            %
            % The cache deliberately uses every field supplied to the authoritative
            % payload producer. This avoids false cache hits when a newer viewspace
            % introduces another content-determining option. Additional irrelevant
            % fields may reduce cache reuse, but they cannot make two scientifically
            % different payload requests collide.
            if ~isstruct(spec), spec = struct(); end
            key = [lower(char(string(family))) '|' jsonencode(orderfields(spec))];
        end

        function key = reportProbabilityCacheKey(spec)
            % reportProbabilityCacheKey  Hash the canonical score-to-probability context.
            %
            % Calibration-curve and DCA presentation options are deliberately
            % excluded because they do not change the underlying probability
            % conversion. All remaining producer inputs, including thresholds,
            % source, classifier, target, method and force-recompute intent, remain
            % part of the key.
            if ~isstruct(spec), spec = struct(); end
            presentationFields = {'action','numBins','smoothCurve','calibrationMetric', ...
                'maxProb','stepSize'};
            spec = NMResultsViewerReportTools.removeStructFields(spec,presentationFields);
            key = ['probability_bundle|' jsonencode(orderfields(spec))];
        end

        function key = reportActionCacheKey(spec)
            % reportActionCacheKey  Hash the complete derived-action specification.
            if ~isstruct(spec), spec = struct(); end
            key = ['model_performance_action|' jsonencode(orderfields(spec))];
        end

        function summary = reportBuildSessionSummary(session)
            % reportBuildSessionSummary  Return JSON-safe cache diagnostics for profiling.
            summary = struct('payloadHits',session.Stats.payloadHits,'payloadMisses',session.Stats.payloadMisses, ...
                'actionHits',session.Stats.actionHits,'actionMisses',session.Stats.actionMisses, ...
                'probabilityHits',session.Stats.probabilityHits,'probabilityMisses',session.Stats.probabilityMisses, ...
                'probabilityPersistEvents',session.Stats.probabilityPersistEvents, ...
                'payloadEntryCount',session.PayloadCache.Count,'actionEntryCount',session.ActionCache.Count, ...
                'probabilityEntryCount',session.ProbabilityCache.Count);
        end

        function [baseId, metricId, yMetricId] = modelFeatureInspectionComponentIdentity(component)
            % Purpose: Resolve Feature Inspection component semantics from structured Instance identity.
            % Scientific/state contract: Stable component Id values are opaque serialization identifiers; report logic must not parse them to recover metric or representation semantics.
            % Failure semantics: Missing or unknown structured component identity fails explicitly.
            inst = component.Instance;
            componentType = inst.ComponentType;
            metricId = inst.MetricId;
            yMetricId = inst.YMetricId;
            switch componentType
                case 'feature_metric'
                    baseId = 'model_feature_inspection.feature_metric_bar';
                    if isempty(metricId)
                        error('NMResultsViewerReportTools:MissingFeatureMetricIdentity', ...
                            'Feature metric component %s has no structured MetricId.',component.Id);
                    end
                case 'feature_metric_distribution'
                    baseId = 'model_feature_inspection.feature_metric_distribution';
                    if isempty(metricId)
                        error('NMResultsViewerReportTools:MissingFeatureMetricIdentity', ...
                            'Feature metric distribution %s has no structured MetricId.',component.Id);
                    end
                case 'feature_metric_relationship'
                    baseId = 'model_feature_inspection.feature_metric_relationship';
                    if isempty(metricId) || isempty(yMetricId)
                        error('NMResultsViewerReportTools:MissingFeatureMetricIdentity', ...
                            'Feature metric relationship %s requires structured MetricId and YMetricId.',component.Id);
                    end
                case 'modality_contribution'
                    baseId = 'model_feature_inspection.modality_contribution';
                case 'component_summary'
                    baseId = 'model_feature_inspection.component_summary';
                case 'fractionated_decision'
                    baseId = 'model_feature_inspection.fractionated_decision';
                case 'fractionated_individual'
                    baseId = 'model_feature_inspection.fractionated_individual';
                case 'fractionated_population'
                    baseId = 'model_feature_inspection.fractionated_population';
                case 'fractionated_clusters'
                    baseId = 'model_feature_inspection.fractionated_clusters';
                case 'component_modality_matrix'
                    baseId = 'model_feature_inspection.component_modality_matrix';
                case 'feature_ranking'
                    baseId = 'model_feature_inspection.feature_ranking';
                case 'feature_metric_table'
                    baseId = 'model_feature_inspection.feature_metric_table';
                case 'feature_relations_matrix'
                    baseId = 'model_feature_inspection.correlation_matrix';
                case 'feature_relations_graph'
                    baseId = 'model_feature_inspection.feature_network';
                case 'extra_label_generalization'
                    baseId = 'model_feature_inspection.extra_label_generalization';
                case 'spatial_provenance'
                    baseId = 'model_feature_inspection.spatial_map_summary';
                case 'technical_payload'
                    baseId = 'model_feature_inspection.payload';
                otherwise
                    error('NMResultsViewerReportTools:UnknownFeatureComponentType', ...
                        'Unknown Feature Inspection component type "%s" for component %s.',componentType,component.Id);
            end
        end

        function specs = modelFeatureInspectionMetricSpecs(payload, featureRows)
            % Scientific metadata comes from the fixed Feature Inspection measure producer.
            % Only feature-row projection and finite, nonzero table availability live here.
            tmpl = struct('metricId','','label','','field','','seField','','category','', ...
                'sourceField','','valuePolarity','signed','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN, ...
                'thresholdValue',NaN,'thresholdLabel','No threshold','available',false);
            defs = NMResultsViewerReportTools.modelFeatureInspectionMetricDefinitions();
            measures = payload.measures;
            specs = repmat(tmpl,1,numel(defs));
            count = 0;
            for ii = 1:numel(defs)
                rowDef = defs(ii);
                hit = find(strcmp({measures.sourceField},rowDef.sourceField) & [measures.enabled],1,'first');
                if isempty(hit), continue; end
                if ~isempty(featureRows)
                    values=NMResultsViewerReportTools.structNumericArray(featureRows,rowDef.field);
                    if ~any(isfinite(values) & abs(values)>1e-12), continue; end
                end
                m=measures(hit);
                count=count+1;
                specs(count) = struct('metricId',m.measureId,'label',m.label,'field',rowDef.field, ...
                    'seField',rowDef.seField,'category',m.category,'sourceField',m.sourceField, ...
                    'valuePolarity',m.valuePolarity,'thresholdMode',m.thresholdMode, ...
                    'thresholdLow',m.thresholdLow,'thresholdHigh',m.thresholdHigh, ...
                    'thresholdValue',m.thresholdValue,'thresholdLabel',m.thresholdLabel,'available',true);
            end
            specs=specs(1:count);
        end

        function defs = modelFeatureInspectionMetricDefinitions()
            % Only the feature-table representation mapping belongs to Report Builder.
            % Scientific metric identity, thresholds and labels come from payload.measures.
            raw = { ...
                'MEAN','meanWeight','seWeight'; ...
                'CVRatio','crossValidationRatio',''; ...
                'FeatProb','featureSelectionProbability',''; ...
                'Prob_CV2','reliabilityProbability95CI',''; ...
                'SignBased_CV2','signConsistency',''; ...
                'SignBased_CV2_z','signConsistencyZ',''; ...
                'SignBased_CV2_p_uncorr','signConsistencyLogP',''; ...
                'SignBased_CV2_p_fdr','signConsistencyLogQ',''; ...
                'Spearman_CV2','spearmanAssociation',''; ...
                'Pearson_CV2','pearsonAssociation',''; ...
                'Spearman_CV2_p_uncorr','spearmanLogP',''; ...
                'Pearson_CV2_p_uncorr','pearsonLogP',''; ...
                'Spearman_CV2_p_fdr','spearmanLogQ',''; ...
                'Pearson_CV2_p_fdr','pearsonLogQ',''; ...
                'PermZ_CV2','permutationZ',''; ...
                'PermProb_CV2','permutationLogP',''; ...
                'PermProb_CV2_FDR','permutationLogQ',''; ...
                'Analytical_p','analyticalLogP',''; ...
                'Analyitcal_p_fdr','analyticalLogQ','' };
            defs = repmat(struct('sourceField','','field','','seField',''),1,size(raw,1));
            for ii = 1:size(raw,1)
                defs(ii).sourceField=raw{ii,1};
                defs(ii).field=raw{ii,2};
                defs(ii).seField=raw{ii,3};
            end
        end

        function [metricSpec, found] = modelFeatureInspectionMetricById(metricSpecs, metricId)
            % Resolve exact producer-defined scientific measure identity.
            found=false;
            metricSpec=struct('metricId','','label','','field','','seField','','category','', ...
                'sourceField','','valuePolarity','signed','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN, ...
                'thresholdValue',NaN,'thresholdLabel','No threshold','available',false);
            if isempty(metricSpecs), return; end
            hit=find(strcmp({metricSpecs.metricId},metricId),1,'first');
            if isempty(hit), return; end
            metricSpec=metricSpecs(hit);
            found=true;
        end

        function [rows, metricSpec] = modelFeatureInspectionRowsForMetric(featureRows, metricSpec, opts)
            % modelFeatureInspectionRowsForMetric  Project feature rows onto one selected browser/report metric state.
            %
            % [rows, metricSpec] = NMResultsViewerReportTools.modelFeatureInspectionRowsForMetric(featureRows, metricSpec, opts)
            % applies the explicit browser-side Feature Inspection state serialized by
            % the Results Viewer. The transformation is deterministic and read-only:
            % feature index expressions are interpreted by NMSerializationTools,
            % threshold overrides are folded into metricSpec, and sorting,
            % subthreshold display mode, alternative labels and optional pagination are
            % applied before table/plot export. This prevents Report Builder exports
            % from inferring state from the DOM.
            rows = NMResultsViewerReportTools.modelFeatureInspectionRowsForFields(featureRows, fieldnames(NMResultsViewerReportTools.featureMetricProjectedRowTemplate()));
            if isempty(featureRows), rows = rows([]); return; end
            metricSpec = NMResultsViewerReportTools.applyFeatureMetricThresholdOptions(metricSpec, opts);
            vals = NMResultsViewerReportTools.structNumericArray(featureRows, metricSpec.field);
            if isempty(metricSpec.seField)
                se = NaN(size(vals));
            else
                se = NMResultsViewerReportTools.structNumericArray(featureRows, metricSpec.seField);
                if numel(se) ~= numel(vals)
                    error('NMResultsViewerReportTools:FeatureMetricAxis', ...
                        'Selected metric and standard-error vectors disagree on the feature axis.');
                end
            end
            if ~any(isfinite(vals)), rows = rows([]); return; end
            displaySpec = struct('PositiveColor',opts.PositiveColor, ...
                'NegativeColor',opts.NegativeColor, ...
                'MidpointColor',opts.MidpointColor);
            identity = struct('metricId',metricSpec.metricId,'sourceField',metricSpec.sourceField);
            displayContract = NMResultsViewerDisplaySemanticsTools.resolveContract(vals,metricSpec,displaySpec,identity);
            metricSpec.displayContract = displayContract;
            keep = isfinite(vals);
            requestedIdx = NMResultsViewerReportTools.featureMetricOptionIndices(opts);
            if ~isempty(requestedIdx)
                rowIdx = NMResultsViewerReportTools.structNumericArray(featureRows, 'featureIndex');
                keep = keep & ismember(round(rowIdx(:)), requestedIdx(:));
            end
            ordinal = (1:numel(vals))';
            featureRows = featureRows(keep); vals = vals(keep); se = se(keep); ordinal = ordinal(keep);
            if isempty(vals), rows = rows([]); return; end
            tmpl = NMResultsViewerReportTools.featureMetricProjectedRowTemplate();
            rows = repmat(tmpl, 1, numel(vals));
            signedRanks = NMResultsViewerReportTools.metricRanks(vals, false);
            absRanks = NMResultsViewerReportTools.metricRanks(vals, true);
            labelOptions = NMResultsViewerReportTools.featureMetricAlternativeLabelOptions(opts);
            for ii = 1:numel(vals)
                rows(ii) = NMResultsViewerReportTools.featureMetricProjectedRowFromFeature(featureRows(ii), metricSpec, vals(ii), se(ii), displayContract);
                rows(ii).featureName = NMResultsViewerReportTools.featureMetricAlternativeLabel(rows(ii).featureName, rows(ii).featureIndex, ordinal(ii), labelOptions);
                rows(ii).tooltipTitle = rows(ii).featureName;
                rows(ii).sortSignedRank = signedRanks(ii);
                rows(ii).sortAbsRank = absRanks(ii);
            end
            subMode = opts.SubthresholdHandling;
            if strcmp(subMode,'hide')
                rows = rows([rows.thresholdPassed]);
            elseif strcmp(subMode,'only')
                rows = rows(~[rows.thresholdPassed]);
            end
            rows = NMResultsViewerReportTools.sortFeatureMetricRows(rows, opts.SortMode);
            if opts.ApplyPagination
                rows = NMResultsViewerReportTools.paginateFeatureMetricRows(rows, opts);
            end
        end

        % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
        function opts = featureMetricOptionsFromComponentOptions(compOptions, panels, metricId)
            % featureMetricOptionsFromComponentOptions  Normalize serialized browser Feature Inspection state for one metric.
            %
            % opts = NMResultsViewerReportTools.featureMetricOptionsFromComponentOptions(compOptions, metricId)
            % reads both the explicit component Options fields and the nested
            % BrowserFeatureInspectionViewState.panels.<metricId> object emitted by
            % the browser Results Viewer. The normalized option names are consumed by
            % report/table/figure builders so exports reproduce the current browser
            % state without reading DOM elements. ShowAllRows is preserved separately
            % from PageSize because the browser deliberately disables, but does not
            % erase, the page-size control while all rows are displayed.
            opts = struct('MetricId',metricId,'FeatureIndexExpression','', ...
                'FeatureIndices',[],'SubsetMode','all_features','SortMode','abs_desc', ...
                'PageSize',20,'ShowAllRows',false,'CurrentPage',1,'ApplyPagination',false, ...
                'PositiveColor','#dc2626','NegativeColor','#2563eb','MidpointColor','#ffffff','SubthresholdColor','#cbd5e1', ...
                'BarWidth',12,'BarEdge',false, ...
                'ThresholdEnabled',true,'ThresholdMode','','ThresholdLow',NaN,'ThresholdHigh',NaN, ...
                'ThresholdValue',NaN,'HistogramBins',20,'SubthresholdHandling','grey', ...
                'TableRowCount',20,'AlternativeLabelsText','','AlternativeLabelsResolved',{{}});
            raw = struct();
            % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
            if isfield(panels, metricId)
                raw = panels.(metricId);
            end
            opts = NMResultsViewerReportTools.featureMetricOptionsOverlay(opts, raw, false);
            opts = NMResultsViewerReportTools.featureMetricOptionsOverlay(opts, compOptions, true);
            opts.ThresholdMode = strtrim(opts.ThresholdMode);
            opts.BarWidth = max(5,min(24,round(double(opts.BarWidth))));
            if isempty(opts.BarEdge), opts.BarEdge = false; else, opts.BarEdge = logical(opts.BarEdge(1)); end
        end

        function opts = featureMetricOptionsOverlay(opts, raw, topLevel)
            % Convert one partial external panel layer to the fixed options schema.
            % Canonical component fields take precedence in the top-level layer;
            % browser panel fields are the only inputs in the captured layer.
            if ~isstruct(raw), return; end
            % nm2-allow: This existing component-options producer admits partial browser fields once; readers consume the resulting fixed-schema opts directly.
            persistent fields
            if isempty(fields)
                fields = { ...
                'FeatureIndexExpression','FeatureIndexExpression','featureExpression','text'; ...
                'FeatureIndices','FeatureIndices','featureIndices','vector'; ...
                'SubsetMode','SubsetMode','subsetMode','text'; ...
                'SortMode','SortMode','sortingMode','text'; ...
                'PageSize','PageSize','pageSize','scalar'; ...
                'ShowAllRows','ShowAllRows','showAllRows','logical'; ...
                'CurrentPage','CurrentPage','currentPage','scalar'; ...
                'PositiveColor','PositiveColor','positiveColor','text'; ...
                'NegativeColor','NegativeColor','negativeColor','text'; ...
                'MidpointColor','MidpointColor','midpointColor','text'; ...
                'SubthresholdColor','SubthresholdColor','subthresholdColor','text'; ...
                'BarWidth','BarWidth','barWidth','scalar'; ...
                'BarEdge','BarEdge','barEdge','logical'; ...
                'ThresholdEnabled','ThresholdEnabled','thresholdEnabled','logical'; ...
                'ThresholdMode','ThresholdMode','thresholdMode','text'; ...
                'ThresholdLow','ThresholdLow','thresholdLow','scalar'; ...
                'ThresholdHigh','ThresholdHigh','thresholdHigh','scalar'; ...
                'ThresholdValue','ThresholdValue','thresholdValue','scalar'; ...
                'HistogramBins','HistogramBins','histogramBins','scalar'; ...
                'SubthresholdHandling','SubthresholdHandling','subthresholdHandling','text'; ...
                'TableRowCount','TableRowCount','tableRowCount','scalar'; ...
                'AlternativeLabelsText','AlternativeLabelsText','altLabelsText','text'; ...
                'AlternativeLabelsResolved','AlternativeLabelsResolved','altLabelsResolved','labels'; ...
                };
            end
            for ii=1:size(fields,1)
                destination=fields{ii,1};
                if topLevel
                    candidates=fields(ii,2:3);
                else
                    candidates=fields(ii,3);
                end
                for jj=1:numel(candidates)
                    fieldName=candidates{jj};
% nm2-allow: Feature-metric option fields may be absent; component projection establishes defaults here.
                    if ~isfield(raw,fieldName) || isempty(raw.(fieldName)), continue; end
                    optionValue=raw.(fieldName);
                    valid=true;
                    switch fields{ii,4}
                        case 'text'
% nm2-allow: Captured option text needs one conversion in the existing typed-options producer.
                            optionValue=char(string(optionValue));
                        case 'scalar'
% nm2-allow: Captured scalar options may be numeric or logical before typed projection.
                            if isnumeric(optionValue) || islogical(optionValue)
                                optionValue=double(optionValue(1));
                            else
% nm2-allow: Captured numeric option strings are converted once in the typed-options producer.
                                optionValue=str2double(char(string(optionValue)));
                            end
                            valid=isfinite(optionValue);
                        case 'logical'
% nm2-allow: Captured boolean options may be numeric or logical before typed projection.
                            if islogical(optionValue) || isnumeric(optionValue)
                                optionValue=logical(optionValue(1));
                            else
% nm2-allow: Captured boolean text is converted once in the typed-options producer.
                                optionValue=any(strcmp(lower(strtrim(char(string(optionValue)))),{'true','1','yes','on'}));
                            end
                        case 'vector'
% nm2-allow: Captured feature-index vectors must be numeric for typed projection.
                            valid=isnumeric(optionValue);
                            if valid,optionValue=double(optionValue(:))';end
                        case 'labels'
                            optionValue=NMSerializationTools.normalizeTextLabelVector(optionValue,50000);
                    end
                    if valid
                        opts.(destination)=optionValue;
                        break;
                    end
                end
            end
            opts.PageSize=max(1,min(500,round(double(opts.PageSize))));
            opts.CurrentPage=max(1,round(double(opts.CurrentPage)));
            opts.HistogramBins=max(3,min(80,round(double(opts.HistogramBins))));
            opts.TableRowCount=max(1,min(500,round(double(opts.TableRowCount))));
        end

        function spec = applyFeatureMetricThresholdOptions(spec, opts)
            % applyFeatureMetricThresholdOptions  Apply browser threshold controls to one metric descriptor.
            if ~opts.ThresholdEnabled
                spec.thresholdMode = 'none';
                spec.thresholdLow = NaN; spec.thresholdHigh = NaN; spec.thresholdValue = NaN;
                spec.thresholdLabel = 'No threshold';
                return;
            end
            mode = opts.ThresholdMode;
            if ~isempty(mode), spec.thresholdMode = mode; end
            if isfinite(opts.ThresholdLow),spec.thresholdLow=opts.ThresholdLow;end
            if isfinite(opts.ThresholdHigh),spec.thresholdHigh=opts.ThresholdHigh;end
            if isfinite(opts.ThresholdValue),spec.thresholdValue=opts.ThresholdValue;end
            spec.thresholdLabel = NMResultsViewerReportTools.featureMetricThresholdLabel(spec);
        end

        function label = featureMetricThresholdLabel(spec)
            % featureMetricThresholdLabel  Format one validated canonical threshold.
            threshold = NMResultsViewerDisplaySemanticsTools.thresholdFromSpec(spec);
            switch threshold.mode
                case 'above'
                    label = sprintf('Metric >= %.4g', threshold.value);
                case 'below'
                    label = sprintf('Metric <= %.4g', threshold.value);
                case 'outside_interval'
                    label = sprintf('Metric <= %.4g or >= %.4g', threshold.lower, threshold.upper);
                case 'above_abs'
                    label = sprintf('|metric| >= %.4g', threshold.value);
                case 'none'
                    label = 'No threshold';
                otherwise
                    error('NMResultsViewerReportTools:InvalidThresholdMode', ...
                        'Canonical threshold mode is unsupported: %s',threshold.mode);
            end
        end

        function idx = featureMetricOptionIndices(opts)
            % featureMetricOptionIndices  Resolve explicit feature-index vectors from report options.
            idx = [];
            if ~isempty(opts.FeatureIndices)
                idx = opts.FeatureIndices(:);
            elseif ~isempty(strtrim(opts.FeatureIndexExpression))
                try
                    [parsed, ~] = NMSerializationTools.interpretNumericExpression(opts.FeatureIndexExpression, 'numeric_vector');
                    idx = parsed(:);
                catch ME
                    error('NMResultsViewerReportTools:featureIndexExpression', ...
                        'Feature-index expression could not be interpreted: %s', ME.message);
                end
            end
            idx = unique(round(idx(isfinite(idx) & idx >= 1)), 'stable');
        end

        function labelOptions = featureMetricAlternativeLabelOptions(opts)
            % featureMetricAlternativeLabelOptions  Parse browser alternative-feature-name text into deterministic maps.
            labelOptions = struct('mapIndex',[],'mapLabel',{{}},'sequenceLabel',{{}});
            seq = cell(1,0); idx = []; labs = cell(1,0);
            hasResolvedLabels = false;
            if ~isempty(opts.AlternativeLabelsResolved)
                seq = opts.AlternativeLabelsResolved;
                hasResolvedLabels = true;
            end
            txt = opts.AlternativeLabelsText;
            if isempty(strtrim(txt))
                labelOptions.sequenceLabel = seq; return;
            end
            literalParsed = false;
            if isempty(seq) && ~isempty(regexp(strtrim(txt), '^[\{\[].*[\}\]]$', 'once'))
                q = regexp(txt, '''([^'']*)''|"([^"]*)"', 'tokens');
                if ~isempty(q)
                    literalParsed = true;
                    for qq = 1:numel(q)
                        tok = q{qq};
                        if ~isempty(tok{1}), seq{end+1} = tok{1}; else, seq{end+1} = tok{2}; end %#ok<AGROW>
                    end
                end
            end
            directLineMode = ~hasResolvedLabels && ~literalParsed && isempty(regexp(strtrim(txt), '^[A-Za-z_]\w*$', 'once'));
            lines = regexp(txt, '\r\n|\n|\r', 'split');
            for ii = 1:numel(lines)
                line = strtrim(lines{ii});
                if isempty(line), continue; end
                tok = regexp(line, '^(?:#?\s*)?(\d+)\s*[:=,]\s*(.+)$', 'tokens', 'once');
                if ~isempty(tok)
                    idx(end+1) = str2double(tok{1}); %#ok<AGROW>
                    labs{end+1} = strtrim(tok{2}); %#ok<AGROW>
                elseif directLineMode
                    seq{end+1} = line; %#ok<AGROW>
                end
            end
            labelOptions.mapIndex = idx;
            labelOptions.mapLabel = labs;
            labelOptions.sequenceLabel = seq;
        end

        function label = featureMetricAlternativeLabel(originalLabel, featureIndex, ordinal, labelOptions)
            % featureMetricAlternativeLabel  Resolve one browser-supplied feature label override.
            label = originalLabel;
            idx = labelOptions.mapIndex;
            labs = labelOptions.mapLabel;
            if ~isempty(idx) && isfinite(featureIndex)
                hit = find(round(idx(:)) == round(featureIndex), 1, 'first');
                if ~isempty(hit), label = labs{hit}; return; end
            end
            seq = labelOptions.sequenceLabel;
            % nm2-allow: Browser alternative-label sequence may be shorter than the selected feature ordinal; check the external label axis.
            if isfinite(ordinal) && ordinal >= 1 && round(ordinal) <= numel(seq)
                label = seq{round(ordinal)};
            end
        end

        function rows = sortFeatureMetricRows(rows, sortMode)
            % sortFeatureMetricRows  Sort projected metric rows using browser sort tokens.
            if isempty(rows), return; end
            mode = sortMode;
            vals = NMResultsViewerReportTools.structNumericArray(rows, 'displayValue');
            switch mode
                case 'abs_asc'
                    [~, order] = sort(abs(vals), 'ascend', 'MissingPlacement', 'last');
                case 'signed_desc'
                    [~, order] = sort(vals, 'descend', 'MissingPlacement', 'last');
                case 'signed_asc'
                    [~, order] = sort(vals, 'ascend', 'MissingPlacement', 'last');
                case 'feature_index'
                    idx = NMResultsViewerReportTools.structNumericArray(rows, 'featureIndex');
                    [~, order] = sort(idx, 'ascend', 'MissingPlacement', 'last');
                case 'label'
                    labels = NMResultsViewerReportTools.rowTextArray(rows, 'featureName');
                    [~, order] = sort(lower(string(labels)));
                otherwise
                    [~, order] = sort(abs(vals), 'descend', 'MissingPlacement', 'last');
            end
            rows = rows(order);
        end

        function rows = paginateFeatureMetricRows(rows, opts)
            % paginateFeatureMetricRows  Apply the authoritative browser row-window contract.
            %
            % rows = NMResultsViewerReportTools.paginateFeatureMetricRows(rows, opts)
            % returns every sorted/filtered row when ShowAllRows is true. Otherwise it
            % applies the normalized PageSize and CurrentPage values. The method is the
            % single Report Builder pagination gate for ordinary feature-metric bars;
            % it must not infer row visibility from disabled page-size controls or from
            % report defaults. Scientific values and row ordering are not changed.
            if isempty(rows), return; end
            if opts.ShowAllRows
                return;
            end
            pageSize = opts.PageSize;
            currentPage = opts.CurrentPage;
            nPages = max(1, ceil(numel(rows) ./ pageSize));
            currentPage = min(nPages, currentPage);
            first = (currentPage - 1) .* pageSize + 1;
            last = min(numel(rows), first + pageSize - 1);
            rows = rows(first:last);
        end

        function row = featureMetricProjectedRowFromFeature(src, metricSpec, value, se, displayContract)
            row = NMResultsViewerReportTools.featureMetricProjectedRowTemplate();
            names = fieldnames(row);
            for ii = 1:numel(names)
                row.(names{ii}) = src.(names{ii});
            end
            passed = NMResultsViewerDisplaySemanticsTools.extremaEligible(value, displayContract, true);
            row.measureId = metricSpec.metricId;
            row.displayValue = value;
            row.displaySE = se;
            row.thresholdPassed = passed;
            row.barState = NMResultsViewerReportTools.stateFromThreshold(passed, value, 'bar');
            row.labelState = NMResultsViewerReportTools.stateFromThreshold(passed, value, 'label');
            row.errorBarState = NMResultsViewerReportTools.stateFromThreshold(passed, value, 'error');
            row.tooltipSubtitle = metricSpec.label;
            row.tooltipMetricPrimary = value;
            row.tooltipMetricPrimaryLabel = metricSpec.label;
            row.tooltipMetricSE = se;
            if isfinite(se), row.tooltipMetricSELabel = 'Standard error'; else, row.tooltipMetricSELabel = ''; end
            row.tooltipThresholdLabel = metricSpec.thresholdLabel;
            row.tooltipThresholdPassed = passed;
            row.tooltipSourceField = metricSpec.sourceField;
        end

        function tmpl = featureMetricProjectedRowTemplate()
            tmpl = struct('contextId','','measureId','','featureIndex',NaN,'featureName','', ...
                'displayValue',NaN,'displaySE',NaN,'meanWeight',NaN,'seWeight',NaN, ...
                'crossValidationRatio',NaN,'featureSelectionProbability',NaN,'reliabilityProbability95CI',NaN, ...
                'signConsistency',NaN,'signConsistencyZ',NaN,'signConsistencyLogP',NaN,'signConsistencyLogQ',NaN, ...
                'spearmanAssociation',NaN,'pearsonAssociation',NaN,'spearmanLogP',NaN,'pearsonLogP',NaN, ...
                'spearmanLogQ',NaN,'pearsonLogQ',NaN,'permutationZ',NaN,'permutationLogP',NaN, ...
                'permutationLogQ',NaN,'analyticalLogP',NaN,'analyticalLogQ',NaN,'thresholdPassed',false, ...
                'barState','missing','labelState','missing','errorBarState','missing','sortSignedRank',NaN, ...
                'sortAbsRank',NaN,'featureKind','','provenanceId','','tooltipTitle','','tooltipSubtitle','', ...
                'tooltipMetricPrimary',NaN,'tooltipMetricPrimaryLabel','','tooltipMetricSE',NaN,'tooltipMetricSELabel','', ...
                'tooltipThresholdLabel','','tooltipThresholdPassed',false,'tooltipRankSigned',NaN,'tooltipRankAbsolute',NaN, ...
                'tooltipSelectionProbability',NaN,'tooltipStabilitySummary','','tooltipSourceField','','tooltipProvenanceSummary','');
        end

        function rows = modelFeatureInspectionMetricTableRows(featureRows, metricSpecs)
            % modelFeatureInspectionMetricTableRows  Compact table containing all available feature metrics.
            tmpl = NMResultsViewerReportTools.modelFeatureInspectionMetricTableRowTemplate();
            rows = repmat(tmpl, 1, 0);
            if isempty(featureRows), return; end
            n = numel(featureRows);
            rows = repmat(tmpl, 1, n);
            for ii = 1:n
                rows(ii).featureName = featureRows(ii).featureName;
                rows(ii).featureKind = featureRows(ii).featureKind;
                rows(ii).provenance = featureRows(ii).tooltipProvenanceSummary;
                rows(ii).absRank = featureRows(ii).sortAbsRank;
                for mm = 1:numel(metricSpecs)
                    fld = metricSpecs(mm).field;
                    rows(ii).(fld) = featureRows(ii).(fld);
                end
            end
        end

        function tmpl = modelFeatureInspectionMetricTableRowTemplate()
            tmpl = struct('featureName','','featureKind','','provenance','','absRank',NaN, ...
                'meanWeight',NaN,'crossValidationRatio',NaN,'featureSelectionProbability',NaN, ...
                'reliabilityProbability95CI',NaN,'signConsistency',NaN,'signConsistencyZ',NaN, ...
                'signConsistencyLogP',NaN,'signConsistencyLogQ',NaN,'spearmanAssociation',NaN, ...
                'pearsonAssociation',NaN,'spearmanLogP',NaN,'pearsonLogP',NaN, ...
                'spearmanLogQ',NaN,'pearsonLogQ',NaN,'permutationZ',NaN, ...
                'permutationLogP',NaN,'permutationLogQ',NaN,'analyticalLogP',NaN,'analyticalLogQ',NaN);
        end

        function rows = modelFeatureInspectionRelationshipPresets(metricSpecs)
            tmpl = struct('xMetricId','','yMetricId','','label','','enabled',false);
            preset = {
                'cross_validation_ratio','sign_consistency_logp','Cross-validation ratio vs SBC -log10(P)';
                'feature_weight_mean','feature_selection_probability','Mean feature weight vs feature-selection probability';
                'feature_weight_mean','cross_validation_ratio','Mean feature weight vs cross-validation ratio';
                'analytical_logq','permutation_logq','Analytical -log10(q) vs permutation -log10(q)';
                'pearson_association','spearman_association','Pearson association vs Spearman association'};
            rows = repmat(tmpl, 1, size(preset,1));
            for ii = 1:size(preset,1)
                rows(ii).xMetricId = preset{ii,1}; rows(ii).yMetricId = preset{ii,2}; rows(ii).label = preset{ii,3};
                rows(ii).enabled = NMResultsViewerReportTools.metricExists(metricSpecs, rows(ii).xMetricId) && NMResultsViewerReportTools.metricExists(metricSpecs, rows(ii).yMetricId);
            end
            rows = rows([rows.enabled]);
        end

        function tf = metricExists(metricSpecs, metricId)
            tf = any(strcmp({metricSpecs.metricId},metricId));
        end

        function [rows, xSpec, ySpec] = modelFeatureInspectionRelationshipRows( ...
                featureRows, xSpec, ySpec, xOptions, yOptions)
            tmpl = struct('featureName','','featureIndex',NaN,'xMetricId','','yMetricId','', ...
                'xMetricLabel','','yMetricLabel','','xValue',NaN,'yValue',NaN,'xThresholdPassed',false, ...
                'yThresholdPassed',false,'thresholdPassedAny',false,'thresholdPassedBoth',false, ...
                'pointState','missing','labelState','missing','featureKind','','tooltipTitle','', ...
                'tooltipProvenanceSummary','');
            rows = repmat(tmpl, 1, 0);
            if isempty(featureRows), return; end
            xSpec = NMResultsViewerReportTools.applyFeatureMetricThresholdOptions(xSpec,xOptions);
            ySpec = NMResultsViewerReportTools.applyFeatureMetricThresholdOptions(ySpec,yOptions);
            x = NMResultsViewerReportTools.structNumericArray(featureRows, xSpec.field);
            y = NMResultsViewerReportTools.structNumericArray(featureRows, ySpec.field);
            if ~any(isfinite(x)) || ~any(isfinite(y)), return; end
            xDisplay = struct('PositiveColor',xOptions.PositiveColor, ...
                'NegativeColor',xOptions.NegativeColor, ...
                'MidpointColor',xOptions.MidpointColor);
            yDisplay = struct('PositiveColor',yOptions.PositiveColor, ...
                'NegativeColor',yOptions.NegativeColor, ...
                'MidpointColor',yOptions.MidpointColor);
            xContract = NMResultsViewerDisplaySemanticsTools.resolveContract( ...
                x,xSpec,xDisplay,struct('metricId',xSpec.metricId));
            yContract = NMResultsViewerDisplaySemanticsTools.resolveContract( ...
                y,ySpec,yDisplay,struct('metricId',ySpec.metricId));
            xSpec.displayContract = xContract;
            ySpec.displayContract = yContract;
            good = isfinite(x) & isfinite(y);
            featureRows = featureRows(good); x = x(good); y = y(good);
            if isempty(x), return; end
            [~, order] = sort(abs(x).*max(1,abs(y)), 'descend');
            featureRows = featureRows(order); x = x(order); y = y(order);
            rows = repmat(tmpl, 1, numel(x));
            for ii = 1:numel(x)
                xp = NMResultsViewerDisplaySemanticsTools.extremaEligible(x(ii),xContract,true);
                yp = NMResultsViewerDisplaySemanticsTools.extremaEligible(y(ii),yContract,true);
                rows(ii).featureName = featureRows(ii).featureName;
                rows(ii).featureIndex = featureRows(ii).featureIndex;
                rows(ii).xMetricId = xSpec.metricId; rows(ii).yMetricId = ySpec.metricId;
                rows(ii).xMetricLabel = xSpec.label; rows(ii).yMetricLabel = ySpec.label;
                rows(ii).xValue = x(ii); rows(ii).yValue = y(ii);
                rows(ii).xThresholdPassed = xp; rows(ii).yThresholdPassed = yp;
                rows(ii).thresholdPassedAny = xp || yp; rows(ii).thresholdPassedBoth = xp && yp;
                rows(ii).pointState = NMResultsViewerReportTools.stateFromThreshold(rows(ii).thresholdPassedAny, x(ii), 'point');
                rows(ii).labelState = NMResultsViewerReportTools.stateFromThreshold(rows(ii).thresholdPassedAny, x(ii), 'label');
                rows(ii).featureKind = featureRows(ii).featureKind;
                rows(ii).tooltipTitle = rows(ii).featureName;
                rows(ii).tooltipProvenanceSummary = featureRows(ii).tooltipProvenanceSummary;
            end
        end


        function state = stateFromThreshold(passed, value, kind)
            if ~isfinite(value)
                state = 'missing';
            elseif ~passed
                if strcmp(kind,'label')
                    state = 'greyed';
                else
                    state = 'below_threshold';
                end
            else
                state = 'active';
            end
        end

        function ranks = metricRanks(vals, byAbs)
            vals = double(vals(:)); ranks = NaN(size(vals));
            good = isfinite(vals);
            if ~any(good), return; end
            if byAbs, sortVals = abs(vals(good)); else, sortVals = vals(good); end
            [~, ord] = sort(sortVals, 'descend');
            idx = find(good); idx = idx(ord);
            ranks(idx) = 1:numel(idx);
        end

        function opts = featureMetricFigureOptions(component, exportSpec, metricSpec)
            % featureMetricFigureOptions  Merge captured browser state with report figure limits.
            %
            % Syntax:
            %   opts = NMResultsViewerReportTools.featureMetricFigureOptions(component, exportSpec, metricSpec)
            %
            % Inputs:
            %   component   Scalar report component containing normalized Options and
            %               the already-filtered PlotPayload.featureRows array.
            %   exportSpec  Complete report-export options (exportSpecDefaults fields); the
            %               HTML/PDF limits apply only when the browser did not select ShowAllRows.
            %   metricSpec  Scalar metric descriptor defining labels and threshold state.
            %
            % Outputs:
            %   opts  Scalar options struct consumed by the static feature-bar,
            %         histogram, and distribution-summary renderers.
            %
            % State contract:
            %   Captured browser content choices take precedence over report defaults.
            %   ShowAllRows promotes the complete post-selection PlotPayload.featureRows
            %   array and sets MaxRows/LabelTopN to its size for both HTML and PDF. The
            %   renderer then emits one continuous, dynamically tall bar SVG rather than
            %   independent chunks with separate scales. TableRowCount remains separate.
            %
            % Errors and diagnostics:
            %   The method does not recompute, reorder, or silently truncate scientific
            %   feature rows.
            %
            % Side effects:
            %   None.
            compOptions = component.Options;
            opts = struct();
            opts.Title = metricSpec.label;
            opts.XLabel = opts.Title;
            opts.ValueField = 'displayValue';
            opts.ErrorField = 'displaySE';
            if exportSpec.PdfTarget
                opts.MaxRows = exportSpec.PdfMaxPlottedFeatures;
                opts.LabelTopN = exportSpec.PdfLabelTopN;
                opts.MinLabelFontPt = exportSpec.PdfMinFeatureLabelFontPt;
                opts.MaxSvgHeight = exportSpec.PdfMaxFeatureBarSvgHeight;
                opts.PdfTarget = true;
            else
                opts.MaxRows = exportSpec.MaxPlottedFeatures;
                opts.LabelTopN = exportSpec.LabelTopN;
                opts.MinLabelFontPt = exportSpec.MinFeatureLabelFontPt;
                opts.MaxSvgHeight = exportSpec.MaxFeatureBarSvgHeight;
            end
            opts.ShowAllRows = compOptions.ShowAllRows;
            if opts.ShowAllRows
                plottedRows = component.PlotPayload.featureRows;
                if ~isempty(plottedRows)
                    opts.MaxRows = numel(plottedRows);
                    opts.LabelTopN = numel(plottedRows);
                end
            end
            opts.TableRowCount = compOptions.TableRowCount;
            opts.HistogramBins = compOptions.HistogramBins;
            opts.PositiveColor = compOptions.PositiveColor;
            opts.NegativeColor = compOptions.NegativeColor;
            opts.MidpointColor = compOptions.MidpointColor;
            opts.SubthresholdColor = compOptions.SubthresholdColor;
            opts.BarWidth = compOptions.BarWidth;
            opts.BarEdge = compOptions.BarEdge;
            % nm2-allow: Public Report Builder component Options may explicitly supply per-metric browser display colors.
            opts.UseBrowserColors = isfield(compOptions,'PositiveColor') || isfield(compOptions,'NegativeColor') || isfield(compOptions,'SubthresholdColor');
            NMResultsViewerDisplaySemanticsTools.validateContract(metricSpec.displayContract);
            opts.DisplayContract = metricSpec.displayContract;
            opts.ThresholdLabel = metricSpec.thresholdLabel;
        end


        function html = modelFeatureInspectionFusionPanelReportHtml(fig, tableHtml, contextHtml)
            % modelFeatureInspectionFusionPanelReportHtml  Compose static fusion-panel plot/table layout.
            plotPart=''; tablePart='';
            if ~isempty(fig), plotPart=['<div class="fusionReportPlot">' fig '</div>']; end
            if ~isempty(tableHtml), tablePart=['<div class="fusionReportTable">' tableHtml '</div>']; end
            html=[contextHtml '<div class="fusionReportGrid">' plotPart tablePart '</div>'];
        end

        function html = modelFeatureInspectionFusionReportContextHtml(component, statisticLabel)
            % modelFeatureInspectionFusionReportContextHtml  Render selected source/component metadata above a fusion panel.
            metadata=component.Metadata;
            plotPayload=component.PlotPayload;
            labels=cell(1,7); values=cell(1,7); itemCount=0;
            contextLabel=metadata.featureContextLabel;
            if ~isempty(strtrim(contextLabel)), itemCount=itemCount+1; labels{itemCount}='Feature source'; values{itemCount}=contextLabel; end
            componentLabel=metadata.backprojectionComponentLabel;
            if ~isempty(strtrim(componentLabel)), itemCount=itemCount+1; labels{itemCount}='Backprojected component'; values{itemCount}=componentLabel; end
            scopeLabel=plotPayload.componentScopeLabel;
            if ~isempty(strtrim(scopeLabel)), itemCount=itemCount+1; labels{itemCount}='Component source'; values{itemCount}=scopeLabel; end
            sourceLabel=plotPayload.componentSourceLabel;
            if ~isempty(strtrim(sourceLabel)), itemCount=itemCount+1; labels{itemCount}='DR / modality source'; values{itemCount}=sourceLabel; end
            if ~isempty(strtrim(statisticLabel)), itemCount=itemCount+1; labels{itemCount}='Statistic'; values{itemCount}=statisticLabel; end
            sortLabel=plotPayload.componentSortLabel;
            if ~isempty(strtrim(sortLabel)), itemCount=itemCount+1; labels{itemCount}='Sort'; values{itemCount}=sortLabel; end
            sourceRowCount=plotPayload.componentSourceRowCount;
            topK=plotPayload.componentTopK;
            if isfinite(sourceRowCount) && isfinite(topK)
                itemCount=itemCount+1; labels{itemCount}='Components';
                if sourceRowCount>topK, values{itemCount}=sprintf('Top %d of %d',topK,sourceRowCount); else, values{itemCount}=sprintf('All %d',sourceRowCount); end
            end
            if itemCount==0, html=''; return; end
            labels=labels(1:itemCount); values=values(1:itemCount);
            items=cell(1,itemCount);
            for ii=1:numel(labels)
                items{ii}=sprintf('<span><b>%s:</b> %s</span>',NMResultsViewerReportTools.htmlEscape(labels{ii}),NMResultsViewerReportTools.htmlEscape(values{ii}));
            end
            html=['<div class="fusionReportContext">' strjoin(items,'') '</div>'];
        end

        function html = modelFeatureInspectionModalityReportTableHtml(rows, maxRows)
            % modelFeatureInspectionModalityReportTableHtml  Render only available modality-contribution columns.
            if isempty(rows), html='<div class="small">No modality-contribution rows are available.</div>'; return; end
            hasMean=NMResultsViewerReportTools.modelFeatureInspectionRowsHaveFiniteField(rows,'meanShare');
            lo=NMResultsViewerReportTools.structNumericArray(rows,'lo95'); hi=NMResultsViewerReportTools.structNumericArray(rows,'hi95');
            hasInterval=any(isfinite(lo)&isfinite(hi));
            covN=NMResultsViewerReportTools.structNumericArray(rows,'coverageN'); covT=NMResultsViewerReportTools.structNumericArray(rows,'coverageTotal');
            hasCoverage=any(isfinite(covN)&isfinite(covT));
            tmpl=struct('modalityLabel','','medianShare',NaN,'meanShare',NaN,'lo95',NaN,'hi95',NaN,'coverage','');
            projected=repmat(tmpl,1,numel(rows));
            for ii=1:numel(rows)
                projected(ii).modalityLabel=rows(ii).modalityLabel;
                projected(ii).medianShare=rows(ii).medianShare;
                projected(ii).meanShare=rows(ii).meanShare;
                projected(ii).lo95=rows(ii).lo95;
                projected(ii).hi95=rows(ii).hi95;
                if isfinite(covN(ii)) && isfinite(covT(ii)), projected(ii).coverage=sprintf('%d/%d',round(covN(ii)),round(covT(ii))); end
            end
            fields={'modalityLabel','medianShare'}; labels={'Modality','Median Lp share'};
            if hasMean, fields{end+1}='meanShare'; labels{end+1}='Mean Lp share'; end %#ok<AGROW>
            if hasInterval, fields=[fields {'lo95','hi95'}]; labels=[labels {'Lo95','Hi95'}]; end
            if hasCoverage, fields{end+1}='coverage'; labels{end+1}='Coverage'; end %#ok<AGROW>
            html=NMResultsViewerReportTools.structRowsHtml(projected,fields,labels,maxRows);
        end

        function html = modelFeatureInspectionComponentReportTableHtml(rows, metricField, metricLabel, maxRows)
            % modelFeatureInspectionComponentReportTableHtml  Render selected component statistic plus available contextual columns.
            if isempty(rows), html='<div class="small">No component-statistics rows are available.</div>'; return; end
            [loField,hiField]=NMResultsViewerReportTools.modelFeatureInspectionComponentMetricIntervalFields(metricField);
            hasInterval=false;
            if ~isempty(loField) && ~isempty(hiField)
                lo=NMResultsViewerReportTools.structNumericArray(rows,loField); hi=NMResultsViewerReportTools.structNumericArray(rows,hiField);
                hasInterval=any(isfinite(lo)&isfinite(hi));
            end
            hasPresence=NMResultsViewerReportTools.modelFeatureInspectionRowsHaveFiniteField(rows,'presencePercent');
            hasAdjusted=NMResultsViewerReportTools.modelFeatureInspectionRowsHaveFiniteField(rows,'adjustedExcessPresencePercent');
            hasReference=NMResultsViewerReportTools.modelFeatureInspectionRowsHaveFiniteField(rows,'meanReferenceCorrelation');
            hasLogP=NMResultsViewerReportTools.modelFeatureInspectionRowsHaveFiniteField(rows,'meanPermutationLogP');
            tmpl=struct('componentLabel','','componentIndex',NaN,'value',NaN,'lo95',NaN,'hi95',NaN, ...
                'presencePercent',NaN,'adjustedExcessPresencePercent',NaN,'meanReferenceCorrelation',NaN,'meanPermutationLogP',NaN,'retained','');
            projected=repmat(tmpl,1,numel(rows));
            for ii=1:numel(rows)
                projected(ii).componentLabel=rows(ii).componentLabel;
                projected(ii).componentIndex=rows(ii).componentIndex;
                projected(ii).value=rows(ii).(metricField);
                if hasInterval
                    projected(ii).lo95=rows(ii).(loField);
                    projected(ii).hi95=rows(ii).(hiField);
                end
                projected(ii).presencePercent=rows(ii).presencePercent;
                projected(ii).adjustedExcessPresencePercent=rows(ii).adjustedExcessPresencePercent;
                projected(ii).meanReferenceCorrelation=rows(ii).meanReferenceCorrelation;
                projected(ii).meanPermutationLogP=rows(ii).meanPermutationLogP;
                kept=rows(ii).kept; if kept, projected(ii).retained='Yes'; else, projected(ii).retained='No'; end
            end
            fields={'componentLabel','componentIndex','value'}; labels={'Component','#',metricLabel};
            if hasInterval, fields=[fields {'lo95','hi95'}]; labels=[labels {'Lo95','Hi95'}]; end
            if hasPresence && ~strcmp(metricField,'presencePercent'), fields{end+1}='presencePercent'; labels{end+1}='Presence %'; end %#ok<AGROW>
            if hasAdjusted && ~strcmp(metricField,'adjustedExcessPresencePercent'), fields{end+1}='adjustedExcessPresencePercent'; labels{end+1}='Adjusted excess presence %'; end %#ok<AGROW>
            if hasReference && ~strcmp(metricField,'meanReferenceCorrelation'), fields{end+1}='meanReferenceCorrelation'; labels{end+1}='Reference r'; end %#ok<AGROW>
            if hasLogP && ~strcmp(metricField,'meanPermutationLogP'), fields{end+1}='meanPermutationLogP'; labels{end+1}='-log10(P)'; end %#ok<AGROW>
            fields{end+1}='retained'; labels{end+1}='Retained';
            html=NMResultsViewerReportTools.structRowsHtml(projected,fields,labels,maxRows);
        end

        function html = modelFeatureInspectionComponentModalityReportTableHtml(rows, matrixField, matrixLabel, maxRows)
            % modelFeatureInspectionComponentModalityReportTableHtml  Render selected matrix statistic and optional coverage.
            if isempty(rows), html='<div class="small">No component-by-modality rows are available.</div>'; return; end
            covN=NMResultsViewerReportTools.structNumericArray(rows,'coverageN'); covT=NMResultsViewerReportTools.structNumericArray(rows,'coverageTotal');
            hasCoverage=any(isfinite(covN)&isfinite(covT));
            tmpl=struct('componentLabel','','componentIndex',NaN,'modalityLabel','','value',NaN,'coverage','');
            projected=repmat(tmpl,1,numel(rows));
            for ii=1:numel(rows)
                projected(ii).componentLabel=rows(ii).componentLabel;
                projected(ii).componentIndex=rows(ii).componentIndex;
                projected(ii).modalityLabel=rows(ii).modalityLabel;
                projected(ii).value=rows(ii).(matrixField);
                if isfinite(covN(ii)) && isfinite(covT(ii)), projected(ii).coverage=sprintf('%d/%d',round(covN(ii)),round(covT(ii))); end
            end
            fields={'componentLabel','componentIndex','modalityLabel','value'}; labels={'Component','#','Modality',matrixLabel};
            if hasCoverage, fields{end+1}='coverage'; labels{end+1}='Coverage'; end %#ok<AGROW>
            html=NMResultsViewerReportTools.structRowsHtml(projected,fields,labels,maxRows);
        end

        function tf = modelFeatureInspectionRowsHaveFiniteField(rows, field)
            % modelFeatureInspectionRowsHaveFiniteField  Test whether a normalized numeric field contains finite values.
            tf=false;
            if isempty(rows), return; end
            values=NMResultsViewerReportTools.structNumericArray(rows,field);
            tf=any(isfinite(values));
        end

        function [rows,metric,sourceRows,scopeLabel,sourceLabel,sortLabel,topK] = modelFeatureInspectionComponentRowsForOptions(componentAnalysis, opts, selectedContext)
            % Select the source once for the filtered rows and unfiltered sidecar.
            metric = NMResultsViewerReportTools.modelFeatureInspectionComponentMetricOption(opts);
            [sourceRows,scope,requestedSourceKey] = NMResultsViewerReportTools.modelFeatureInspectionComponentSourceRows(componentAnalysis, opts, selectedContext);
            if strcmp(scope,'fusion_report'), scopeLabel='Fusion component report'; else, scopeLabel='Selected feature source'; end
            sourceLabel = requestedSourceKey;
            rows = sourceRows;
            sortMode = 'abs_desc';
            % nm2-allow: Component Options sorting token is optional in the report recipe writer
            if isfield(opts,'SortMode') && ~isempty(opts.SortMode), sortMode=lower(strtrim(char(string(opts.SortMode)))); end
            switch sortMode
                case 'signed_asc', sortLabel='Value, ascending';
                case 'signed_desc', sortLabel='Value, descending';
                case 'feature_index', sortLabel='Component index';
                case 'abs_asc', sortLabel='Absolute value, ascending';
                otherwise, sortLabel='Absolute value, descending';
            end
            topK=20;
            % nm2-allow: Component Options TopK is an optional report recipe presentation field
            if isfield(opts,'TopK') && isnumeric(opts.TopK) && ~isempty(opts.TopK) && isfinite(double(opts.TopK(1)))
                topK=max(1,round(double(opts.TopK(1))));
            end
            if isempty(rows), return; end
            values = NMResultsViewerReportTools.modelFeatureInspectionComponentMetricValues(rows,metric);
            % The selected statistic is exact: never substitute a different one.
            finite = isfinite(values);
            rows = rows(finite); values = values(finite);
            if isempty(rows), return; end
            switch sortMode
                case 'signed_asc', [~,ord]=sort(values,'ascend');
                case 'signed_desc', [~,ord]=sort(values,'descend');
                case 'feature_index'
                    idx=[rows.componentIndex];
                    [~,ord]=sort(idx,'ascend');
                case 'abs_asc', [~,ord]=sort(abs(values),'ascend');
                otherwise, [~,ord]=sort(abs(values),'descend');
            end
            rows = rows(ord);
            rows = rows(1:min(numel(rows),topK));
            if ~isempty(rows) && ~isempty(strtrim(rows(1).drSourceLabel))
                sourceLabel = rows(1).drSourceLabel;
            end
        end

        % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
        function opts = modelFeatureInspectionFusionPanelOptions(opts, panels, panelId)
            nested = struct();
            % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
            if isfield(panels,panelId)
                nested = panels.(panelId);
            end
            opts = NMResultsViewerReportTools.mergeStructs(nested, opts);
        end

        function [rows,scope,requestedSourceKey] = modelFeatureInspectionComponentSourceRows(componentAnalysis, opts, selectedContext)
            % modelFeatureInspectionComponentSourceRows  Select one exact normalized component scope and source.
            rows = struct([]);
            modalityRows = componentAnalysis.modalityComponentTable;
            fusionRows = componentAnalysis.componentTable;
            scope = 'auto';
            % nm2-allow: Partial Report Builder fusion-panel source/scope choices enter MATLAB here; normalize before selecting fixed scientific component rows.
            if isfield(opts,'ComponentStatsScope') && ~isempty(opts.ComponentStatsScope)
                % nm2-allow: Partial Report Builder fusion-panel source/scope choices enter MATLAB here; normalize before selecting fixed scientific component rows.
                scope = lower(strtrim(char(string(opts.ComponentStatsScope))));
            end
            switch scope
                case 'selected_context'
                    rows = modalityRows;
                case 'fusion_report'
                    rows = fusionRows;
                otherwise
                    if ~isempty(modalityRows), rows = modalityRows; else, rows = fusionRows; end
            end
            requestedSourceKey = '';
            % nm2-allow: Report recipe component Options optionally contains an explicit DR source selection
            if isfield(opts,'DrSourceKey') && ~isempty(opts.DrSourceKey)
                % nm2-allow: Report recipe DR source selector conversion occurs at source selection owner
                requestedSourceKey = char(string(opts.DrSourceKey));
                if strcmp(requestedSourceKey,'all'), requestedSourceKey=''; end
            end
            if isempty(rows), return; end
            keys = cell(1,numel(rows));
            for ii=1:numel(rows), keys{ii}=NMResultsViewerReportTools.modelFeatureInspectionComponentRowSourceKey(rows(ii)); end
            uniqueKeys = unique(keys,'stable');
            sourceKey = requestedSourceKey;
            if isempty(sourceKey)
                sourceKey = NMResultsViewerReportTools.modelFeatureInspectionPreferredReportSourceKey(uniqueKeys, selectedContext);
            end
            if isempty(sourceKey)
                if numel(uniqueKeys) > 1, rows = rows([]); end
                return;
            end
            keep = strcmp(keys, sourceKey);
            if ~any(keep), rows = rows([]); else, rows = rows(keep); end
        end

        function key = modelFeatureInspectionComponentRowSourceKey(row)
            % modelFeatureInspectionComponentRowSourceKey  Return the stable source identity for one normalized component row.
            key = 'unscoped';
            contextId = row.contextId;
            if ~isempty(contextId), key=['context:' contextId]; return; end
            modalityIndex = row.drSourceModalityIndex;
            if isfinite(modalityIndex)
                key=sprintf('modality:%d',round(modalityIndex)); return;
            end
            sourceIndex = row.drSourceIndex;
            if isfinite(sourceIndex)
                key=sprintf('source:%d',round(sourceIndex));
            end
        end

        function key = modelFeatureInspectionPreferredReportSourceKey(uniqueKeys, selectedContext)
            key = '';
            if isempty(uniqueKeys), return; end
            if numel(uniqueKeys)==1, key=uniqueKeys{1}; return; end
            isCombined = NMResultsViewerReportTools.safeLogicalDefault(selectedContext,'isCombined',false);
            % nm2-allow: Serialized browser selectedFeatureContext is a partial external selection; check its optional member IDs before matching producer-owned source keys.
            contextId = char(string(NMResultsViewerReportTools.safeField(selectedContext,'contextId','')));
            if ~isCombined && ~isempty(contextId)
                candidate=['context:' contextId];
                if any(strcmp(uniqueKeys,candidate)), key=candidate; return; end
            end
            members = NMResultsViewerReportTools.safeField(selectedContext,'memberContextIds',{});
            % nm2-allow: Serialized browser selectedFeatureContext is a partial external selection; check its optional member IDs before matching producer-owned source keys.
            if ischar(members) || isstring(members), members=cellstr(members); end
            % nm2-allow: Serialized browser selectedFeatureContext is a partial external selection; check its optional member IDs before matching producer-owned source keys.
            if ~iscell(members), return; end
            for ii=1:numel(members)
                % nm2-allow: Serialized browser selectedFeatureContext is a partial external selection; check its optional member IDs before matching producer-owned source keys.
                candidate=['context:' char(string(members{ii}))];
                if any(strcmp(uniqueKeys,candidate)), key=candidate; return; end
            end
        end

        function metadata = modelFeatureInspectionReportMetadata(payload, browserStateSchemaVersion)
            % modelFeatureInspectionReportMetadata  Preserve selected feature/component context in built report components.
            metadata = struct('featureContextId','','featureContextLabel','', ...
                'backprojectionComponentId','','backprojectionComponentIndex',NaN, ...
                'backprojectionComponentLabel','','browserStateSchemaVersion',NaN);
            metadata.featureContextId = payload.selectedFeatureContextId;
            metadata.featureContextLabel = payload.selectedFeatureContext.selectionLabel;
            metadata.backprojectionComponentId = payload.selectedBackprojectionComponentId;
            metadata.backprojectionComponentIndex = payload.selectedBackprojectionComponentIndex;
            metadata.backprojectionComponentLabel = payload.selectedBackprojectionComponentLabel;
            metadata.browserStateSchemaVersion = browserStateSchemaVersion;
        end

        function rows = modelFeatureInspectionSortRows(rows, field, direction)
            % modelFeatureInspectionSortRows  Sort normalized rows by one finite scalar field.
            if isempty(rows), return; end
            values=NMResultsViewerReportTools.structNumericArray(rows,field);
            missing=~isfinite(values);
            if strcmpi(direction,'ascend'), values(missing)=Inf; else, values(missing)=-Inf; end
            [~,ord]=sort(values,direction); rows=rows(ord);
        end

        function values = modelFeatureInspectionComponentMetricValues(rows,field)
            % modelFeatureInspectionComponentMetricValues  Read one normalized scalar component field exactly.
            values=NaN(1,numel(rows));
            for ii=1:numel(rows)
                values(ii)=rows(ii).(field);
            end
        end

        function field = modelFeatureInspectionComponentMetricOption(opts)
            % modelFeatureInspectionComponentMetricOption  Validate the component statistic field requested by browser state.
            field = 'medianL2Share';
            % nm2-allow: Public component-panel metric choice is optional external request state; validate against the known component statistic catalogue.
            if ~isfield(opts,'ComponentMetric') || isempty(opts.ComponentMetric), return; end
            % nm2-allow: Public component-panel metric choice is optional external request state; validate against the known component statistic catalogue.
            candidate = char(string(opts.ComponentMetric));
            allowed = {'medianL2Share','meanL2Share','adjustedExcessPresencePercent','presencePercent','observedExpectedPresenceRatio','selectionRatio','meanReferenceCorrelation','meanPermutationLogP'};
            if any(strcmp(candidate,allowed)), field=candidate; end
        end

        function [loField,hiField] = modelFeatureInspectionComponentMetricIntervalFields(field)
            % modelFeatureInspectionComponentMetricIntervalFields  Map normalized component statistics to their 95% interval fields.
            switch field
                case {'medianL2Share','meanL2Share'}
                    loField='l2ShareLo95'; hiField='l2ShareHi95';
                case 'meanReferenceCorrelation'
                    loField='referenceCorrelationLo95'; hiField='referenceCorrelationHi95';
                case 'meanPermutationLogP'
                    loField='permutationLogPLo95'; hiField='permutationLogPHi95';
                otherwise
                    loField=''; hiField='';
            end
        end

        function label = modelFeatureInspectionComponentMetricLabel(field)
            % modelFeatureInspectionComponentMetricLabel  Return a stable scientific label for a normalized component statistic.
            switch field
                case 'medianL2Share', label='Median Lp share';
                case 'meanL2Share', label='Mean Lp share';
                case 'adjustedExcessPresencePercent', label='Propensity-adjusted excess presence [%]';
                case 'presencePercent', label='Presence across resamples [%]';
                case 'observedExpectedPresenceRatio', label='Observed / expected presence';
                case 'selectionRatio', label='Selection ratio';
                case 'meanReferenceCorrelation', label='Reference correlation';
                case 'meanPermutationLogP', label='Permutation -log10(P)';
                otherwise, label='Component statistic';
            end
        end

        function field = modelFeatureInspectionMatrixStatisticOption(opts, panels)
            % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
            opts = NMResultsViewerReportTools.modelFeatureInspectionFusionPanelOptions(opts, panels, 'component_modality_matrix');
            field = 'medianShare';
            % nm2-allow: Public component-by-modality panel statistic is optional external request state; admit only the documented meanShare choice.
            if isfield(opts,'MatrixStatistic') && strcmp(char(string(opts.MatrixStatistic)),'meanShare')
                field = 'meanShare';
            end
        end

        function relationPayload = attachRelationDisplayContract(relationPayload, opts, viewKind)
            if ~relationPayload.ok || ~relationPayload.view.available
                return;
            end
            view = relationPayload.view;
            values = NMResultsViewerReportTools.numericMatrixFromPayloadValues(view.values);
            metricSpec = struct('valuePolarity',view.primaryValuePolarity, ...
                'thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN);
            rangeMode = 'full_data_range';
            if strcmp(metricSpec.valuePolarity,'signed'), rangeMode = 'symmetric_absolute'; end
            displaySpec = struct('DisplayRangeMode',rangeMode,'Opacity',1, ...
                'NegativeColor',opts.NegativeColor, ...
                'MidpointColor',opts.MidpointColor, ...
                'PositiveColor',opts.PositiveColor);
            identity = struct('pathway','feature_relation_report', ...
                'view',viewKind, ...
                'matrixId',view.matrixId, ...
                'contextId',view.contextId, ...
                'measureId',view.primaryLayerId);
            view.displayContract = NMResultsViewerDisplaySemanticsTools.resolveContract( ...
                values,metricSpec,displaySpec,identity);
            graph = view.graph;
            if graph.available
                graph.displayContract = view.displayContract;
                view.graph = graph;
            end
            relationPayload.view = view;
        end

        function contract = requiredRelationDisplayContract(view)
            contract = view.displayContract;
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
        end

        function [opts, relationState, panelVisible, capturedRobustness] = modelFeatureRelationOptionsFromComponentOptions(compOptions, panels, panelType)
            % The browser supplies canonical relation controls; the relation service
            % alone validates/normalizes scientific selection and graph parameters.
            if strcmp(panelType,'relationGraph'), panelId='feature_relation_graph'; else, panelId='correlation_matrix'; end
            panelVisible=compOptions.PanelVisible;
            relationState=compOptions.RelationState;
            opts=struct('PanelId',panelId,'PanelType',panelType, ...
                'RelationState',relationState,'MidpointColor','#ffffff');
            capturedRobustness=struct();
            if ~panelVisible,return;end
            opts.GraphLabelMode=compOptions.GraphLabelMode;
            opts.GraphMaxLabels=compOptions.GraphMaxLabels;
            opts.SelectedRelationPatternId=compOptions.SelectedRelationPatternId;
            opts.RelationPanelsSynchronized=compOptions.RelationPanelsSynchronized;
            opts.PositiveColor=compOptions.PositiveColor;
            opts.NegativeColor=compOptions.NegativeColor;
            opts.SubthresholdColor=compOptions.SubthresholdColor;
            opts.MatrixReportIncluded=compOptions.MatrixReportIncluded;
            viewState = NMResultsViewerReportTools.safeField(compOptions,'BrowserFeatureInspectionViewState',struct());
            opts.BrowserFeatureInspectionViewState = viewState;
            raw = struct();
            % nm2-allow: keyed lookup in the captured panel map; snapshots exist only for panels in panelOrder (serializeFeatureInspectionViewState).
            if isfield(panels,panelId), raw=panels.(panelId); end
            capturedRobustness = NMResultsViewerReportTools.safeField(raw,'graphRobustnessResult',struct());
        end

        function result = validCapturedGraphRobustness(captured, relationPayload)
            % validCapturedGraphRobustness  Return a captured robustness result only when it describes the exported graph.  nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            %
            % Syntax:
            %   result = NMResultsViewerReportTools.validCapturedGraphRobustness(captured,relationPayload)
            %
            % Inputs:
            %   captured         Browser-cached robustness contract captured with panel state.  nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            %   relationPayload  Fresh canonical relation payload reconstructed for export.
            %
            % Outputs:
            %   result  The captured result when graph identity and selected fixed density
            %           match; otherwise a disabled robustness template.  nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            %
            % Scientific contract:
            %   Robustness is a fixed-density sparsification-sensitivity result. It is  nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            %   reportable only when matrix identity, selected layer, stable feature
            %   universe and selected density match the freshly materialized graph.
            %
            % Invariants and mutability:
            %   Cached browser results are never recomputed, repaired, or rebound to another
            %   graph. Inputs are read-only.
            %
            % Errors and diagnostics:
            %   Identity mismatches return a disabled template rather than a stale figure.
            %
            % Side effects:
            %   None.
            result = NMResultsViewerFeatureGraphTools.robustnessTemplate();
            % nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            if ~isstruct(captured) || isempty(captured) || ...
                    ~NMResultsViewerReportTools.safeLogicalDefault(captured,'available',false) || ...
                    ~NMResultsViewerReportTools.safeLogicalDefault(captured,'enabled',false), return; end
            graph = relationPayload.view.graph;
            if ~strcmp(graph.edgeSelectionMode,'fixed_density'), return; end
            selectedDensity = NMResultsViewerReportTools.safeField(captured,'selectedDensity',NaN);
            targetDensity = graph.targetDensity;
            % nm2-allow: Browser captured graph robustness selectedDensity is an external session-cache input; validate its numeric scalar contract.
            if ~isnumeric(selectedDensity) || ~isscalar(selectedDensity) || ~isreal(selectedDensity) || ~isfinite(selectedDensity) || ...
                    ~isfinite(targetDensity) || abs(selectedDensity-targetDensity) > 1e-9, return; end
            % nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            capturedMatrix = char(string(NMResultsViewerReportTools.safeField(captured,'matrixId','')));
            graphMatrix = graph.matrixId;
            if ~strcmp(capturedMatrix,graphMatrix), return; end
            % nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            capturedLayer = char(string(NMResultsViewerReportTools.safeField(captured,'sourceLayerId','')));
            graphLayer = graph.sourceLayerId;
            if ~strcmp(capturedLayer,graphLayer), return; end
            capturedFeatures = double(NMResultsViewerReportTools.safeField(captured,'selectedFeatureIndices',[]));
            graphFeatures = graph.selectedFeatureIndices;
            if ~isequal(capturedFeatures(:),graphFeatures(:)), return; end
            % nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            capturedContext = char(string(NMResultsViewerReportTools.safeField(captured,'contextId','')));
            graphContext = graph.contextId;
            if ~strcmp(capturedContext,graphContext), return; end
            % nm2-allow: Browser session-cached robustness is an untrusted external graph product; reject missing or incompatible matrix, layer, context, axis and cache identities.
            capturedCacheIdentity = char(string(NMResultsViewerReportTools.safeField(captured,'cacheIdentity','')));
            if isempty(capturedCacheIdentity), return; end
            request = NMResultsViewerFeatureGraphTools.graphRequestTemplate();
            request.sourceLayerId = graphLayer;
            expectedCacheIdentity = NMResultsViewerFeatureGraphTools.robustnessIdentity(captured,request);
            if ~strcmp(capturedCacheIdentity,expectedCacheIdentity), return; end
            result = captured;
        end

        function rows = modelFeatureRelationDetailsRows(relationPayload, opts, capturedState, panelKind)
            % modelFeatureRelationDetailsRows  Build human-readable Report Builder details for captured relation state.
            %
            % Syntax:
            %   rows = NMResultsViewerReportTools.modelFeatureRelationDetailsRows(relationPayload,opts,capturedState,panelKind)
            %
            % Inputs:
            %   relationPayload  Fresh canonical relation payload.
            %   opts             Relation panel/report options (modelFeatureRelationOptionsFromComponentOptions).
            %   capturedState    Completed captured view state (featureInspectionViewState).
            %   panelKind        matrix or graph.
            %
            % Outputs:
            %   rows  Fixed-schema setting/value rows describing visible panels, source,
            %         layer, filtering, ordering, clustering, pruning, patterns, pagination,
            %         label presentation, synchronization, and robustness validity.  nm2-allow: Browser visible-panel catalogue is external presentation state; optional panel labels require input checks before report text.
            %
            % Scientific contract:
            %   Rows explicitly record panel visibility and all content-defining user choices.
            %   Internal field names are not exposed in the report body.
            %
            % Invariants and mutability:
            %   Details describe the same relationPayload that supplies figures and tables.
            %   Inputs are not mutated.
            %
            % Errors and diagnostics:
            %   Missing optional settings are represented by explicit Off/None text.
            %
            % Side effects:
            %   None.
            view = relationPayload.view;
            graph = view.graph;
            visibleIds = capturedState.visiblePanelIds;
            visibleLabels = cell(size(visibleIds));
            statePanels = capturedState.panels;
            for vv=1:numel(visibleIds)
                visibleLabels{vv}=visibleIds{vv};
                % nm2-allow: visible panel ids can name panels without a captured snapshot (serializeFeatureInspectionViewState).
                if isfield(statePanels,visibleIds{vv})
                    % nm2-allow: Browser visible-panel catalogue is external presentation state; optional panel labels require input checks before report text.
                    visibleLabels{vv}=char(string(NMResultsViewerReportTools.safeField(statePanels.(visibleIds{vv}),'label',visibleIds{vv})));
                end
            end
            visibleText = strjoin(visibleLabels, ', '); if isempty(visibleText), visibleText='None'; end
            mode = graph.edgeSelectionMode;
            switch mode
                case 'legacy_topk_union', modeLabel='Strongest-edge union';
                case 'fixed_density', modeLabel='Fixed density';
                case 'absolute_threshold', modeLabel='Absolute primary threshold';
                otherwise, modeLabel=mode;
            end
            tmpl=struct('setting','','value',''); rows=repmat(tmpl,1,0);
            add=@(name,value)struct('setting',name,'value',value);
            rows(end+1)=add('Visible feature panels',visibleText); %#ok<AGROW>
            if strcmp(panelKind,'graph'), exportedPanel='Feature-relation graph'; else, exportedPanel='Feature-correlation matrix'; end
            rows(end+1)=add('Exported panel',exportedPanel); %#ok<AGROW>
            sourceScope=view.sourceScope;
            % The header Feature source is the sole user-facing source selector.
            % sourceScope remains an internal replay assertion and is not rendered as
            % a second report setting.
            rows(end+1)=add('Feature source',view.modalityLabel); %#ok<AGROW>
            relationId=view.relationId;
            if ~isempty(relationId), rows(end+1)=add('Persisted relation identity',relationId); end %#ok<AGROW>
            memberCounts=view.memberFeatureCounts;
            if strcmp(sourceScope,'combined') && ~isempty(memberCounts)
                countText=strjoin(arrayfun(@(x)sprintf('%d',round(double(x))),memberCounts(:)','UniformOutput',false),' + ');
                rows(end+1)=add('Combined feature blocks',sprintf('%d modalities; %s features',numel(memberCounts),countText)); %#ok<AGROW>
            end
            rows(end+1)=add('Relation layer',view.primaryLayerLabel); %#ok<AGROW>
            rows(end+1)=add('Retained feature universe',sprintf('%d of %d features',view.filteredFeatureCount,view.allFeatureCount)); %#ok<AGROW>
            rows(end+1)=add('Displayed feature page',sprintf('%d of %d; %d feature(s)',view.currentPage,view.pageCount,view.displayedFeatureCount)); %#ok<AGROW>
            rows(end+1)=add('Feature ordering',view.effectiveOrderingMode); %#ok<AGROW>
            filterMode=view.secondaryThresholdMode;
            if strcmp(filterMode,'none')
                rows(end+1)=add('Secondary feature filter','Off'); %#ok<AGROW>
            else
                filterLabel=view.secondaryFeatureMetricLabel;
                rows(end+1)=add('Secondary feature filter',sprintf('%s; %s',filterLabel,filterMode)); %#ok<AGROW>
            end
            clusteringApplied=view.clusteringApplied;
            if clusteringApplied
                rows(end+1)=add('Hierarchical ordering',view.clusteringLabel); %#ok<AGROW>
                extractionMode=view.clusterExtractionMode;
                if ~strcmp(extractionMode,'none')
                    if strcmp(extractionMode,'fixed_count')
                        extractionText=sprintf('Fixed count: %d requested, %d resolved',round(view.clusterCountRequested),round(view.clusterCountResolved));
                    else
                        extractionText=sprintf('Cut height %.3g; %d cluster(s) resolved',view.clusterCutHeight,round(view.clusterCountResolved));
                    end
                    rows(end+1)=add('Feature-cluster extraction',extractionText); %#ok<AGROW>
                end
            else
                rows(end+1)=add('Hierarchical ordering','Off'); %#ok<AGROW>
            end
            patternCount=round(graph.relationPatternClusterCount);
            graphDetailsRequired=strcmp(panelKind,'graph')||patternCount>0;
            if graphDetailsRequired
                rows(end+1)=add('Graph construction',modeLabel); %#ok<AGROW>
                if strcmp(mode,'legacy_topk_union')
                    rows(end+1)=add('Strongest-edge union settings',sprintf('%d local candidate edge(s) per feature; %d global candidate edge(s)',graph.kPerNode,graph.maxGlobal)); %#ok<AGROW>
                elseif strcmp(mode,'fixed_density')
                    rows(end+1)=add('Requested / realized density',sprintf('%.1f%% / %.1f%%',100*graph.targetDensity,100*graph.realizedDensity)); %#ok<AGROW>
                elseif strcmp(mode,'absolute_threshold')
                    rows(end+1)=add('Absolute layer cutoff',sprintf('%.4g',graph.absoluteThreshold)); %#ok<AGROW>
                end
                rows(end+1)=add('Relation patterns',sprintf('%d valid pattern(s); minimum %d edges',patternCount,graph.relationPatternMinEdges)); %#ok<AGROW>
                selectedPattern=round(opts.SelectedRelationPatternId);
                if selectedPattern>0, selectedPatternText=sprintf('Pattern %d',selectedPattern); else, selectedPatternText='All relation patterns'; end
                rows(end+1)=add('Active browser pattern',selectedPatternText); %#ok<AGROW>
            end
            if strcmp(panelKind,'graph')
                rows(end+1)=add('Node-label display',sprintf('%s; maximum %d label(s)',opts.GraphLabelMode,round(opts.GraphMaxLabels))); %#ok<AGROW>
                if opts.GraphRobustnessValid
                    rows(end+1)=add('Robust graph setting',sprintf('Valid for exported graph; selected density %.1f%%',100*opts.GraphRobustnessSelectedDensity)); %#ok<AGROW>
                else
                    rows(end+1)=add('Robust graph setting','Not displayed: no identity-valid result for the exported graph'); %#ok<AGROW>
                end
            end
            bothRelationPanelsVisible=any(strcmp(visibleIds,'correlation_matrix'))&&any(strcmp(visibleIds,'feature_relation_graph'));
            if bothRelationPanelsVisible
                if opts.RelationPanelsSynchronized, syncText='On'; else, syncText='Off'; end
                rows(end+1)=add('Matrix / graph synchronization',syncText); %#ok<AGROW>
            end
        end

        function rows = modelFeatureGraphSummaryRows(relationPayload)
            % modelFeatureGraphSummaryRows  Return one fixed-schema graph-level statistics row.
            %
            % Syntax:
            %   rows = NMResultsViewerReportTools.modelFeatureGraphSummaryRows(relationPayload)
            %
            % Inputs:
            %   relationPayload  Canonical relation payload containing the full pruned graph.
            %
            % Outputs:
            %   rows  Scalar fixed-schema summary of topology, density, components, isolated
            %         nodes, statistics availability, and weighted-statistics affinity.
            %
            % Scientific contract:
            %   Values describe the full canonical pruned graph, not the paginated SVG subset.
            %
            % Invariants and mutability:
            %   No statistics are recomputed and no input is mutated.
            %
            % Errors and diagnostics:
            %   Missing fields use explicit schema defaults.
            %
            % Side effects:
            %   None.
            view=relationPayload.view;
            graph=view.graph;
            rows=struct('nodeCount',graph.nodeCount, ...
                'edgeCount',graph.edgeCount, ...
                'possibleEdgeCount',graph.possibleEdgeCount, ...
                'density',graph.graphDensity, ...
                'connectedComponents',graph.connectedComponentCount, ...
                'isolatedNodes',graph.isolatedNodeCount, ...
                'statisticsAvailable',graph.graphStatisticsAvailable, ...
                'statisticsAffinity',graph.graphStatisticsAffinity);
        end

        function rows = modelFeatureGraphNodeRows(relationPayload)
            % modelFeatureGraphNodeRows  Return canonical full-graph node statistics without page truncation.
            %
            % Syntax:
            %   rows = NMResultsViewerReportTools.modelFeatureGraphNodeRows(relationPayload)
            %
            % Inputs:
            %   relationPayload  Canonical relation payload.
            %
            % Outputs:
            %   rows  Fixed-schema node rows with stable identity, topology, weighted
            %         statistics, components, layout, and pattern membership.
            %
            % Scientific contract:
            %   Rows describe the full graph represented by the report and are not replaced
            %   by page-local hover degree or transient browser highlights.
            %
            % Invariants and mutability:
            %   Stable feature IDs/indices are preserved; inputs are not mutated.
            %
            % Errors and diagnostics:
            %   Returns an empty node-template array when unavailable.
            %
            % Side effects:
            %   None.
            graph=relationPayload.view.graph;
            rows=graph.nodeRows;
        end

        function rows = modelFeatureRelationPatternRows(relationPayload)
            % modelFeatureRelationPatternRows  Return all valid pattern summaries from the exported graph identity.
            %
            % Syntax:
            %   rows = NMResultsViewerReportTools.modelFeatureRelationPatternRows(relationPayload)
            %
            % Inputs:
            %   relationPayload  Canonical relation payload.
            %
            % Outputs:
            %   rows  Pattern summaries satisfying the graph's minimum-edge contract.
            %
            % Scientific contract:
            %   All currently valid patterns are retained regardless of the browser's focused
            %   pattern. Pattern IDs remain local to the exact exported graph identity.
            %
            % Invariants and mutability:
            %   Pattern membership is not recomputed by Report Builder.
            %
            % Errors and diagnostics:
            %   Returns an empty fixed-schema array when no valid pattern exists.
            %
            % Side effects:
            %   None.
            graph=relationPayload.view.graph;
            rows=graph.relationClusterSummaries;
            if isempty(rows), return; end
            keep=arrayfun(@(r)r.relationClusterId>0 && r.edgeCount>=graph.relationPatternMinEdges,rows);
            rows=rows(keep);
        end

        function html = modelFeatureRelationMatrixReportHtml(component, relationPayload, maxRows)
            % modelFeatureRelationMatrixReportHtml  Render the visible matrix panel from captured browser state.
            %
            % Syntax:
            %   html = NMResultsViewerReportTools.modelFeatureRelationMatrixReportHtml(component,relationPayload,maxRows)
            %
            % Inputs:
            %   component        Built Report Builder component with normalized Details rows.
            %   relationPayload  Fresh canonical relation view reconstructed from captured state.
            %   maxRows          Maximum table rows for compact report tables.
            %
            % Outputs:
            %   html  Details followed by the exact displayed matrix page. When multiple
            %         relation patterns are present, a discrete pattern legend is rendered
            %         outside the matrix while the numerical value colour bar remains separate.
            %
            % Scientific contract:
            %   This method renders only a matrix component that passed the authoritative
            %   panel-visibility gate. Matrix values, ordering, pagination, filtering,
            %   clustering, and pattern membership are replayed from browser state. When the graph
            %   component is selected, its full pruned graph follows the matrix without an
            %   intervening graph-specific table.
            %
            % Invariants and mutability:
            %   No graph, matrix, report, or browser state is modified.
            %
            % Errors and diagnostics:
            %   Returns an empty fragment if the canonical matrix view is unavailable.
            %
            % Side effects:
            %   None.
            view=relationPayload.view;
            if ~view.available,html='';return;end
            details=component.Tables.featureRelationDetails;
            detailHtml=NMResultsViewerReportTools.structRowsHtml(details,{'setting','value'},{'Setting','Captured user choice'},max(20,maxRows));
            sourceScope=view.sourceScope;
            sourceLabel=view.modalityLabel;
            figureTitle='Feature-correlation matrix';
            if strcmp(sourceScope,'combined') && ~isempty(sourceLabel), figureTitle=[figureTitle ' — ' sourceLabel]; end
            displayContract=NMResultsViewerReportTools.requiredRelationDisplayContract(view);
            fig=NMResultsViewerReportFigureTools.featureInspectionRelationMatrixSvg(relationPayload, ...
                'Title',figureTitle,'ShowPatternLegend',false,'DisplayContract',displayContract);
            html=['<div class="featureRelationReport relationMatrixReport" data-relation-source-scope="' ...
                sourceScope '"><div class="relationReportDetails"><h3>Feature-relation details</h3>' detailHtml '</div>' fig '</div>'];
        end

        function html = modelFeatureGraphReportHtml(component, relationPayload, robustness, maxRows)
            % modelFeatureGraphReportHtml  Render the visible graph panel below the matrix component.
            %
            % Syntax:
            %   html = NMResultsViewerReportTools.modelFeatureGraphReportHtml(component,relationPayload,robustness,maxRows)  nm2-allow: Public static-report component Options control label presentation; normalize at the renderer input boundary.
            %
            % Inputs:
            %   component        Built graph component with captured browser/report options.
            %   relationPayload  Fresh canonical graph relation payload reconstructed from state.
            %   robustness       Optional identity-valid fixed-density robustness result.  nm2-allow: Public static-report component Options control label presentation; normalize at the renderer input boundary.
            %   maxRows          Maximum number of rows in compact report tables.
            %
            % Outputs:
            %   html  Captured graph details, full canonical pruned graph, all valid relation
            %         patterns in a deterministic gallery only when at least two patterns exist, an identity-valid robustness  nm2-allow: Public static-report component Options control label presentation; normalize at the renderer input boundary.
            %         diagnostic, graph-level statistics, and ranked node statistics.
            %
            % Scientific contract:
            %   All pattern tiles use the full graph's backend layout coordinates. PDF layout
            %   is exactly three tiles per row; HTML layout is responsive. A stale robustness  nm2-allow: Public static-report component Options control label presentation; normalize at the renderer input boundary.
            %   result is never rendered. Centrality describes the exported graph topology and
            %   is not predictive feature importance.
            %
            % Invariants and mutability:
            %   The method is read-only and does not recompute topology or pattern membership.
            %
            % Errors and diagnostics:
            %   Returns an empty fragment if canonical graph topology is unavailable.
            %
            % Side effects:
            %   None.
            view=relationPayload.view;
            graph=view.graph;
            if ~graph.available,html='';return;end
            opts=component.Options;
            % nm2-allow: Public static-report component Options control label presentation; normalize at the renderer input boundary.
            labelMode=opts.GraphLabelMode;
            maxLabels=opts.GraphMaxLabels;
            % Static-report policy: unless the user explicitly hid labels,
            % attempt every node label and suppress only labels that cannot be placed
            % without overlap after font-size reduction.
            if strcmp(labelMode,'none'),reportLabelMode='none';else,reportLabelMode='all_nonoverlapping';end
            details=component.Tables.featureRelationDetails;
            detailTable=NMResultsViewerReportTools.structRowsHtml(details,{'setting','value'},{'Setting','Captured user choice'},max(20,maxRows));
            if opts.MatrixReportIncluded
                detailHtml=''; % The selected matrix component already placed shared relation details immediately above the matrix.
            else
                detailHtml=['<div class="relationReportDetails"><h3>Feature-relation details</h3>' detailTable '</div>'];
            end
            sourceScope=view.sourceScope;
            sourceLabel=view.modalityLabel;
            graphTitle='Full pruned feature-relation graph';
            if strcmp(sourceScope,'combined') && ~isempty(sourceLabel), graphTitle=[graphTitle ' — ' sourceLabel]; end
            displayContract=NMResultsViewerReportTools.requiredRelationDisplayContract(view);
            NMResultsViewerReportTools.reportProgress('Report export', ...
                sprintf('Rendering feature-relation graph (%d nodes, %d edges).', ...
                numel(graph.nodeRows),numel(graph.edgeRows)),94,'render_graph');
            fullGraph=NMResultsViewerReportFigureTools.featureInspectionCanonicalGraphSvg(graph, ...
                'Title',graphTitle,'PatternId',0,'Compact',false,'LabelMode',reportLabelMode, ...
                'MaxLabels',maxLabels,'ShowVisibleTitle',true,'ShowSummary',true,'ContextGraph',false, ...
                'AllowLabelSuppression',true,'DisplayContract',displayContract);
            gallery=NMResultsViewerReportTools.modelFeatureRelationPatternGalleryHtml(graph,displayContract);
            robustHtml='';
            if robustness.available && robustness.enabled
                robustHtml=['<div class="relationRobustnessReport"><h3>Graph sparsification robustness</h3>' ...
                    NMResultsViewerReportFigureTools.featureInspectionRobustnessSvg(robustness,'Title','Robust graph setting identified') ...
                    '<p class="small">This diagnostic evaluates sensitivity to fixed-density graph sparsification only. It does not establish sampling reliability, statistical significance, causality, cross-validation stability, or predictive importance.</p></div>'];
            end
            summary=component.Tables.graphSummary;
            summaryHtml=NMResultsViewerReportTools.structRowsHtml(summary,{'nodeCount','edgeCount','possibleEdgeCount','density','connectedComponents','isolatedNodes','statisticsAffinity'}, ...
                {'Nodes','Edges','Possible edges','Density','Connected components','Isolated nodes','Weighted-statistics affinity'},maxRows);
            patterns=component.Tables.relationPatterns;
            patternsHtml='';
            if ~isempty(patterns)
                patternsHtml=['<h3>Relation-pattern statistics</h3>' NMResultsViewerReportTools.structRowsHtml(patterns, ...
                    {'relationClusterId','edgeCount','nodeCount','positiveEdgeCount','negativeEdgeCount','meanAbsoluteWeight','totalAbsoluteWeight'}, ...
                    {'Pattern','Edges','Nodes','Positive edges','Negative edges','Mean absolute layer value','Total absolute layer value'},maxRows)];
            end
            nodes=component.Tables.nodeStatistics;
            nodeHtml=NMResultsViewerReportTools.modelFeatureGraphNodeStatisticsTableHtml(nodes,graph);
            disclaimer='<p class="small graphStatisticsDisclaimer">Graph centrality and strength summarize topology in the exported pruned graph. They are not measures of predictive feature importance.</p>';
            html=['<div class="featureRelationReport relationGraphReport" data-relation-source-scope="' ...
                sourceScope '">' detailHtml ...
                '<div class="fullPrunedGraphReport"><h3>Full pruned graph</h3>' fullGraph '</div>' gallery robustHtml ...
                '<div class="relationGraphStatistics"><h3>Graph-level statistics</h3>' summaryHtml patternsHtml '<h3>Node statistics</h3>' nodeHtml disclaimer '</div></div>'];
        end

        function html = modelFeatureRelationPatternGalleryHtml(graph,displayContract)
            % modelFeatureRelationPatternGalleryHtml  Render every valid relation pattern with shared node coordinates.
            %
            % Syntax:
            %   html = NMResultsViewerReportTools.modelFeatureRelationPatternGalleryHtml(graph,displayContract)
            %
            % Inputs:
            %   graph            Canonical full pruned graph contract.
            %   displayContract  Canonical selected-layer display contract.
            %
            % Outputs:
            %   html  Comparative gallery containing one deterministic tile per pattern when at least two valid patterns exist.
            %
            % Scientific contract:
            %   Gallery membership is derived from the exact exported graph identity, not the
            %   currently focused browser pattern. Every tile repeats the complete pruned graph
            %   in faint context colours, emphasizes only the selected pattern, and names all
            %   participating nodes. Node coordinates are inherited from the full graph.
            %
            % Invariants and mutability:
            %   Pattern IDs, edge membership, node coordinates, and counts are read-only.
            %
            % Errors and diagnostics:
            %   Returns an empty fragment when fewer than two valid relation patterns exist.
            %
            % Layout contract:
            %   Common CSS uses a responsive HTML grid and an exact three-column PDF grid.
            %
            % Side effects:
            %   None.
            html='';
            summaries=graph.relationClusterSummaries;
            if ~isstruct(summaries)||isempty(summaries),return;end
            minEdges=graph.relationPatternMinEdges;
            keep=arrayfun(@(r)r.relationClusterId>0&&r.edgeCount>=minEdges,summaries);
            summaries=summaries(keep);if isempty(summaries),return;end
            % A gallery is comparative by definition. Preserve the exact
            % user-constructed graph and pattern membership, but do not duplicate the
            % full graph in a one-tile gallery when only one valid pattern exists.
            if numel(summaries) < 2, return; end
            [~,ord]=sort(arrayfun(@(r)r.relationClusterId,summaries));summaries=summaries(ord);
            tiles=cell(1,numel(summaries));
            contextMarkup='';
            edgeColors={};
            for ii=1:numel(summaries)
                pid=round(summaries(ii).relationClusterId);
                eCount=round(summaries(ii).edgeCount);
                nCount=round(summaries(ii).nodeCount);
                NMResultsViewerReportTools.reportProgress('Report export', ...
                    sprintf('Rendering feature-relation pattern %d/%d (%d context edges).', ...
                    ii,numel(summaries),numel(graph.edgeRows)),94,'render_pattern');
                [fig,contextMarkup,edgeColors]=NMResultsViewerReportFigureTools.featureInspectionCanonicalGraphSvg(graph, ...
                    'Title',sprintf('Pattern %d',pid),'PatternId',pid,'Compact',true, ...
                    'LabelMode','all_nonoverlapping','MaxLabels',nCount,'ShowVisibleTitle',false, ...
                    'ShowSummary',false,'ContextGraph',true,'AllowLabelSuppression',false, ...
                    'DisplayContract',displayContract,'ContextMarkup',contextMarkup,'EdgeColors',edgeColors);
                tiles{ii}=sprintf('<article class="relationPatternTile" data-relation-pattern-id="%d"><header><strong>Pattern %d</strong><span>%d edges · %d nodes</span></header>%s</article>',pid,pid,eCount,nCount,fig);
            end
            html=['<div class="relationPatternGallerySection"><h3>Relation-pattern gallery</h3><div class="relationPatternGallery">' strjoin(tiles,'') '</div></div>'];
        end

        function summary = modelFeatureInspectionPayloadSummary(payload)
            % modelFeatureInspectionPayloadSummary  Build compact component context metadata.
            summary = struct('kind',payload.kind, ...
                'schemaVersion',payload.schemaVersion, ...
                'ok',payload.ok, ...
                'message',payload.message, ...
                'analysisIndex',payload.analysisIndex, ...
                'targetIndex',payload.targetIndex, ...
                'classifierIndex',payload.classifierIndex, ...
                'selectedMeasureId',payload.selectedMeasureId, ...
                'selectedFeatureContextId',payload.selectedFeatureContextId, ...
                'selectedBackprojectionComponentId',payload.selectedBackprojectionComponentId, ...
                'selectedBackprojectionComponentIndex',payload.selectedBackprojectionComponentIndex, ...
                'selectedBackprojectionComponentLabel',payload.selectedBackprojectionComponentLabel, ...
                'backprojectionComponentCount',numel(payload.backprojectionComponents), ...
                'contextCount',numel(payload.contexts), ...
                'measureCount',numel(payload.measures), ...
                'featureRowCount',numel(payload.featureTable));
        end

        function n = countFiniteRowsForField(rows, fieldName)
            % countFiniteRowsForField  Count rows containing one finite scalar-like numeric field.
            n = 0;
            if ~isstruct(rows) || isempty(rows), return; end
            for ii=1:numel(rows)
                if isfield(rows(ii), fieldName)
                    val = rows(ii).(fieldName);
                    if isnumeric(val) && ~isempty(val) && any(isfinite(double(val(:))))
                        n = n + 1;
                    end
                end
            end
        end

        function n = minFeatureMetricHistogramCount()
            % minFeatureMetricHistogramCount  Minimum finite feature count for feature histograms.
            n = 50;
        end

        function reason = featureMetricHistogramMissingReason(finiteMetricN)
            % featureMetricHistogramMissingReason  Explain why a feature-metric histogram is disabled.
            minN = NMResultsViewerReportTools.minFeatureMetricHistogramCount();
            finiteMetricN = max(0, double(finiteMetricN));
            if finiteMetricN == 0
                reason = 'No finite values are available for the selected feature metric distribution.';
            else
                reason = sprintf('Feature-metric histograms are available only when at least %d finite feature values exist; the selected metric has %d.', minN, finiteMetricN);
            end
        end

        function tf = structArrayHasRows(rows)
            % structArrayHasRows  Test whether a struct array is non-empty.
            tf = isstruct(rows) && ~isempty(rows);
        end

        function tf = safeLogicalDefault(s, fieldName, default)
            % safeLogicalDefault  Read one logical scalar field with default.
            if nargin < 3, default = false; end
            tf = logical(default);
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                tf = logical(s.(fieldName));
            end
        end

        function status = statusForRows(rows)
            % statusForRows  Return ok/unavailable for non-empty row payloads.
            if isstruct(rows) && ~isempty(rows)
                status = 'ok';
            else
                status = 'unavailable';
            end
        end

        function rows = modelFeatureInspectionRowsForFields(inRows, fields)
            % modelFeatureInspectionRowsForFields  Keep selected fields from feature rows.
            tmpl = struct();
            for ff=1:numel(fields), tmpl.(fields{ff}) = ''; end
            rows = tmpl([]);
            if ~isstruct(inRows) || isempty(inRows), return; end
            rows = repmat(tmpl, 1, numel(inRows));
            for rr=1:numel(inRows)
                for ff=1:numel(fields)
                    f = fields{ff};
                    if isfield(inRows(rr), f)
                        rows(rr).(f) = inRows(rr).(f);
                    else
                        rows(rr).(f) = '';
                    end
                end
            end
        end

        function rows = modelFeatureInspectionRowsWithFiniteField(inRows, fieldName)
            % modelFeatureInspectionRowsWithFiniteField  Filter rows by one finite numeric field.
            rows = inRows([]);
            if ~isstruct(inRows) || isempty(inRows), return; end
            keep = false(1,numel(inRows));
            for rr=1:numel(inRows)
                if isfield(inRows(rr), fieldName)
                    val = inRows(rr).(fieldName);
                    keep(rr) = isnumeric(val) && ~isempty(val) && any(isfinite(double(val(:))));
                end
            end
            rows = inRows(keep);
        end

        function rows = modelFeatureInspectionDistributionSummaryRows(featureRows, fieldName)
            % modelFeatureInspectionDistributionSummaryRows  Summarize one feature metric distribution.
            tmpl = struct('metricField',fieldName,'nFinite',0,'min',NaN,'max',NaN,'mean',NaN,'median',NaN,'sd',NaN);
            rows = tmpl([]);
            if ~isstruct(featureRows) || isempty(featureRows), return; end
            vals = nan(numel(featureRows),1);
            for rr=1:numel(featureRows)
                if isfield(featureRows(rr), fieldName) && isnumeric(featureRows(rr).(fieldName))
                    v = double(featureRows(rr).(fieldName));
                    if ~isempty(v), vals(rr) = v(1); end
                end
            end
            finite = vals(isfinite(vals));
            if isempty(finite), return; end
            rows = tmpl;
            rows.nFinite = numel(finite);
            rows.min = min(finite);
            rows.max = max(finite);
            rows.mean = mean(finite);
            rows.median = median(finite);
            if numel(finite) > 1, rows.sd = std(finite); else, rows.sd = 0; end
        end

        function rows = modelFeatureInspectionSpatialSummaryRows(spatialMaps)
            % modelFeatureInspectionSpatialSummaryRows  Convert spatial descriptors to table rows.
            tmpl = struct('spatialMapId','','contextId','','measureId','','mapKind','', ...
                'artifactKind','','viewerMode','','hasAtlasCoordinates',false,'hasIndexedVoxelPositions',false, ...
                'hasPositiveValues',false,'hasNegativeValues',false,'enabled',false,'disabledReason','');
            rows = tmpl([]);
            if ~isstruct(spatialMaps) || isempty(spatialMaps), return; end
            rows = repmat(tmpl, 1, numel(spatialMaps));
            for ii=1:numel(spatialMaps)
                rows(ii).spatialMapId = spatialMaps(ii).spatialMapId;
                rows(ii).contextId = spatialMaps(ii).contextId;
                rows(ii).measureId = spatialMaps(ii).measureId;
                rows(ii).mapKind = spatialMaps(ii).mapKind;
                rows(ii).artifactKind = spatialMaps(ii).artifactKind;
                rows(ii).viewerMode = spatialMaps(ii).viewerMode;
                rows(ii).hasAtlasCoordinates = spatialMaps(ii).hasAtlasCoordinates;
                rows(ii).hasIndexedVoxelPositions = spatialMaps(ii).hasIndexedVoxelPositions;
                rows(ii).hasPositiveValues = spatialMaps(ii).hasPositiveValues;
                rows(ii).hasNegativeValues = spatialMaps(ii).hasNegativeValues;
                rows(ii).enabled = spatialMaps(ii).enabled;
                rows(ii).disabledReason = spatialMaps(ii).disabledReason;
            end
        end

        function reportSpec = compileFeatureSelection(NM, reportSpec)
            % Purpose: Compile an explicitly enabled natural selector into the canonical analysis-local FeatureInspectionPlan.
            % Syntax: reportSpec = NMResultsViewerReportTools.compileFeatureSelection(NM,reportSpec)
            % Inputs: Read-only NM and one single-analysis planning specification whose AnalysisPlans entry matches reportSpec.AnalysisIndex.
            % Outputs: The same reportSpec with only that AnalysisPlans entry and its requested metric components updated.
            % Authority and flow: Natural selectors are an API input surface only; authoritative feature contexts/components are resolved through listAvailableComponents.
            % Scientific/state contract: AnalysisPlans is the sole location of analysis-local selector state. No top-level FeatureSelection/FeatureInspectionPlan copy is created.
            % Invariants: Exactly one canonical AnalysisPlans entry owns the selected analysis; browser-authored recipes keep FeatureSelection.Enabled=false.
            % Materialization and performance: Only explicitly enabled API natural selectors trigger catalogue materialization; repeated planning of already-instanced components returns before this compiler is called.
            % Failure semantics: Missing/duplicate analysis-plan identity or unavailable requested payloads fail explicitly.
            % Side effects: None.
            % Consumers and dependencies: planReportSpec and the existing component catalogue authority.
            plans = reportSpec.AnalysisPlans;
            pos = find([plans.AnalysisIndex] == reportSpec.AnalysisIndex,1,'first');
            if isempty(pos)
                error('NMResultsViewerReportTools:MissingAnalysisPlan', ...
                    'Report analysis %d has no canonical AnalysisPlans entry.',reportSpec.AnalysisIndex);
            end
            selection = plans(pos).FeatureSelection;
            if ~selection.Enabled
                return;
            end

            sourcePlan = plans(pos).FeatureInspectionPlan;
            plan = NMResultsViewerReportTools.featureInspectionPlanTemplate();
            maxExpanded = sourcePlan.MaxExpandedComponents;
            if isfinite(maxExpanded) && maxExpanded >= 1, plan.MaxExpandedComponents = double(round(maxExpanded)); end

            classifiers = selection.Classifiers;
            if ischar(classifiers) || (isstring(classifiers) && isscalar(classifiers))
                classifierText = lower(strtrim(char(string(classifiers))));
                if strcmp(classifierText,'all')
                    plan.ClassifierScope = 'all_binary';
                    plan.SelectedClassifierIndices = [];
                elseif ~isempty(classifierText)
                    error('NMResultsViewerReportTools:InvalidNaturalClassifierSelection', ...
                        'FeatureSelection.Classifiers must be a numeric vector, empty, or "all".');
                end
            elseif ~isempty(classifiers)
                classifiers = NMResultsViewerReportTools.requiredPositiveIntegerVector(classifiers, ...
                    'FeatureSelection.Classifiers');
                plan.ClassifierScope = 'selected';
                plan.SelectedClassifierIndices = classifiers;
            end

            modalities = selection.Modalities;
            includeCombined = selection.IncludeCombined;
            plan.SelectedFeatureContextIds = {};
            plan.SelectedModalityIndices = [];
            plan.IncludeCombinedFeatureContext = logical(includeCombined);
            if ischar(modalities) || (isstring(modalities) && isscalar(modalities))
                modalityText = lower(strtrim(char(string(modalities))));
                if strcmp(modalityText,'all')
                    if includeCombined, plan.FeatureSourceScope = 'combined_and_all'; else, plan.FeatureSourceScope = 'all_physical'; end
                elseif ~isempty(modalityText)
                    error('NMResultsViewerReportTools:InvalidNaturalModalitySelection', ...
                        'FeatureSelection.Modalities must be a numeric vector, empty, or "all".');
                elseif includeCombined
                    plan.FeatureSourceScope = 'combined';
                end
            elseif ~isempty(modalities)
                plan.SelectedModalityIndices = NMResultsViewerReportTools.requiredPositiveIntegerVector(modalities, ...
                    'FeatureSelection.Modalities');
                plan.FeatureSourceScope = 'selected_modalities';
            elseif includeCombined
                plan.FeatureSourceScope = 'combined';
            end

            retained = selection.Components;
            if ischar(retained) || (isstring(retained) && isscalar(retained))
                retainedText = lower(strtrim(char(string(retained))));
                if strcmp(retainedText,'all')
                    plan.ComponentScope = 'all_retained';
                    plan.SelectedBackprojectionComponentIndices = [];
                    plan.SelectedBackprojectionComponentIds = {};
                elseif ~isempty(retainedText)
                    error('NMResultsViewerReportTools:InvalidNaturalComponentSelection', ...
                        'FeatureSelection.Components must be a numeric vector, empty, or "all".');
                end
            elseif ~isempty(retained)
                retained = NMResultsViewerReportTools.requiredPositiveIntegerVector(retained, ...
                    'FeatureSelection.Components');
                plan.ComponentScope = 'selected';
                plan.SelectedBackprojectionComponentIndices = retained;
                plan.SelectedBackprojectionComponentIds = {};
            end
            plan.IncludeFusionOverview = selection.IncludeFusionOverview;
            reportSpec.AnalysisPlans(pos).FeatureInspectionPlan = plan;

            payloadIds = NMResultsViewerReportTools.safeCellstr(selection.Payloads);
            payloadIds = unique(payloadIds,'stable');
            if isempty(payloadIds), return; end

            current = reportSpec.Components;
            isMetric = false(1,numel(current));
            currentMetricIds = cell(1,0);
            for ii=1:numel(current)
                inst=current(ii).Instance;
                isMetric(ii)=strcmp(inst.ComponentType,'feature_metric');
                if isMetric(ii)
                    metricId=inst.MetricId;
                    if isempty(metricId)
                        error('NMResultsViewerReportTools:MissingFeatureMetricIdentity', ...
                            'Feature metric component %s has no structured MetricId.',current(ii).Id);
                    end
                    currentMetricIds{end+1}=metricId; %#ok<AGROW>
                end
            end
            currentMetricIds=unique(currentMetricIds,'stable');
            if numel(currentMetricIds)==numel(payloadIds) && all(ismember(payloadIds,currentMetricIds)), return; end
            query = struct('AnalysisIndex',reportSpec.AnalysisIndex,'Source',reportSpec.Source, ...
                'ResultType','model_feature_inspection','MultiClassModeIndex',reportSpec.MultiClassModeIndex);
            if ~isempty(reportSpec.Components)
                firstPayload = reportSpec.Components(1).PayloadSpec;
                if isstruct(firstPayload)
                    copyFields = {'classifierIndex','targetIndex','modelSource','maxFeatures','maxComponents'};
                    for ff=1:numel(copyFields)
                        field = copyFields{ff};
                        if isfield(firstPayload,field) && ~isempty(firstPayload.(field)), query.(field)=firstPayload.(field); end
                    end
                end
            end
            [catalogueComponents, ~] = NMResultsViewerReportTools.listAvailableComponents(NM, query);
            current = current(~isMetric);
            selected = NMResultsViewerReportTools.componentSpecTemplate([]);
            for ii=1:numel(payloadIds)
                catPos=[];
                for cc=1:numel(catalogueComponents)
                    inst=catalogueComponents(cc).Instance;
                    if strcmp(inst.ComponentType,'feature_metric') && ...
                            strcmp(inst.MetricId,payloadIds{ii})
                        catPos=cc;break;
                    end
                end
                if isempty(catPos) || ~catalogueComponents(catPos).Enabled
                    error('NMResultsViewerReportTools:NaturalPayloadUnavailable', ...
                        'Requested feature payload "%s" is unavailable in the selected analysis.',payloadIds{ii});
                end
                spec = NMResultsViewerReportTools.componentSpecTemplate();
                spec.Id = catalogueComponents(catPos).Id;
                spec.Title = catalogueComponents(catPos).Label;
                spec.Viewspace = catalogueComponents(catPos).Viewspace;
                spec.PayloadSpec = catalogueComponents(catPos).PayloadSpec;
                spec.Layout = catalogueComponents(catPos).DefaultLayout;
                spec.Instance = catalogueComponents(catPos).Instance;
                spec.Options = struct();
                selected(end+1)=spec; %#ok<AGROW>
            end
            reportSpec.Components = [current selected];
        end

        function values = requiredPositiveIntegerVector(raw, label)
            % requiredPositiveIntegerVector  Validate one natural 1-based selector vector.
            if ~(isnumeric(raw) || islogical(raw))
                error('NMResultsViewerReportTools:InvalidNaturalSelectionVector', ...
                    '%s must contain finite positive integer indices.',label);
            end
            values = double(raw(:))';
            if any(~isfinite(values) | values < 1 | abs(values-round(values)) > eps(max(ones(size(values)),abs(values))))
                error('NMResultsViewerReportTools:InvalidNaturalSelectionVector', ...
                    '%s must contain finite positive integer indices.',label);
            end
            values = unique(round(values),'stable');
        end

        function reportSpec = normalizeReportSpec(NM, reportSpec)
            % Purpose: Normalize schema-2 Report Builder input into one canonical AnalysisPlans representation.
            % Syntax: reportSpec = NMResultsViewerReportTools.normalizeReportSpec(NM,reportSpec)
            % Inputs: Read-only NM and one public/browser report specification.
            % Outputs: Canonical schema-2 reportSpec in which all analysis-local selector/presentation state exists only in AnalysisPlans; root PresentationState carries report-global OutputOrder only.
            % Authority and flow: This function validates/report-normalizes composition state only. Scientific availability remains delegated to existing Results Viewer authorities.
            % Scientific/state contract: AnalysisPlans is the sole persistent location for FeatureSelection, FeatureInspectionPlan, FeaturePresentations, local PresentationState and DisplayOverrides.
            % Invariants: Every ordinary component analysis identity has exactly one AnalysisPlans entry; obsolete root analysis-local fields are rejected rather than migrated or aliased; an explicitly empty Components array remains empty.
            % Materialization and performance: O(A+C) compact metadata normalization; no Scientific State construction, file/resource read, feature scan or payload materialization. Natural selector compilation is deferred to planning.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; safe for interactive/retained Report Builder normalization.
            % Interactive/retained use: Safe on explicit build/plan boundaries and retained browser state serialization because it performs metadata normalization only.
            % Failure semantics: Conflicting schema versions, obsolete duplicate schema fields, duplicate/missing analysis plans and invalid local-state shapes fail explicitly.
            % Side effects: None.
            % Consumers and dependencies: buildReport, planReportSpecForBrowser, browser/MATLAB report services and script/API recipes.
            if ~isstruct(reportSpec) || ~isscalar(reportSpec)
                error('NMResultsViewerReportTools:InvalidReportSpecShape','Report specification must be one scalar struct.');
            end
            if isfield(reportSpec,'schemaVersion') % nm2-allow: report recipe schema admission rejects obsolete casing.
                error('NMResultsViewerReportTools:NonCanonicalReportSchema','Use SchemaVersion, not schemaVersion.');
            end
            if isfield(reportSpec,'SchemaVersion') && ~isequal(reportSpec.SchemaVersion,2) % nm2-allow: report recipe schema version validation at its producer.
                error('NMResultsViewerReportTools:UnsupportedReportSchemaVersion', ...
                    'Unsupported report specification schema version. Expected 2.');
            end

            obsolete={'FeatureSelection','FeaturePresentations','DisplayOverrides','FeatureInspectionPlan'};
            present=obsolete(isfield(reportSpec,obsolete));
            if ~isempty(present)
                error('NMResultsViewerReportTools:NonCanonicalAnalysisLocalState', ...
                    'Analysis-local Report Builder state must be encoded only in AnalysisPlans; obsolete root field(s): %s.',strjoin(present,', '));
            end
            if isfield(reportSpec,'PresentationState')&&~isempty(reportSpec.PresentationState)
                if ~isstruct(reportSpec.PresentationState)||~isscalar(reportSpec.PresentationState)
                    error('NMResultsViewerReportTools:InvalidPresentationStateShape','PresentationState must be one scalar struct.');
                end
                rootFields=fieldnames(reportSpec.PresentationState);
                if ~isempty(setdiff(rootFields,{'OutputOrder'}))
                    error('NMResultsViewerReportTools:InvalidGlobalPresentationState', ...
                        'Root PresentationState is report-global and may contain only OutputOrder.');
                end
            end

            reportSpec=NMResultsViewerReportTools.copyMissingFields(reportSpec,NMResultsViewerReportTools.reportSpecTemplate());
            reportSpec.SchemaVersion=2;
            if ~isstruct(reportSpec.PresentationState)||~isscalar(reportSpec.PresentationState)
                error('NMResultsViewerReportTools:InvalidPresentationStateShape','PresentationState must be one scalar struct.');
            end
            if ~isfield(reportSpec.PresentationState,'OutputOrder'),reportSpec.PresentationState.OutputOrder={};end
            if ~isequal(sort(fieldnames(reportSpec.PresentationState)),{'OutputOrder'}')
                error('NMResultsViewerReportTools:InvalidGlobalPresentationState', ...
                    'Root PresentationState is report-global and may contain only OutputOrder.');
            end

            plans=NMResultsViewerReportTools.fixedStructArray( ...
                reportSpec.AnalysisPlans,NMResultsViewerReportTools.analysisPlanTemplate(),'AnalysisPlans');
            if isempty(plans)
                plans=NMResultsViewerReportTools.analysisPlanTemplate();
                plans.AnalysisIndex=reportSpec.AnalysisIndex;
            end
            for pp=1:numel(plans)
                if ~isfinite(plans(pp).AnalysisIndex)||plans(pp).AnalysisIndex<1||plans(pp).AnalysisIndex~=round(plans(pp).AnalysisIndex)
                    error('NMResultsViewerReportTools:InvalidAnalysisPlanIndex','Each AnalysisPlans.AnalysisIndex must be one positive integer.');
                end
                if ~isstruct(plans(pp).FeatureSelection)||~isscalar(plans(pp).FeatureSelection),error('NMResultsViewerReportTools:InvalidFeatureSelectionShape','AnalysisPlans.FeatureSelection must be one scalar struct.');end
                plans(pp).FeatureSelection=NMResultsViewerReportTools.copyMissingFields(plans(pp).FeatureSelection,NMResultsViewerReportTools.featureSelectionTemplate());
                if ~isstruct(plans(pp).FeatureInspectionPlan)||~isscalar(plans(pp).FeatureInspectionPlan),error('NMResultsViewerReportTools:InvalidFeatureInspectionPlanShape','AnalysisPlans.FeatureInspectionPlan must be one scalar struct.');end
                plans(pp).FeatureInspectionPlan=NMResultsViewerReportTools.copyMissingFields(plans(pp).FeatureInspectionPlan,NMResultsViewerReportTools.featureInspectionPlanTemplate());
                if ~isstruct(plans(pp).OOCVGroupPlan)||~isscalar(plans(pp).OOCVGroupPlan),error('NMResultsViewerReportTools:InvalidOOCVGroupPlanShape','AnalysisPlans.OOCVGroupPlan must be one scalar struct.');end
                plans(pp).OOCVGroupPlan=NMResultsViewerReportTools.copyMissingFields(plans(pp).OOCVGroupPlan,NMResultsViewerReportTools.oocvGroupPlanTemplate());
                plans(pp).EvaluationSourcePlan=NMResultsViewerReportTools.copyMissingFields( ...
                    plans(pp).EvaluationSourcePlan,NMResultsViewerReportTools.evaluationSourcePlanTemplate());
                evaluationPlan=plans(pp).EvaluationSourcePlan;
                if ~ismember(evaluationPlan.Mode,{'current','selected'})
                    error('NMResultsViewerReportTools:InvalidEvaluationSourceMode', ...
                        'EvaluationSourcePlan.Mode must be current or selected.');
                end
                sourceIds=evaluationPlan.SelectedSourceIds;
                % Browser JSON encodes an empty cell selection as []; complete it here.
                if isempty(sourceIds),sourceIds={};end
                plans(pp).EvaluationSourcePlan.SelectedSourceIds=sourceIds;
                if numel(unique(sourceIds))~=numel(sourceIds) || ...
                        (strcmp(evaluationPlan.Mode,'selected') && isempty(sourceIds))
                    error('NMResultsViewerReportTools:InvalidEvaluationSourceSelection', ...
                        'Selected evaluation source IDs must be a nonempty unique cell array of strings.');
                end
                groupMode=lower(strtrim(char(string(plans(pp).OOCVGroupPlan.Mode))));
                if ~ismember(groupMode,{'current','selected'}),error('NMResultsViewerReportTools:InvalidOOCVGroupPlanMode','OOCVGroupPlan.Mode must be current or selected.');end
                plans(pp).OOCVGroupPlan.Mode=groupMode;
                groupIndices=double(plans(pp).OOCVGroupPlan.SelectedSubgroupIndices(:)');
                if any(~isfinite(groupIndices)|groupIndices<2|groupIndices~=round(groupIndices)),error('NMResultsViewerReportTools:InvalidOOCVGroupSelection','Selected OOCV group comparisons must use subgroup indices >= 2.');end
                plans(pp).OOCVGroupPlan.SelectedSubgroupIndices=unique(round(groupIndices),'stable');
                plans(pp).OOCVGroupPlan.SelectedSubgroupLabels=NMResultsViewerReportTools.safeCellstr(plans(pp).OOCVGroupPlan.SelectedSubgroupLabels);
                if strcmp(groupMode,'selected')&&isempty(plans(pp).OOCVGroupPlan.SelectedSubgroupIndices),error('NMResultsViewerReportTools:MissingOOCVGroupSelection','Selected OOCV group export mode requires at least one comparison.');end
                if strcmp(groupMode,'selected')&&numel(plans(pp).OOCVGroupPlan.SelectedSubgroupLabels)~=numel(plans(pp).OOCVGroupPlan.SelectedSubgroupIndices),error('NMResultsViewerReportTools:InvalidOOCVGroupLabels','Selected OOCV group export requires one stored backend comparison label for every selected subgroup index.');end
                plans(pp).FeaturePresentations=NMResultsViewerReportTools.fixedStructArray( ...
                    plans(pp).FeaturePresentations,NMResultsViewerReportTools.featurePresentationTemplate(),'AnalysisPlans.FeaturePresentations');
                for rr=1:numel(plans(pp).FeaturePresentations)
                    representationId=strtrim(char(string(plans(pp).FeaturePresentations(rr).Representation)));
                    supportDomain=strtrim(char(string(plans(pp).FeaturePresentations(rr).SupportDomain)));
                    if isempty(representationId)
                        error('NMResultsViewerReportTools:MissingFeaturePresentationIdentity', ...
                            'Each AnalysisPlans.FeaturePresentations row must declare Representation.');
                    end
                    if isempty(supportDomain)
                        error('NMResultsViewerReportTools:MissingFeaturePresentationSupportDomain', ...
                            'Feature presentation %s must declare SupportDomain structurally.',representationId);
                    end
                end
                if ~isstruct(plans(pp).PresentationState)||~isscalar(plans(pp).PresentationState),error('NMResultsViewerReportTools:InvalidPresentationStateShape','AnalysisPlans.PresentationState must be one scalar struct.');end
                plans(pp).PresentationState=NMResultsViewerReportTools.copyMissingFields( ...
                    plans(pp).PresentationState,struct('BrowserFeatureInspectionViewState',struct()));
                snapshot=plans(pp).PresentationState.BrowserFeatureInspectionViewState;
                % nm2-allow: user-supplied snapshot structure is validated before its fixed internal projection.
                if ~isstruct(snapshot)||~isscalar(snapshot)
                    error('NMResultsViewerReportTools:InvalidFeatureSnapshot', ...
                        'AnalysisPlans.PresentationState.BrowserFeatureInspectionViewState must be a scalar struct.');
                end
                if ~isstruct(plans(pp).DisplayOverrides)||~isscalar(plans(pp).DisplayOverrides),error('NMResultsViewerReportTools:InvalidDisplayOverridesShape','AnalysisPlans.DisplayOverrides must be one scalar struct.');end
            end
            if numel(unique([plans.AnalysisIndex]))~=numel(plans),error('NMResultsViewerReportTools:DuplicateAnalysisPlan','AnalysisPlans may contain each analysis only once.');end
            reportSpec.AnalysisPlans=plans;
            if ~any([plans.AnalysisIndex]==reportSpec.AnalysisIndex)
                error('NMResultsViewerReportTools:MissingPrimaryAnalysisPlan','The report AnalysisIndex must identify one canonical AnalysisPlans entry.');
            end

            if ~isfield(reportSpec,'Components')
                defaultSpec=NMResultsViewerReportTools.defaultReportSpec(NM,reportSpec);
                reportSpec.Components=defaultSpec.Components;
            else
                reportSpec.Components=NMResultsViewerReportTools.normalizeComponentSpecs(reportSpec.Components,reportSpec);
            end
            ordinary=reportSpec.Components(~strcmp({reportSpec.Components.Viewspace},'cross_analysis'));
            componentAnalyses=[];
            for cc=1:numel(ordinary)
                ps=ordinary(cc).PayloadSpec;
                componentAnalyses(end+1)=ps.analysisIndex; %#ok<AGROW>
            end
            missing=setdiff(unique(componentAnalyses),[plans.AnalysisIndex]);
            if ~isempty(missing)
                error('NMResultsViewerReportTools:MissingAnalysisPlan', ...
                    'Ordinary report components reference analysis indices without AnalysisPlans entries: %s.', ...
                    strjoin(arrayfun(@num2str,missing,'UniformOutput',false),', '));
            end
            if ~isfield(reportSpec,'Layout')||~isstruct(reportSpec.Layout)
                reportSpec.Layout=NMResultsViewerReportTools.defaultReportLayout(numel(reportSpec.Components));
            end
        end

        function [reportSpec, session] = planReportSpec(session, reportSpec)

            % Purpose: Expand a declarative report specification into deterministic per-analysis component instances plus set-level components.

            % Syntax: see method signature above.

            % Inputs: Request-scoped report session and normalized reportSpec.

            % Outputs: Planned reportSpec with ordered expanded Components and PlanSummary.

            % Authority and flow: The established single-analysis planner remains authoritative inside each explicit component PayloadSpec.analysisIndex group; set-level cross_analysis components are appended once after analysis-local groups.

            % Scientific/state contract: Scientific State answers what exists; Report Builder records only composition/presentation state and preserves explicit scientific identities.

            % Invariants: No raw NM result discovery is introduced here; ordinary components retain explicit analysisIndex, set-level components retain explicit AnalysisIndices, and catalogue-unavailable requests remain status-only components outside classifier/feature expansion.

            % Materialization and performance: Compact report metadata/planning unless delegated existing component planners materialize established payload metadata; no new feature-scale work is introduced.

            % Resource declaration: This method itself reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices, and creates no feature-scale arrays; delegated established authorities retain their own contracts.

            % Interactive/retained use: Intended for explicit Report Builder catalogue/planning actions; it does not introduce a retained scientific rematerialization loop.
            % Failure semantics: Invalid schema, analysis identity or planning state fails explicitly through existing Report Builder errors; invalid scientific state is never substituted.

            % Side effects: None except request-scoped session/cache mutation where explicitly passed by planReportSpec.

            % Consumers and dependencies: Browser/API Report Builder, existing component planners/materializers, Scientific State and Cross-analysis report integration.
            % Structural stage identity is checked before ordering, grouping or any
            % delegated selector/materialization work. A fully planned specification
            % is already canonical and therefore returns unchanged.
            % One browser snapshot per analysis is admitted by the report-plan boundary.
            % Bind to unplanned FI instances only; the existing classifier/context planner
            % then owns instance-specific rebinding. Direct API component options remain valid.
            for cc=1:numel(reportSpec.Components)
                comp=reportSpec.Components(cc);
                if ~strcmp(comp.Viewspace,'model_feature_inspection') || ~isempty(comp.Instance.Id) || ...
                        ismember(comp.Id,{'model_feature_inspection.fractionated_individual', ...
                        'model_feature_inspection.fractionated_population', ...
                        'model_feature_inspection.fractionated_clusters'}),continue;end
                plan=reportSpec.AnalysisPlans([reportSpec.AnalysisPlans.AnalysisIndex]==comp.PayloadSpec.analysisIndex);
                snapshot=plan.PresentationState.BrowserFeatureInspectionViewState;
                if isempty(fieldnames(snapshot)),continue;end
                if ~isempty(fieldnames(comp.Options.BrowserFeatureInspectionViewState))
                    error('NMResultsViewerReportTools:DuplicateFeatureSnapshot', ...
                        'The Feature Inspection snapshot must be supplied by either its AnalysisPlan or component Options, not both.');
                end
                reportSpec.Components(cc).Options.BrowserFeatureInspectionViewState=snapshot;
            end
            inputComponents=reportSpec.Components;inputIds={inputComponents.Id};
            catalogueUnavailable=false(1,numel(inputComponents));
            for uu=1:numel(inputComponents)
                unavailableOptions=inputComponents(uu).Options;
                catalogueUnavailable(uu)=NMResultsViewerReportTools.structLogical(unavailableOptions,{'ReportCatalogueUnavailable'},false);
            end
            inputViewspaces={inputComponents.Viewspace};
            classifierScoped=(strcmp(inputViewspaces,'model_performance') | ...
                strcmp(inputViewspaces,'model_optimization') | ...
                strcmp(inputViewspaces,'model_feature_inspection')) & ~catalogueUnavailable;
            if any(classifierScoped)
                plannedMask=false(1,sum(classifierScoped));plannedPositions=find(classifierScoped);
                for kk=1:numel(plannedPositions)
                    inst=inputComponents(plannedPositions(kk)).Instance;
                    plannedMask(kk)=~isempty(inst.Id);
                end
                if any(plannedMask)
                    if ~all(plannedMask)
                        error('NMResultsViewerReportTools:MixedPlanningStage', ...
                            'Classifier-scoped report components must be either entirely unplanned or entirely planned.');
                    end
                    return;
                end
            end
            comps = NMResultsViewerReportTools.scientificOrderComponentSpecs(inputComponents);

            % AnalysisPlans is the only persistent analysis-local state. Multi-analysis
            % composition passes one canonical entry into the same single-analysis
            % planner rather than copying selector/presentation fields to the root.
            ids={comps.Id}; viewspaces={comps.Viewspace};
            isSetLevel=strcmp(viewspaces,'cross_analysis');
            ordinary=comps(~isSetLevel); setLevel=comps(isSetLevel);
            componentAnalyses=[];
            for aa=1:numel(ordinary)
                ps=ordinary(aa).PayloadSpec;
                componentAnalyses(end+1)=ps.analysisIndex; %#ok<AGROW>
            end
            planIndices=[reportSpec.AnalysisPlans.AnalysisIndex];
            if any(~ismember(componentAnalyses,planIndices))
                missing=unique(componentAnalyses(~ismember(componentAnalyses,planIndices)),'stable');
                error('NMResultsViewerReportTools:MissingAnalysisPlan', ...
                    'Report component analysis identity has no canonical AnalysisPlans entry: %s.', ...
                    strjoin(arrayfun(@num2str,missing,'UniformOutput',false),', '));
            end
            allAnalyses=planIndices;
            if numel(allAnalyses)>1
                expanded=NMResultsViewerReportTools.componentSpecTemplate([]); summaries=cell(1,0);
                for aa=1:numel(allAnalyses)
                    idx=allAnalyses(aa);mask=componentAnalyses==idx;
                    if ~any(mask),continue;end
                    pos=find(planIndices==idx,1,'first');
                    if isempty(pos)
                        error('NMResultsViewerReportTools:MissingAnalysisPlan', ...
                            'Report analysis %d has no canonical AnalysisPlans entry.',idx);
                    end
                    local=reportSpec;local.AnalysisIndex=idx;local.Components=ordinary(mask);local.AnalysisPlans=reportSpec.AnalysisPlans(pos);
                    [local,session]=NMResultsViewerReportTools.planReportSpec(session,local);
                    reportSpec.AnalysisPlans(pos)=local.AnalysisPlans(1);
                    expanded=[expanded local.Components]; %#ok<AGROW>
                    summaries{end+1}=local.PlanSummary; %#ok<AGROW>
                end
                reportSpec.Components=NMResultsViewerReportTools.reindexComponentSpecs([expanded setLevel]);
                reportSpec.Layout=NMResultsViewerReportTools.defaultReportLayout(numel(reportSpec.Components));
                reportSpec.PlanSummary=struct('scope','multi_analysis','analysisIndices',allAnalyses,'analysisSummaries',{summaries},'requestedComponentCount',numel(comps),'expandedComponentCount',numel(reportSpec.Components));
                return;
            end
            if isempty(allAnalyses)
                error('NMResultsViewerReportTools:MissingAnalysisPlan','Report planning requires one canonical AnalysisPlans entry.');
            end
            reportSpec.AnalysisIndex=allAnalyses(1);
            pos=find(planIndices==reportSpec.AnalysisIndex,1,'first');
            if isempty(pos)
                error('NMResultsViewerReportTools:MissingAnalysisPlan', ...
                    'Report analysis %d has no canonical AnalysisPlans entry.',reportSpec.AnalysisIndex);
            end
            if strcmp(reportSpec.AnalysisPlans(pos).EvaluationSourcePlan.Mode,'selected')
                [reportSpec,session]=NMResultsViewerReportTools.planSelectedEvaluationSources(session,reportSpec);
                return;
            end
            if reportSpec.AnalysisPlans(pos).FeatureSelection.Enabled
                reportSpec=NMResultsViewerReportTools.compileFeatureSelection(session.CurrentNM,reportSpec);
                comps=NMResultsViewerReportTools.scientificOrderComponentSpecs(reportSpec.Components);
            end
            plan = reportSpec.AnalysisPlans(pos).FeatureInspectionPlan;
            if isempty(comps)
                reportSpec.Components = comps;
                reportSpec.PlanSummary = struct('requestedComponentCount',0,'expandedComponentCount',0, ...
                    'classifierCount',0,'classifierIndices',[],'classifierLabels',{{}}, ...
                    'modelPerformanceInstanceCount',0,'modelOptimizationInstanceCount',0, ...
                    'featureContextCount',0, ...
                    'backprojectionInstanceCount',0,'classifierScope','current');
                return;
            end

            overviewIds = {'model_feature_inspection.modality_contribution', ...
                'model_feature_inspection.component_summary', ...
                'model_feature_inspection.component_modality_matrix'};
            ids = {comps.Id};
            viewspaces={comps.Viewspace};
            catalogueUnavailable=false(1,numel(comps));
            for uu=1:numel(comps)
                unavailableOptions=comps(uu).Options;
                catalogueUnavailable(uu)=NMResultsViewerReportTools.structLogical(unavailableOptions,{'ReportCatalogueUnavailable'},false);
            end
            isPerformance = strcmp(viewspaces,'model_performance') & ~catalogueUnavailable;
            isOptimization = strcmp(viewspaces,'model_optimization') & ~catalogueUnavailable;
            isFeature = strcmp(viewspaces,'model_feature_inspection') & ~catalogueUnavailable;
            isClassifierScoped = isPerformance | isOptimization | isFeature;
            if ~any(isClassifierScoped)
                reportSpec.Components = NMResultsViewerReportTools.reindexComponentSpecs(comps);
                reportSpec.PlanSummary = struct('requestedComponentCount',numel(comps), ...
                    'expandedComponentCount',numel(comps),'classifierCount',0, ...
                    'classifierIndices',[],'classifierLabels',{{}}, ...
                    'modelPerformanceInstanceCount',0,'modelOptimizationInstanceCount',0, ...
                    'featureContextCount',0, ...
                    'backprojectionInstanceCount',0,'classifierScope','current');
                return;
            end

            performanceSpecs = comps(isPerformance);
            optimizationSpecs = comps(isOptimization);
            featurePositions = find(isFeature);
            if isempty(featurePositions)
                fixedBeforeFeature = comps(~isClassifierScoped);
                fixedAfterFeature = comps(false(1,numel(comps)));
            else
                firstFeaturePosition = featurePositions(1);
                positions = 1:numel(comps);
                fixedBeforeFeature = comps(~isClassifierScoped & positions < firstFeaturePosition);
                fixedAfterFeature = comps(~isClassifierScoped & positions > firstFeaturePosition);
            end
            isOverview = ismember(ids, overviewIds);
            % The Individual Dx payload spans every retained component. It is
            % scoped by classifier and feature context, never by component cut.
            isContextWide = isFeature & ismember(ids, ...
                {'model_feature_inspection.fractionated_individual','model_feature_inspection.fractionated_population','model_feature_inspection.fractionated_clusters'});
            featureSpecs = comps(isFeature);
            detailSpecs = comps(isFeature & ~isOverview);
            contextWideDetails = isContextWide(isFeature & ~isOverview);
            nComponentDetails = numel(detailSpecs)-nnz(contextWideDetails);
            requestedOverview = comps(isOverview);

            sourcePerformanceClassifierIndex = NMResultsViewerReportTools.reportComponentClassifierSeed( ...
                performanceSpecs, reportSpec, 'classification');
            sourceOptimizationClassifierIndex = NMResultsViewerReportTools.reportComponentClassifierSeed( ...
                optimizationSpecs, reportSpec, 'model_optimization');
            sourceFeatureClassifierIndex = NMResultsViewerReportTools.reportComponentClassifierSeed( ...
                featureSpecs, reportSpec, 'model_feature_inspection');
            plan = reportSpec.AnalysisPlans(pos).FeatureInspectionPlan;
            classifierScope = plan.ClassifierScope;
            if strcmp(classifierScope,'current')
                seedValues = [sourcePerformanceClassifierIndex, ...
                    sourceOptimizationClassifierIndex, sourceFeatureClassifierIndex];
                seedLabels = {'Model Performance','Model Optimization','Model Feature Inspection'};
                finiteSeedMask = isfinite(seedValues);
                distinctSeeds = unique(round(seedValues(finiteSeedMask)),'stable');
                if numel(distinctSeeds) > 1
                    parts = cell(1,sum(finiteSeedMask));
                    sourcePositions = find(finiteSeedMask);
                    for ss=1:numel(sourcePositions)
                        pos = sourcePositions(ss);
                        parts{ss} = sprintf('%s (%d)',seedLabels{pos},round(seedValues(pos)));
                    end
                    error('NMResultsViewerReportTools:ConflictingCurrentClassifierSelection', ...
                        ['Current decomposition scope received conflicting classifier indices ' ...
                         'across selected model-result viewspaces: %s.'],strjoin(parts,', '));
                end
            end
            sharedSeedIndex = sourcePerformanceClassifierIndex;
            if ~isfinite(sharedSeedIndex), sharedSeedIndex = sourceOptimizationClassifierIndex; end
            if ~isfinite(sharedSeedIndex), sharedSeedIndex = sourceFeatureClassifierIndex; end
            if ~isfinite(sharedSeedIndex), sharedSeedIndex = 1; end
            if ~isempty(performanceSpecs) && ~isfinite(sourcePerformanceClassifierIndex)
                sourcePerformanceClassifierIndex = sharedSeedIndex;
            end
            if ~isempty(optimizationSpecs) && ~isfinite(sourceOptimizationClassifierIndex)
                sourceOptimizationClassifierIndex = sharedSeedIndex;
            end
            currentResultType = '';
            if ~isempty(performanceSpecs)
                performanceProbe = NMResultsViewerReportTools.componentPayloadSpec( ...
                    performanceSpecs(1), reportSpec, 'classification');
                currentResultType = performanceProbe.resultType;
            end
            performanceGroupIndices=1; performanceGroupLabels={''};
            if ~isempty(performanceSpecs)
                groupProbeSpec=NMResultsViewerReportTools.componentPayloadSpec(performanceSpecs(1),reportSpec,'classification');
                [isOOCVPerformance,~]=NMResultsViewerTools.parseOOCVSourceId(groupProbeSpec.source);
                groupPlan=reportSpec.AnalysisPlans(pos).OOCVGroupPlan;
                if isOOCVPerformance
                    [availableGroups,currentGroupIndex]=NMResultsViewerTools.oocvSubgroupsForAnalysis(session.CurrentNM,reportSpec.AnalysisIndex,groupProbeSpec);
                    if strcmp(groupPlan.Mode,'selected')
                        requestedGroups=double(groupPlan.SelectedSubgroupIndices(:)'); requestedLabels=groupPlan.SelectedSubgroupLabels;
                        performanceGroupIndices=zeros(1,numel(requestedGroups)); performanceGroupLabels=cell(1,numel(requestedGroups));
                        for gg=1:numel(requestedGroups)
                            hit=find([availableGroups.index]==requestedGroups(gg)&[availableGroups.enabled],1,'first');
                            if isempty(hit),error('NMResultsViewerReportTools:UnavailableOOCVGroup','OOCV subgroup %d is unavailable for the selected analysis/source/target.',requestedGroups(gg));end
                            label=availableGroups(hit).label;
                            if ~isempty(requestedLabels)&&~strcmp(label,requestedLabels{gg}),error('NMResultsViewerReportTools:ChangedOOCVGroupIdentity','OOCV subgroup %d no longer matches the stored comparison label.',requestedGroups(gg));end
                            performanceGroupIndices(gg)=double(requestedGroups(gg)); performanceGroupLabels{gg}=label;
                        end
                    else
                        requestedCurrent=NMResultsViewerReportTools.structScalar(groupProbeSpec,{'oocvSubgroupIndex','OOCVSubgroupIndex'},currentGroupIndex);
                        hit=find([availableGroups.index]==requestedCurrent&[availableGroups.enabled],1,'first');
                        if isempty(hit),error('NMResultsViewerReportTools:UnavailableCurrentOOCVGroup','The currently selected OOCV subgroup is unavailable for this report payload.');end
                        performanceGroupIndices=double(availableGroups(hit).index); performanceGroupLabels={availableGroups(hit).label};
                    end
                elseif strcmp(groupPlan.Mode,'selected')
                    error('NMResultsViewerReportTools:OOCVGroupPlanNotApplicable','Explicit OOCV group export is applicable only to OOCV Model Performance payloads.');
                end
            end
            classifierProbeSpec = struct('analysisIndex',reportSpec.AnalysisIndex, ...
                'classifierIndex',double(sharedSeedIndex),'resultType',currentResultType);
            classifiers = NMResultsViewerReportTools.reportPlanBinaryClassifiers( ...
                session.CurrentNM, reportSpec, classifierProbeSpec);
            if isempty(classifiers)
                error('NMResultsViewerReportTools:NoClassifiersForPlan', ...
                    'The requested decomposition scope does not resolve to a trained classifier.');
            end

            maxExpanded = max(1, round(plan.MaxExpandedComponents));
            forceBinaryPerformance = any(strcmp(classifierScope,{'all_binary','selected'}));
            performanceInstanceCount = numel(performanceSpecs) * numel(classifiers) * numel(performanceGroupIndices);
            optimizationInstanceCount = numel(optimizationSpecs) * numel(classifiers);

            planEntry = struct('classifier',struct(),'probeSpec',struct(),'probePayload',struct(), ...
                'contexts',struct([]),'contextPayloads',{{}},'componentLists',{{}}, ...
                'overview',NMResultsViewerReportTools.componentSpecTemplate([]),'instanceCount',0);
            if isempty(featureSpecs)
                featurePlans = planEntry([]);
            else
                featurePlans = repmat(planEntry,1,numel(classifiers));
            end
            requestedCount = numel(comps);
            expandedCount = performanceInstanceCount + optimizationInstanceCount + ...
                numel(fixedBeforeFeature) + numel(fixedAfterFeature);
            totalContexts = 0;
            totalInstances = 0;

            if ~isempty(featureSpecs)
                firstFeature = featureSpecs(1);
                baseProbeSpec = NMResultsViewerReportTools.componentPayloadSpec(firstFeature, reportSpec, 'model_feature_inspection');
                baseProbeSpec.resultType = 'model_feature_inspection';
                baseProbeSpec.featureInspectionPayloadScope = 'metadata';
                if ~isfinite(sourceFeatureClassifierIndex), sourceFeatureClassifierIndex = sharedSeedIndex; end
                baseProbeSpec.classifierIndex = double(sourceFeatureClassifierIndex);
                for kk=1:numel(classifiers)
                    NMResultsViewerReportTools.reportProgress('Report Builder', ...
                        sprintf('Resolving feature contexts for decomposition %d/%d.',kk,numel(classifiers)), ...
                        57+2*(kk-1)/numel(classifiers),'plan_features');
                    classifier = classifiers(kk);
                    probeSpec = baseProbeSpec;
                    probeSpec.classifierIndex = double(classifier.index);
                    [probePayload, session] = NMResultsViewerReportTools.reportSessionPayload( ...
                        session, 'model_feature_inspection', probeSpec);
                    contexts = struct([]);
                    contextPayloads = {};
                    componentLists = {};
                    classifierInstances = 0;
                    if ~isempty(detailSpecs)
                        contexts = NMResultsViewerReportTools.reportPlanFeatureContexts(probePayload, plan);
                        if isempty(contexts)
                            error('NMResultsViewerReportTools:NoFeatureContextsForClassifier', ...
                                'The requested feature-source scope is unavailable for binary decomposition "%s".', ...
                                classifier.label);
                        end
                        anchorComponentIndex = NMResultsViewerReportTools.structScalar( ...
                            probePayload, {'selectedBackprojectionComponentIndex'}, NaN);
                        contextPayloads = cell(1,numel(contexts));
                        componentLists = cell(1,numel(contexts));
                        for cc=1:numel(contexts)
                            ctxSpec = probeSpec;
                            ctxSpec.featureContextId = contexts(cc).contextId;
                            ctxSpec = NMResultsViewerReportTools.removeStructFields( ...
                                ctxSpec, {'backprojectionComponentId','componentIndex'});
                            [ctxPayload, session] = NMResultsViewerReportTools.reportSessionPayload( ...
                                session, 'model_feature_inspection', ctxSpec);
                            contextPayloads{cc} = ctxPayload;
                            if nComponentDetails>0
                                componentLists{cc} = NMResultsViewerReportTools.reportPlanBackprojectionComponents( ...
                                    ctxPayload, plan, anchorComponentIndex);
                                classifierInstances = classifierInstances + max(1,numel(componentLists{cc}));
                            end
                        end
                    end

                    overview = requestedOverview;
                    if ~plan.IncludeFusionOverview
                        overview = overview([]);
                    else
                        overview = NMResultsViewerReportTools.reportFusionOverviewSpecs( ...
                            probePayload, probeSpec, reportSpec, overview);
                    end
                    for ii=1:numel(overview)
                        overview(ii) = NMResultsViewerReportTools.bindFeatureClassifierSpec(overview(ii), classifier);
                        overview(ii) = NMResultsViewerReportTools.rebindPlannedFusionOverviewSpec( ...
                            overview(ii), probePayload, sourceFeatureClassifierIndex, classifier.index);
                    end

                    featurePlans(kk).classifier = classifier;
                    featurePlans(kk).probeSpec = probeSpec;
                    featurePlans(kk).probePayload = probePayload;
                    featurePlans(kk).contexts = contexts;
                    featurePlans(kk).contextPayloads = contextPayloads;
                    featurePlans(kk).componentLists = componentLists;
                    featurePlans(kk).overview = overview;
                    featurePlans(kk).instanceCount = classifierInstances;
                    expandedCount = expandedCount + numel(overview) + ...
                        nComponentDetails*classifierInstances + nnz(isContextWide)*numel(contexts);
                    totalContexts = totalContexts + numel(contexts);
                    totalInstances = totalInstances + classifierInstances;
                end
            end

            if expandedCount > maxExpanded
                error('NMResultsViewerReportTools:ExpandedReportTooLarge', ...
                    ['The decomposition/report plan expands to %d components, exceeding ' ...
                     'MaxExpandedComponents=%d.'], expandedCount, maxExpanded);
            end

            tmpl = NMResultsViewerReportTools.componentSpecTemplate();
            planned = repmat(tmpl,1,expandedCount);
            outCount = 0;
            for gg=1:numel(performanceGroupIndices)
                oocvGroupIndex=performanceGroupIndices(gg); oocvGroupLabel=performanceGroupLabels{gg};
                for kk=1:numel(classifiers)
                    classifier = classifiers(kk);
                    for ii=1:numel(performanceSpecs)
                        one = NMResultsViewerReportTools.bindModelPerformanceClassifierSpec( ...
                            performanceSpecs(ii), classifier, sourcePerformanceClassifierIndex, ...
                            forceBinaryPerformance);
                        [isOOCVComponent,~]=NMResultsViewerTools.parseOOCVSourceId(NMResultsViewerReportTools.structText(one.PayloadSpec,{'source','Source'},'cv'));
                        if isOOCVComponent
                            one.PayloadSpec.oocvSubgroupIndex=double(oocvGroupIndex);
                            one.Instance.OOCVSubgroupIndex=double(oocvGroupIndex);
                            one.Instance.OOCVSubgroupLabel=oocvGroupLabel;
                            one.Instance.Id=sprintf('%s|oocv-subgroup:%d',one.Instance.Id,round(oocvGroupIndex));
                            one.Options=NMResultsViewerReportTools.mergeStructs(one.Options,struct('PlannedOOCVSubgroupIndex',double(oocvGroupIndex),'PlannedOOCVSubgroupLabel',oocvGroupLabel));
                        end
                        outCount = outCount + 1;
                        planned(outCount) = one;
                    end
                end
            end
            for kk=1:numel(classifiers)
                classifier = classifiers(kk);
                for ii=1:numel(optimizationSpecs)
                    one = NMResultsViewerReportTools.bindModelOptimizationClassifierSpec( ...
                        optimizationSpecs(ii), classifier);
                    outCount = outCount + 1;
                    planned(outCount) = one;
                end
            end
            for ii=1:numel(fixedBeforeFeature)
                outCount=outCount+1;
                planned(outCount)=fixedBeforeFeature(ii);
            end

            for kk=1:numel(featurePlans)
                classifier = featurePlans(kk).classifier;
                probePayload = featurePlans(kk).probePayload;
                for ii=1:numel(featurePlans(kk).overview)
                    outCount=outCount+1;
                    planned(outCount)=featurePlans(kk).overview(ii);
                end
                contexts = featurePlans(kk).contexts;
                for cc=1:numel(contexts)
                    ctx = contexts(cc);
                    selectedComponents = featurePlans(kk).componentLists{cc};
                    if isempty(selectedComponents)
                        selectedComponents = NMResultsViewerReportTools.emptyBackprojectionPlanEntry();
                    end
                    for bb=1:numel(selectedComponents)
                        for dd=1:numel(detailSpecs)
                            bp = selectedComponents(bb);
                            one = detailSpecs(dd);
                            contextWide = contextWideDetails(dd);
                            if contextWide && bb>1,continue;end
                            if contextWide,bp=NMResultsViewerReportTools.emptyBackprojectionPlanEntry();end
                            one.PayloadSpec.classifierIndex = double(classifier.index);
                            one.PayloadSpec.featureContextId = ctx.contextId;
                            modalityIndex = ctx.modalityIndex;
                            if isfinite(modalityIndex), one.PayloadSpec.modalityIndex = double(modalityIndex); end
                            if ~isempty(bp.componentId)
                                one.PayloadSpec.backprojectionComponentId = bp.componentId;
                                one.PayloadSpec.componentIndex = double(bp.componentIndex);
                            else
                                one.PayloadSpec = NMResultsViewerReportTools.removeStructFields( ...
                                    one.PayloadSpec, {'backprojectionComponentId','componentIndex'});
                            end
                            one.Instance = NMResultsViewerReportTools.reportComponentInstance(ctx, bp, one.Id, classifier, one.Instance);
                            if ~contextWide
                                sourceContextId = probePayload.selectedFeatureContextId;
                                one.Options = NMResultsViewerReportTools.optionsForPlannedFeatureInstance( ...
                                    one.Options, ctx, bp, sourceContextId, sourceFeatureClassifierIndex, classifier.index);
                                one.Options = NMResultsViewerReportTools.mergeStructs(one.Options, ...
                                    struct('PlannedClassifierIndex',double(classifier.index), ...
                                    'PlannedClassifierLabel',classifier.label, ...
                                    'PlannedFeatureContextId',one.Instance.FeatureContextId, ...
                                    'PlannedBackprojectionComponentId',one.Instance.BackprojectionComponentId));
                            end
                            outCount = outCount + 1;
                            planned(outCount) = one;
                        end
                    end
                end
            end

            for ii=1:numel(fixedAfterFeature)
                outCount=outCount+1;
                planned(outCount)=fixedAfterFeature(ii);
            end

            reportSpec.Components = NMResultsViewerReportTools.reindexComponentSpecs(planned(1:outCount));
            reportSpec.Layout = NMResultsViewerReportTools.defaultReportLayout(outCount);
            reportSpec.PlanSummary = struct('requestedComponentCount',requestedCount, ...
                'expandedComponentCount',outCount,'classifierCount',numel(classifiers), ...
                'classifierIndices',[classifiers.index], ...
                'classifierLabels',{{classifiers.label}}, ...
                'modelPerformanceInstanceCount',performanceInstanceCount, ...
                'oocvSubgroupIndices',performanceGroupIndices, ...
                'oocvSubgroupLabels',{performanceGroupLabels}, ...
                'modelOptimizationInstanceCount',optimizationInstanceCount, ...
                'featureContextCount',totalContexts, ...
                'backprojectionInstanceCount',totalInstances, ...
                'classifierScope',classifierScope, ...
                'featureSourceScope',plan.FeatureSourceScope, ...
                'componentScope',plan.ComponentScope, ...
                'includeFusionOverview',plan.IncludeFusionOverview);
        end

        function [reportSpec,session] = planSelectedEvaluationSources(session,reportSpec)
            % Expand one analysis-local Model Performance selection using authoritative
            % result-source and per-source Scientific State component catalogues.
            % Other viewspaces retain their original CV-only source and are planned once.
            selectedSources=reportSpec.AnalysisPlans(1).EvaluationSourcePlan.SelectedSourceIds;
            raw=reportSpec.Components;
            performance=raw(strcmp({raw.Viewspace},'model_performance'));
            seqopt=raw(strcmp({raw.Id},'model_optimization.sequence_diagnostics'));
            other=raw(~strcmp({raw.Viewspace},'model_performance') & ...
                ~strcmp({raw.Id},'model_optimization.sequence_diagnostics'));
            if isempty(performance)&&isempty(seqopt)
                error('NMResultsViewerReportTools:MissingEvaluationReportComponent', ...
                    'Explicit evaluation-source export requires a Performance or SEQOPT diagnostic component.');
            end
            planned=NMResultsViewerReportTools.componentSpecTemplate([]);
            sourceSummaries=cell(1,numel(selectedSources));
            if ~isempty(performance)||~isempty(seqopt)
                if ~isempty(performance),base=performance(1);else,base=seqopt(1);end
                probe=NMResultsViewerReportTools.componentPayloadSpec(base,reportSpec,'classification');
                if isempty(performance),probe.resultType='classification';end
                catalogueSources=NMResultsViewerTools.sourcesForAnalysis( ...
                    session.CurrentNM,reportSpec.AnalysisIndex,probe.resultType);
                for ss=1:numel(selectedSources)
                    sourceId=selectedSources{ss};
                    hit=find(strcmp({catalogueSources.id},sourceId)&[catalogueSources.enabled],1,'first');
                    if isempty(hit)
                        error('NMResultsViewerReportTools:UnavailableEvaluationSource', ...
                            'Evaluation source %s is not available for this analysis and result family.',sourceId);
                    end
                    sourceSpec=probe;
                    sourceSpec.source=sourceId;
                    [sourcePayload,session]=NMResultsViewerReportTools.reportSessionPayload( ...
                        session,'model_performance',sourceSpec);
                    sourceState=NMResultsViewerScientificState.fromPayloads({sourcePayload},sourceSpec);
                    available=NMResultsViewerReportTools.modelPerformanceComponentsFromState( ...
                        sourceSpec,sourceState,1);
                    sourceComponents=[performance seqopt];
                    [isOOCV,~]=NMResultsViewerTools.parseOOCVSourceId(sourceId);
                    for ii=1:numel(sourceComponents)
                        one=sourceComponents(ii);
                        one.PayloadSpec.source=sourceId;
                        if strcmp(one.Id,'model_optimization.sequence_diagnostics')
                            sourceComponents(ii)=one;continue;
                        end
                        if isOOCV,one.PayloadSpec.oocvSubgroupIndex=1;end
                        match=find(strcmp({available.Id},one.Id),1,'first');
                        if isempty(match) || ~available(match).Enabled
                            one.Options.ReportCatalogueUnavailable=true;
                            if isempty(match)
                                one.Options.ReportCatalogueMissingReason='Component is not exposed for this evaluation source.';
                            else
                                one.Options.ReportCatalogueMissingReason=available(match).MissingReason;
                            end
                        elseif ~strcmp(sourceId,probe.source) && ...
                                ismember(one.Id,{'model_performance.model_permutation', ...
                                'model_performance.extra_label_permutation_gallery'})
                            one.Options=NMResultsViewerReportTools.clearModelPerformanceClassifierBoundOptions(one.Options);
                        end
                        sourceComponents(ii)=one;
                    end
                    local=reportSpec;
                    local.Source=sourceId;
                    local.Components=sourceComponents;
                    local.AnalysisPlans.EvaluationSourcePlan.Mode='current';
                    if ~isOOCV,local.AnalysisPlans.OOCVGroupPlan.Mode='current';end
                    [local,session]=NMResultsViewerReportTools.planReportSpec(session,local);
                    sourceSummaries{ss}=local.PlanSummary;
                    for ii=1:numel(local.Components)
                        one=local.Components(ii);
                        % Catalogue-unavailable entries do not traverse classifier binding;
                        % their component ID remains the authoritative output identity.
                        if isempty(one.Instance.Id),one.Instance.Id=one.Id;end
                        one.Instance.Id=sprintf('%s|source:%s',one.Instance.Id,sourceId);
                        one.Title=sprintf('%s | %s',one.Title,catalogueSources(hit).label);
                        planned(end+1)=one; %#ok<AGROW>
                    end
                end
            end
            if ~isempty(other)
                local=reportSpec;
                local.Components=other;
                local.AnalysisPlans.EvaluationSourcePlan.Mode='current';
                [local,session]=NMResultsViewerReportTools.planReportSpec(session,local);
                planned=[planned local.Components]; %#ok<AGROW>
            end
            reportSpec.Components=NMResultsViewerReportTools.reindexComponentSpecs(planned);
            reportSpec.Layout=NMResultsViewerReportTools.defaultReportLayout(numel(planned));
            reportSpec.PlanSummary=struct('scope','selected_evaluations', ...
                'evaluationSourceIds',{selectedSources},'sourceSummaries',{sourceSummaries}, ...
                'requestedComponentCount',numel(raw),'expandedComponentCount',numel(planned));
        end

        function index = reportComponentClassifierSeed(componentSpecs, reportSpec, defaultResultType)
            % reportComponentClassifierSeed  Resolve one viewspace's captured classifier index.
            index = NaN;
            if isempty(componentSpecs), return; end
            values = NaN(1,numel(componentSpecs));
            for ii=1:numel(componentSpecs)
                payloadSpec = NMResultsViewerReportTools.componentPayloadSpec( ...
                    componentSpecs(ii), reportSpec, defaultResultType);
                values(ii) = NMResultsViewerReportTools.structScalar(payloadSpec, ...
                    {'classifierIndex'}, NaN);
            end
            values = values(isfinite(values));
            if isempty(values), return; end
            if any(values < 1 | abs(values-round(values)) > eps(max(ones(size(values)),abs(values))))
                error('NMResultsViewerReportTools:InvalidComponentClassifierSelection', ...
                    'Selected components carry a non-positive or non-integer classifier index.');
            end
            distinct = unique(round(values),'stable');
            if numel(distinct) > 1
                error('NMResultsViewerReportTools:ConflictingComponentClassifierSelection', ...
                    'Selected components in one viewspace carry conflicting classifier indices [%s].', ...
                    strtrim(sprintf('%d ',distinct)));
            end
            index = double(distinct(1));
        end

        function classifiers = reportPlanBinaryClassifiers(NM, reportSpec, probeSpec)
            % reportPlanBinaryClassifiers  Resolve current, selected or all binary decompositions.
            plans = reportSpec.AnalysisPlans;
            pos = find([plans.AnalysisIndex] == reportSpec.AnalysisIndex,1,'first');
            if isempty(pos)
                error('NMResultsViewerReportTools:MissingAnalysisPlan', ...
                    'Report analysis %d has no canonical AnalysisPlans entry.',reportSpec.AnalysisIndex);
            end
            plan = plans(pos).FeatureInspectionPlan;
            scope = plan.ClassifierScope;
            catalogue = NMResultsViewerReportTools.binaryClassifierPlanCatalogue(NM, probeSpec);
            currentIndex = probeSpec.classifierIndex;
            if ~isfinite(currentIndex) || currentIndex < 1 || abs(currentIndex-round(currentIndex)) > eps(max(1,abs(currentIndex)))
                error('NMResultsViewerReportTools:InvalidCurrentClassifierIndex', ...
                    'The current classifier index must be a finite positive integer.');
            end
            currentIndex = round(currentIndex);
            switch scope
                case 'all_binary'
                    classifiers = catalogue;
                    if isempty(classifiers)
                        error('NMResultsViewerReportTools:NoBinaryDecompositions', ...
                            'All binary decompositions were requested, but the selected analysis exposes no BinClass results.');
                    end
                case 'selected'
                    requested = double(plan.SelectedClassifierIndices(:))';
                    if isempty(requested)
                        error('NMResultsViewerReportTools:SelectedClassifierIndicesRequired', ...
                            'ClassifierScope="selected" requires at least one SelectedClassifierIndices entry.');
                    end
                    if any(~isfinite(requested) | requested < 1 | abs(requested-round(requested)) > eps(max(ones(size(requested)),abs(requested))))
                        error('NMResultsViewerReportTools:InvalidSelectedClassifierIndices', ...
                            'SelectedClassifierIndices must contain finite positive integer BinClass indices.');
                    end
                    requested = unique(round(requested),'stable');
                    available = [catalogue.index];
                    missing = requested(~ismember(requested,available));
                    if ~isempty(missing)
                        error('NMResultsViewerReportTools:SelectedClassifierUnavailable', ...
                            'Selected binary decomposition index/indices [%s] are unavailable.', ...
                            strtrim(sprintf('%d ',missing)));
                    end
                    classifiers = catalogue(ismember(available,requested));
                case 'current'
                    requestedType = probeSpec.resultType;
                    isAggregateMultiClass = strcmp(requestedType,'multiclass');
                    label = sprintf('Classifier %d',currentIndex);
                    if ~isAggregateMultiClass && ~isempty(catalogue)
                        hit = find([catalogue.index] == currentIndex,1,'first');
                        if ~isempty(hit), label = catalogue(hit).label; end
                    end
                    if isAggregateMultiClass || isempty(catalogue) || ~any([catalogue.index] == currentIndex)
                        activeLabel = NMResultsViewerReportTools.reportMetadataText( ...
                            reportSpec,'ActiveMultiClassModeLabel','');
                        if isempty(activeLabel) && isAggregateMultiClass
                            activeLabel = 'Multi-group classification';
                        end
                        if ~isempty(activeLabel), label = activeLabel; end
                    end
                    classifiers = struct('index',double(currentIndex), ...
                        'label',label,'enabled',true);
                otherwise
                    error('NMResultsViewerReportTools:InvalidClassifierScope', ...
                        ['FeatureInspectionPlan.ClassifierScope must be "current", ' ...
                         '"selected" or "all_binary"; received "%s".'],scope);
            end
        end

        function spec = bindModelPerformanceClassifierSpec(spec, classifier, sourceClassifierIndex, forceBinary)
            % bindModelPerformanceClassifierSpec  Bind one performance component to a decomposition.
            sourceResultType = spec.PayloadSpec.resultType;
            spec.PayloadSpec.classifierIndex = double(classifier.index);
            if forceBinary
                spec.PayloadSpec.resultType = 'classification';
                spec.PayloadSpec = NMResultsViewerReportTools.removeStructFields( ...
                    spec.PayloadSpec, {'multiClassModeIndex'});
            end
            spec.Instance = NMResultsViewerReportTools.reportClassifierComponentInstance(spec.Id,classifier);
            spec.Options = NMResultsViewerReportTools.optionsForPlannedPerformanceInstance( ...
                spec.Options, sourceClassifierIndex, classifier.index, sourceResultType, forceBinary);
            spec.Options = NMResultsViewerReportTools.mergeStructs(spec.Options, ...
                struct('PlannedClassifierIndex',double(classifier.index), ...
                'PlannedClassifierLabel',classifier.label));
        end

        function spec = bindModelOptimizationClassifierSpec(spec, classifier)
            % bindModelOptimizationClassifierSpec  Bind one optimization component to a decomposition.
            spec.PayloadSpec.classifierIndex = double(classifier.index);
            spec.PayloadSpec.resultType = 'model_optimization';
            spec.PayloadSpec = NMResultsViewerReportTools.removeStructFields( ...
                spec.PayloadSpec, {'multiClassModeIndex'});
            spec.Instance = NMResultsViewerReportTools.reportClassifierComponentInstance( ...
                spec.Id,classifier);
            spec.Options = NMResultsViewerReportTools.mergeStructs(spec.Options, ...
                struct('PlannedClassifierIndex',double(classifier.index), ...
                'PlannedClassifierLabel',classifier.label));
        end

        function instance = reportClassifierComponentInstance(componentId, classifier)
            % reportClassifierComponentInstance  Build stable classifier identity for a report component.
            instance = NMResultsViewerReportTools.componentInstanceTemplate();
            instance.ClassifierIndex = double(classifier.index);
            instance.ClassifierLabel = classifier.label;
            instance.ClassifierId = sprintf('classifier:%d',round(classifier.index));
            instance.Id = sprintf('%s|classifier:%d',componentId,round(classifier.index));
        end

        function opts = optionsForPlannedPerformanceInstance(opts, sourceClassifierIndex, plannedClassifierIndex, sourceResultType, forceBinary)
            % optionsForPlannedPerformanceInstance  Reuse presentation but not payload-bound identities.
            sameClassifier = isfinite(double(sourceClassifierIndex)) && ...
                isfinite(double(plannedClassifierIndex)) && ...
                round(double(sourceClassifierIndex)) == round(double(plannedClassifierIndex));
            sourceIsBinary = strcmp(sourceResultType,'classification');
            samePayloadIdentity = sameClassifier && (~forceBinary || sourceIsBinary);
            if ~samePayloadIdentity
                opts = NMResultsViewerReportTools.clearModelPerformanceClassifierBoundOptions(opts);
            end
        end

        function opts = clearModelPerformanceClassifierBoundOptions(opts)
            % clearModelPerformanceClassifierBoundOptions  Clear permutation identities from another classifier.
            state = NMResultsViewerReportTools.safeField(opts,'ModelPermutationState',struct());
            if any(strcmp(fieldnames(state),'payload')), state.payload = []; end
            main = NMResultsViewerReportTools.safeField(state,'main',struct());
            main.comparisonId = '';
            state.main = main;
            gallery = NMResultsViewerReportTools.safeField(state,'extraLabelGallery',struct());
            gallery.comparisonIds = {};
            state.extraLabelGallery = gallery;
            focused = NMResultsViewerReportTools.safeField(state,'focusedDetail',struct());
            focused.visible = false;
            focused.comparisonId = '';
            state.focusedDetail = focused;
            opts.ModelPermutationState = state;
        end

        function spec = bindFeatureClassifierSpec(spec, classifier)
            % bindFeatureClassifierSpec  Bind one planned overview component to one decomposition.
            spec.PayloadSpec.classifierIndex = double(classifier.index);
            spec.Instance.ClassifierIndex = double(classifier.index);
            spec.Instance.ClassifierLabel = classifier.label;
            spec.Instance.ClassifierId = sprintf('classifier:%d',round(classifier.index));
            spec.Instance.Id = sprintf('%s|classifier:%d',spec.Instance.Id,round(classifier.index));
            spec.Options.PlannedClassifierIndex = double(classifier.index);
            spec.Options.PlannedClassifierLabel = classifier.label;
        end

        function spec = rebindPlannedFusionOverviewSpec(spec, probePayload, sourceClassifierIndex, plannedClassifierIndex)
            % rebindPlannedFusionOverviewSpec  Bind a fusion overview to one classifier payload.
            selectedContextId = probePayload.selectedFeatureContextId;
            selectedContext = probePayload.selectedFeatureContext;
            spec.PayloadSpec.classifierIndex = double(plannedClassifierIndex);
            if ~isempty(selectedContextId)
                spec.PayloadSpec.featureContextId = selectedContextId;
            else
                spec.PayloadSpec = NMResultsViewerReportTools.removeStructFields( ...
                    spec.PayloadSpec, {'featureContextId'});
            end
            spec.PayloadSpec = NMResultsViewerReportTools.removeStructFields( ...
                spec.PayloadSpec, {'backprojectionComponentId','componentIndex'});
            capturedViewState = NMResultsViewerReportTools.safeField( ...
                spec.Options,'BrowserFeatureInspectionViewState',struct());
            capturedContextId = NMResultsViewerReportTools.safeField( ...
                capturedViewState,'selectedFeatureContextId', ...
                NMResultsViewerReportTools.structText(spec.PayloadSpec,{'featureContextId'},''));
            sameClassifier = isfinite(double(sourceClassifierIndex)) && ...
                isfinite(double(plannedClassifierIndex)) && ...
                round(double(sourceClassifierIndex)) == round(double(plannedClassifierIndex));
            if ~sameClassifier
                spec.Options = NMResultsViewerReportTools.clearFeatureBoundOptions(spec.Options, false);
            end
            if ~isempty(capturedContextId) && ~strcmp(capturedContextId,selectedContextId)
                spec.Options = NMResultsViewerReportTools.clearFeatureBoundOptions(spec.Options, true);
            end
            viewState = NMResultsViewerReportTools.safeField( ...
                spec.Options,'BrowserFeatureInspectionViewState',struct());
            % nm2-allow: browser report presentation state boundary validates retained view-state transport.
            if ~isstruct(viewState), viewState = struct(); end
            viewState.classifierIndex = double(plannedClassifierIndex);
            viewState.selectedFeatureContextId = selectedContextId;
            viewState.selectedFeatureContext = selectedContext;
            viewState.contentKey = '';
            viewState.payloadKey = '';
            spec.Options.BrowserFeatureInspectionViewState = viewState;
            spec.Options.PlannedFeatureContextId = selectedContextId;
        end

        function overview = reportFusionOverviewSpecs(payload, payloadSpec, reportSpec, existing)
            % reportFusionOverviewSpecs  Resolve the complete available fusion overview in canonical order.
            ids = {'model_feature_inspection.modality_contribution', ...
                'model_feature_inspection.component_summary', ...
                'model_feature_inspection.component_modality_matrix'};
            labels = {'Modality contribution','Component statistics','Component × modality'};
            componentTypes = {'modality_contribution','component_summary','component_modality_matrix'};
            analysis = payload.componentAnalysis;
            componentRows = analysis.componentTable;
            modalityComponentRows = analysis.modalityComponentTable;
            available = [ ...
                NMResultsViewerReportTools.structArrayHasRows(analysis.modalityShareTable), ...
                NMResultsViewerReportTools.structArrayHasRows(componentRows) || NMResultsViewerReportTools.structArrayHasRows(modalityComponentRows), ...
                NMResultsViewerReportTools.structArrayHasRows(analysis.componentModalityTable)];
            tmpl = NMResultsViewerReportTools.componentSpecTemplate();
            buffer = repmat(tmpl,1,numel(ids));
            count = 0;
            for ii=1:numel(ids)
                hitExisting = find(strcmp({existing.Id},ids{ii}),1,'first');
                if ~isempty(hitExisting)
                    spec = existing(hitExisting);
                else
                    if ~available(ii), continue; end
                    spec = tmpl;
                    spec.Id = ids{ii};
                    spec.Title = labels{ii};
                    spec.Viewspace = 'model_feature_inspection';
                    spec.PayloadSpec = payloadSpec;
                    spec.Layout = NMResultsViewerReportTools.componentLayoutTemplate();
                    spec.Layout.Group = 'model_feature_inspection';
                    spec.Options = struct();
                    spec.Instance.ComponentType = componentTypes{ii};
                end
                if strcmp(ids{ii},'model_feature_inspection.component_summary')
                    resolvedOptions = NMResultsViewerReportTools.modelFeatureInspectionFusionPanelOptions( ...
                        spec.Options,NMResultsViewerReportTools.featureInspectionViewState(spec.Options).panels,'component_statistics');
                    requestedScope = NMResultsViewerReportTools.safeField(resolvedOptions,'ComponentStatsScope','');
                    if isempty(requestedScope) || strcmp(requestedScope,'auto')
                        if NMResultsViewerReportTools.structArrayHasRows(componentRows)
                            spec.Options.ComponentStatsScope = 'fusion_report';
                        elseif NMResultsViewerReportTools.structArrayHasRows(modalityComponentRows)
                            spec.Options.ComponentStatsScope = 'selected_context';
                            rowKeys = cell(1,numel(modalityComponentRows));
                            for rr=1:numel(modalityComponentRows)
                                rowKeys{rr}=NMResultsViewerReportTools.modelFeatureInspectionComponentRowSourceKey(modalityComponentRows(rr));
                            end
                            uniqueKeys = unique(rowKeys,'stable');
                            selectedContext = payload.selectedFeatureContext;
                            sourceKey = NMResultsViewerReportTools.modelFeatureInspectionPreferredReportSourceKey(uniqueKeys,selectedContext);
                            % nm2-allow: normalized component-analysis source resolution accepts the sole available source.
                            if isempty(sourceKey) && numel(uniqueKeys)==1, sourceKey=uniqueKeys{1}; end
                            if ~isempty(sourceKey), spec.Options.DrSourceKey=sourceKey; end
                        end
                    end
                end
                count = count + 1;
                buffer(count) = NMResultsViewerReportTools.normalizeFusionOverviewSpec(spec);
            end
            overview = buffer(1:count);
        end

        function opts = optionsForPlannedFeatureInstance(opts, ctx, bp, sourceContextId, sourceClassifierIndex, plannedClassifierIndex)
            % optionsForPlannedFeatureInstance  Rebind report state to one planned feature instance.
            sameClassifier = isfinite(double(sourceClassifierIndex)) && isfinite(double(plannedClassifierIndex)) && ...
                round(double(sourceClassifierIndex)) == round(double(plannedClassifierIndex));
            if ~sameClassifier
                opts = NMResultsViewerReportTools.clearFeatureBoundOptions(opts, false);
            end
            plannedContextId = ctx.contextId;
            sameContext = ~isempty(plannedContextId) && strcmp(plannedContextId,sourceContextId);
            if ~sameContext
                opts = NMResultsViewerReportTools.clearFeatureBoundOptions(opts, true);
            end
            viewState = NMResultsViewerReportTools.safeField(opts,'BrowserFeatureInspectionViewState',struct());
            % nm2-allow: browser report presentation state boundary validates retained view-state transport.
            if isstruct(viewState)
                viewState.classifierIndex = double(plannedClassifierIndex);
                viewState.selectedFeatureContextId = plannedContextId;
                viewState.contentKey = '';
                viewState.payloadKey = '';
                catalogue = NMResultsViewerReportTools.safeField(viewState,'availableFeatureContexts',struct([]));
                selected = struct('contextId',plannedContextId, ...
                    'selectionLabel',ctx.selectionLabel, ...
                    'modalityLabel',ctx.modalityLabel, ...
                    'isCombined',ctx.isCombined);
                % nm2-allow: browser report presentation state boundary accepts optional retained context catalogue.
                if isstruct(catalogue) && ~isempty(catalogue)
                    match = find(strcmp({catalogue.contextId},plannedContextId),1,'first');
                    if ~isempty(match), selected = catalogue(match); end
                end
                viewState.selectedFeatureContext = selected;
                viewState.selectedBackprojectionComponentId = bp.componentId;
                viewState.selectedBackprojectionComponentIndex = bp.componentIndex;
                viewState.selectedBackprojectionComponentColumn = bp.componentPosition;
                viewState.selectedBackprojectionComponentLabel = bp.selectionLabel;
                opts.BrowserFeatureInspectionViewState = viewState;
            end
        end

        function opts = clearFeatureBoundOptions(opts, clearFeatureIdentity)
            % Rebind captured presentation: invalidate classifier identity or feature-context identity.
            opts = NMResultsViewerReportTools.clearExplicitRelationIdentityAssertions(opts, clearFeatureIdentity);
            if clearFeatureIdentity
                topFields = {'FeatureIndexExpression','featureExpression','FeatureIndices','featureIndices', ...
                    'SubsetMode','subsetMode','AlternativeLabelsText','altLabelsText', ...
                    'AlternativeLabelsResolved','altLabelsResolved','DrSourceKey','drSourceKey', ...
                    'MatrixId','matrixId','RelationSourceScope','relationSourceScope','RelationId','relationId', ...
                    'SourceScope','sourceScope','SelectedRelationPatternId','selectedRelationPatternId', ...
                    'SelectedRelationPatternGraphIdentity','selectedRelationPatternGraphIdentity', ...
                    'SelectedPair','selectedPair','GraphRobustnessResult','graphRobustnessResult'};
                panelFields = {'featureExpression','featureIndices','subsetMode','altLabelsText', ...
                    'altLabelsResolved','altLabelsSource','drSourceKey','matrixId', ...
                    'selectedRelationPatternId','selectedRelationPatternGraphIdentity', ...
                    'selectedPair','graphRobustnessResult','graphRobustnessValidForCurrentGraph'};
                controlFields = {'featureExpressionText','resolvedFeatureIndices','subsetMode', ...
                    'alternativeLabelText','resolvedAlternativeLabels','drSourceKey'};
                relationFields = {'matrixId','selectedRelationPatternId','selectedRelationPatternGraphIdentity', ...
                    'selectedPair','graphRobustnessResult'};
            else
                topFields = {'MatrixId','matrixId','RelationSourceScope','relationSourceScope', ...
                    'RelationId','relationId','SourceScope','sourceScope', ...
                    'SelectedRelationPatternId','selectedRelationPatternId', ...
                    'SelectedRelationPatternGraphIdentity','selectedRelationPatternGraphIdentity', ...
                    'SelectedPair','selectedPair','GraphRobustnessResult','graphRobustnessResult'};
                panelFields = {'matrixId','sourceScope','relationId','selectedRelationPatternId', ...
                    'selectedRelationPatternGraphIdentity','selectedPair', ...
                    'graphRobustnessResult','graphRobustnessValidForCurrentGraph'};
                controlFields = {};
                relationFields = {'matrixId','sourceScope','relationId','selectedRelationPatternId', ...
                    'selectedRelationPatternGraphIdentity','selectedPair','graphRobustnessResult'};
            end
            opts = NMResultsViewerReportTools.removeStructFields(opts, topFields);
            viewState = NMResultsViewerReportTools.safeField(opts,'BrowserFeatureInspectionViewState',struct());
            panels = NMResultsViewerReportTools.safeField(viewState,'panels',struct());
            panelNames = fieldnames(panels);
            for ii=1:numel(panelNames)
                panel = NMResultsViewerReportTools.removeStructFields(panels.(panelNames{ii}), panelFields);
                controls = NMResultsViewerReportTools.safeField(panel,'controls',struct());
                if clearFeatureIdentity
                    controls = NMResultsViewerReportTools.removeStructFields(controls, controlFields);
                end
                relationControls = NMResultsViewerReportTools.safeField(controls,'relation',struct());
                controls.relation = NMResultsViewerReportTools.removeStructFields(relationControls, relationFields);
                panel.controls = controls;
                panels.(panelNames{ii}) = panel;
            end
            viewState.panels = panels;
            opts.BrowserFeatureInspectionViewState = viewState;
        end

        function opts = clearExplicitRelationIdentityAssertions(opts, clearFeatureIdentity)
            % clearExplicitRelationIdentityAssertions  Preserve relation presentation while clearing content IDs.
            relationFields = {'RelationState','relationState'};
            identityFields = {'matrixId','sourceScope','relationId'};
            if clearFeatureIdentity
                identityFields = [identityFields, {'featureIndexExpression','featureIndices', ...
                    'resolvedFeatureIndices','alternativeLabels','alternativeLabelsExpression', ...
                    'alternativeLabelSourceId','resolvedAlternativeLabels'}];
            end
            present = intersect(relationFields,fieldnames(opts),'stable');
            for ii=1:numel(present)
                fieldName = present{ii};
                opts.(fieldName) = NMResultsViewerReportTools.removeStructFields( ...
                    opts.(fieldName), identityFields);
            end
        end

        function s = removeStructFields(s, names)
            % removeStructFields  Remove only named optional fields from one contract struct.
            if isempty(s), return; end
            present = intersect(names,fieldnames(s),'stable');
            if ~isempty(present), s = rmfield(s,present); end
        end

        function spec = normalizeFusionOverviewSpec(spec)
            % normalizeFusionOverviewSpec  Mark one schema-2 fusion overview and enforce global automatic scope.
            spec.Instance.IsOverview = true;
            spec.Instance.Id = ['overview|' spec.Id];
            if strcmp(spec.Id,'model_feature_inspection.component_summary')
                resolvedOptions = NMResultsViewerReportTools.modelFeatureInspectionFusionPanelOptions( ...
                    spec.Options,NMResultsViewerReportTools.featureInspectionViewState(spec.Options).panels,'component_statistics');
                requestedScope = NMResultsViewerReportTools.safeField(resolvedOptions,'ComponentStatsScope','');
                if isempty(requestedScope) || strcmp(requestedScope,'auto')
                    spec.Options.ComponentStatsScope = 'fusion_report';
                end
            end
        end

        function reportSpec = orderPreparedReportComponents(reportSpec)
            % orderPreparedReportComponents  Apply the report-global prepared output order at the MATLAB build boundary.
            if isempty(reportSpec.Components), return; end
            requested = reportSpec.PresentationState.OutputOrder;
            if isempty(requested), return; end
            comps=reportSpec.Components;outputIds=cell(1,numel(comps));hasId=false(1,numel(comps));
            for ii=1:numel(comps)
                outputIds{ii}=NMResultsViewerReportTools.structText(comps(ii).Options,{'PresentationOutputId'},'');
                hasId(ii)=~isempty(outputIds{ii});
            end
            if ~any(hasId),return;end
            if ~all(hasId)
                error('NMResultsViewerReportTools:IncompletePreparedOutputOrder', ...
                    'Prepared report components must all carry PresentationOutputId when OutputOrder is present.');
            end
            % nm2-allow: prepared report ordering boundary validates unique browser-authored output identities.
            if numel(unique(outputIds))~=numel(outputIds)||numel(unique(requested))~=numel(requested)
                error('NMResultsViewerReportTools:DuplicatePreparedOutputOrder', ...
                    'Prepared report output identities and OutputOrder entries must be unique.');
            end
            [present,position]=ismember(outputIds,requested);
            % nm2-allow: prepared report ordering boundary validates complete browser-authored output identity coverage.
            if ~all(present)||numel(requested)~=numel(outputIds)||any(~ismember(requested,outputIds))
                error('NMResultsViewerReportTools:PreparedOutputOrderMismatch', ...
                    'Prepared report components do not match the declared OutputOrder. Re-plan the report before building it.');
            end
            [~,ord]=sort(position);
            isCross=strcmp({comps(ord).Viewspace},'cross_analysis');
            ord=[ord(~isCross) ord(isCross)];
            reportSpec.Components=NMResultsViewerReportTools.reindexComponentSpecs(comps(ord));
            reportSpec.PresentationState.OutputOrder=outputIds(ord);
            reportSpec.Layout.ComponentCount=numel(ord);
        end

        function comps = scientificOrderComponentSpecs(comps)
            % scientificOrderComponentSpecs  Apply stable section and overview ordering.
            if isempty(comps), return; end
            rank = zeros(1,numel(comps));
            subrank = zeros(1,numel(comps));
            overviewIds = {'model_feature_inspection.modality_contribution', ...
                'model_feature_inspection.component_summary', ...
                'model_feature_inspection.component_modality_matrix'};
            for ii=1:numel(comps)
                id = comps(ii).Id;
                viewspace = comps(ii).Viewspace;
                if strcmp(viewspace,'model_performance')
                    rank(ii)=1;
                elseif strcmp(viewspace,'model_optimization')
                    rank(ii)=2;
                elseif ismember(id,overviewIds)
                    rank(ii)=3;
                    subrank(ii)=find(strcmp(overviewIds,id),1,'first');
                elseif strcmp(viewspace,'model_feature_inspection')
                    rank(ii)=4;
                else
                    rank(ii)=5;
                end
                if subrank(ii)==0, subrank(ii)=comps(ii).Layout.Order; end
            end
            original = 1:numel(comps);
            [~,ord] = sortrows([rank(:) subrank(:) original(:)],[1 2 3]);
            comps = comps(ord);
        end

        function comps = reindexComponentSpecs(comps)
            % reindexComponentSpecs  Assign sequential layout order after planning.
            if isempty(comps), return; end
            for ii=1:numel(comps)
                comps(ii).Layout.Row = ii;
                comps(ii).Layout.Order = ii;
                comps(ii).Layout.Group = comps(ii).Viewspace;
            end
        end

        function contexts = reportPlanFeatureContexts(payload, plan)
            % reportPlanFeatureContexts  Resolve requested feature contexts from canonical catalogue ids.
            contexts = payload.featureContexts;
            if isempty(contexts), return; end
            contexts = contexts([contexts.enabled]);
            scope = plan.FeatureSourceScope;
            selectedId = payload.selectedFeatureContextId;
            switch scope
                case 'combined'
                    mask = [contexts.isCombined];
                case 'all_physical'
                    mask = ~[contexts.isCombined];
                case 'combined_and_all'
                    mask = true(1,numel(contexts));
                case 'selected'
                    requested = plan.SelectedFeatureContextIds;
                    availableIds = {contexts.contextId};
                    missing = requested(~ismember(requested, availableIds));
                    if ~isempty(missing)
                        error('NMResultsViewerReportTools:SelectedFeatureContextUnavailable', ...
                            'Selected feature-context identity/identities are unavailable or disabled: %s.', ...
                            strjoin(missing, ', '));
                    end
                    mask = ismember(availableIds,requested);
                case 'selected_modalities'
                    requested = double(plan.SelectedModalityIndices(:))';
                    available = [contexts.modalityIndex];
                    physical = ~[contexts.isCombined];
                    missing = requested(~ismember(requested,available(physical)));
                    if ~isempty(missing)
                        error('NMResultsViewerReportTools:NaturalModalityUnavailable', ...
                            'Requested modality index/indices [%s] are unavailable for the planned classifier.', ...
                            strtrim(sprintf('%d ',missing)));
                    end
                    mask = physical & ismember(available,requested);
                    if plan.IncludeCombinedFeatureContext
                        mask = mask | ~physical;
                    end
                case 'current'
                    mask = strcmp({contexts.contextId},selectedId);
                otherwise
                    error('NMResultsViewerReportTools:InvalidFeatureSourceScope', ...
                        'FeatureInspectionPlan.FeatureSourceScope contains unsupported value "%s".',scope);
            end
            contexts = contexts(mask);
            if isempty(contexts), return; end
            [~,ord] = sortrows([~[contexts.isCombined]' [contexts.visRowIndex]'],[1 2]);
            contexts = contexts(ord);
        end

        function components = reportPlanBackprojectionComponents(payload, plan, anchorComponentIndex)
            % reportPlanBackprojectionComponents  Resolve retained components for one feature context.
            components = payload.backprojectionComponents;
            if isempty(components), return; end
            components = components([components.enabled]);
            scope = plan.ComponentScope;
            selectedId = payload.selectedBackprojectionComponentId;
            switch scope
                case 'all_retained'
                    mask = true(1,numel(components));
                case 'selected'
                    requestedIndices = double(plan.SelectedBackprojectionComponentIndices(:))';
                    requestedIndices = unique(round(requestedIndices(isfinite(requestedIndices) & requestedIndices >= 1)),'stable');
                    if ~isempty(requestedIndices)
                        availableIndices = [components.componentIndex];
                        missing = requestedIndices(~ismember(requestedIndices,availableIndices));
                        if ~isempty(missing)
                            error('NMResultsViewerReportTools:SelectedComponentUnavailable', ...
                                'Selected component index/indices [%s] are not retained in feature context %s.', ...
                                strtrim(sprintf('%d ',missing)),payload.selectedFeatureContextId);
                        end
                        mask = ismember(availableIndices,requestedIndices);
                    else
                        requested = plan.SelectedBackprojectionComponentIds;
                        availableIds = {components.componentId};
                        missing = requested(~ismember(requested,availableIds));
                        if ~isempty(missing)
                            error('NMResultsViewerReportTools:SelectedComponentUnavailable', ...
                                'Selected component identity/identities are unavailable in feature context %s: %s.', ...
                                payload.selectedFeatureContextId, strjoin(missing, ', '));
                        end
                        mask = ismember(availableIds,requested);
                    end
                case 'current'
                    if isfinite(anchorComponentIndex)
                        originalIndices = [components.componentIndex];
                        mask = originalIndices == anchorComponentIndex;
                        if ~any(mask)
                            error('NMResultsViewerReportTools:CurrentComponentUnavailable', ...
                                'Backprojected component %d is not retained for %s.', ...
                                round(anchorComponentIndex), payload.selectedFeatureContext.selectionLabel);
                        end
                    else
                        mask = strcmp({components.componentId},selectedId);
                    end
                otherwise
                    error('NMResultsViewerReportTools:InvalidComponentScope', ...
                        'FeatureInspectionPlan.ComponentScope contains unsupported value "%s".',scope);
            end
            components = components(mask);
            if isempty(components), return; end
            [~,ord]=sort([components.componentPosition]);
            components=components(ord);
        end

        function bp = emptyBackprojectionPlanEntry()
            % emptyBackprojectionPlanEntry  Represent a context without component axis.
            bp = struct('componentId','','componentIndex',NaN,'componentPosition',NaN, ...
                'componentLabel','','selectionLabel','');
        end

        function instance = reportComponentInstance(ctx, bp, componentId, classifier, baseInstance)
            % reportComponentInstance  Build stable output identity for one planned instance while preserving structured component semantics.
            instance = NMResultsViewerReportTools.componentInstanceTemplate();
            semanticFields = {'ComponentType','MetricId','YMetricId','SupportDomain','RepresentationId','PresentationMode','PresentationArtifactRequired'};
            for ff=1:numel(semanticFields)
                field=semanticFields{ff};
                instance.(field)=baseInstance.(field);
            end
            instance.ClassifierIndex = classifier.index;
            instance.ClassifierLabel = classifier.label;
            if isfinite(instance.ClassifierIndex), instance.ClassifierId = sprintf('classifier:%d',round(instance.ClassifierIndex)); end
            instance.FeatureContextId = ctx.contextId;
            instance.FeatureContextLabel = ctx.selectionLabel;
            instance.FeatureKind = ctx.featureKind;
            instance.IsCombinedContext = ctx.isCombined;
            instance.BackprojectionComponentId = bp.componentId;
            instance.BackprojectionComponentLabel = bp.selectionLabel;
            instance.BackprojectionComponentIndex = bp.componentIndex;
            instance.RetainedComponentColumn = bp.componentPosition;
            instance.Id = sprintf('%s|classifier:%g|context:%s|component:%s', char(string(componentId)), instance.ClassifierIndex, instance.FeatureContextId, instance.BackprojectionComponentId);
        end

        function comps = normalizeComponentSpecs(raw, reportSpec)
            % normalizeComponentSpecs  Normalize requested report component structs.
            tmpl = NMResultsViewerReportTools.componentSpecTemplate();
            if ~isstruct(raw) || isempty(raw)
                comps = tmpl([]);
                return;
            end
            comps = repmat(tmpl, 1, numel(raw));
            for ii = 1:numel(raw)
                c = NMResultsViewerReportTools.copyMissingFields(raw(ii), tmpl);
                if isempty(c.Title), c.Title = NMResultsViewerReportTools.componentTitleFromId(c.Id); end
                if isempty(c.Viewspace)
                    error('NMResultsViewerReportTools:MissingComponentViewspace', ...
                        'Report component %s must declare Viewspace structurally; component Id is an opaque serialization identifier.',char(string(c.Id)));
                end
                if strcmp(char(string(c.Viewspace)),'model_feature_inspection')
                    inst=c.Instance;
                    if isempty(strtrim(char(string(NMResultsViewerReportTools.safeField(inst,'ComponentType','')))))
                        error('NMResultsViewerReportTools:MissingFeatureComponentIdentity', ...
                            'Feature Inspection component %s must declare Instance.ComponentType structurally.',char(string(c.Id)));
                    end
                end
                if ismember(c.Id,{'model_feature_inspection.correlation_matrix', ...
                        'model_feature_inspection.feature_network'})
                    c.Options=NMResultsViewerReportTools.copyMissingFields(c.Options, ...
                        NMResultsViewerReportTools.defaultFeatureRelationOptions());
                end
                isFractionatedDx=ismember(c.Id,{'model_feature_inspection.fractionated_individual', ...
                    'model_feature_inspection.fractionated_population', ...
                    'model_feature_inspection.fractionated_clusters'});
                if isFractionatedDx
                    switch c.Id
                        case 'model_feature_inspection.fractionated_individual'
                            defaults=NMResultsViewerReportTools.fractionatedIndividualOptionsTemplate();
                            unknownError='NMResultsViewerReportTools:UnknownFractionatedIndividualOption';
                            optionName='Individual Dx report';
                        case 'model_feature_inspection.fractionated_population'
                            defaults=NMResultsViewerReportTools.fractionatedPopulationOptionsTemplate();
                            unknownError='NMResultsViewerReportTools:UnknownFractionatedPopulationOption';
                            optionName='Population Profiles';
                        case 'model_feature_inspection.fractionated_clusters'
                            defaults=NMResultsViewerReportTools.fractionatedClusterOptionsTemplate();
                            unknownError='NMResultsViewerReportTools:UnknownFractionatedClusterOption';
                            optionName='Subject Clusters';
                    end
                    % PresentationOutputId belongs to report-global output ordering, not to a Dx component.
                    unknown=setdiff(fieldnames(c.Options),[fieldnames(defaults);{'PresentationOutputId'}]);
                    if ~isempty(unknown)
                        error(unknownError,'Unknown %s option(s): %s.',optionName,strjoin(unknown,', '));
                    end
                    c.Options=NMResultsViewerReportTools.copyMissingFields(c.Options,defaults);
                    c.Options.StateSource=validatestring(c.Options.StateSource,{'report','interactive'});
                    switch c.Id
                        case 'model_feature_inspection.fractionated_individual'
                            c.Options.ProfileSort=validatestring(c.Options.ProfileSort, ...
                                {'absolute_desc','absolute_asc','signed_desc','signed_asc','retained_asc','retained_desc'});
                            validateattributes(c.Options.MaxPlotComponents,{'numeric'}, ...
                                {'scalar','integer','>=',1,'<=',100});
                            validateattributes(c.Options.MaxSubjects,{'numeric'}, ...
                                {'scalar','integer','>=',0,'<=',100000});
                            validateattributes(c.Options.CaseId,{'char'},{});
                            c.Options.CaseId=strtrim(c.Options.CaseId);
                            if ~isempty(c.Options.CaseId)
                                validateattributes(c.Options.CaseId,{'char'},{'row'});
                            elseif strcmp(c.Options.StateSource,'interactive')
                                error('NMResultsViewerReportTools:UnresolvedInteractiveDxCase', ...
                                    'Interactive Individual Dx reporting requires a resolved Case ID.');
                            end
                        case 'model_feature_inspection.fractionated_population'
                            metrics={'concentration','effectiveSubjects','meanAbsoluteDx', ...
                                'positivePct','negativePct','zeroPct','observed','coveragePct'};
                            c.Options.Metric=validatestring(c.Options.Metric,metrics);
                            c.Options.SortBy=validatestring(c.Options.SortBy,[metrics {'index','component'}]);
                            validateattributes(c.Options.SortAscending,{'logical'},{'scalar'});
                            validateattributes(c.Options.MaxPlotComponents,{'numeric'}, ...
                                {'scalar','integer','>=',1,'<=',100});
                        case 'model_feature_inspection.fractionated_clusters'
                            c.Options.Mode=validatestring(c.Options.Mode,{'raw','relative'});
                            c.Options.Selection=validatestring(c.Options.Selection,{'fixed','auto'});
                            c.Options.Criterion=validatestring(c.Options.Criterion,{'silhouette','ari','pac','cophenetic'});
                            c.Options.ProfileMetric=validatestring(c.Options.ProfileMetric,{'signedMean','difference','absoluteMean'});
                            validateattributes([c.Options.ClusterCount,c.Options.MinClusters,c.Options.MaxClusters], ...
                                {'numeric'},{'vector','numel',3,'integer','>=',2,'<=',8});
                            if c.Options.MinClusters>c.Options.MaxClusters
                                error('NMResultsViewerReportTools:InvalidFractionatedClusterRange', ...
                                    'Minimum cluster count cannot exceed maximum cluster count.');
                            end
                            validateattributes(c.Options.BootstrapIterations,{'numeric'}, ...
                                {'scalar','integer','>=',4,'<=',100});
                            validateattributes(c.Options.MaxPlotComponents,{'numeric'}, ...
                                {'scalar','integer','>=',1,'<=',100});
                    end
                end
                if strcmp(c.Id,'model_optimization.sequence_diagnostics')
                    c.Options=NMResultsViewerReportTools.copyMissingFields(c.Options, ...
                        struct('CandidatePolicy','winner','CandidateIndex',NaN, ...
                        'MetricIds',{{'criterion','sens','spec'}},'Representation','plots_tables'));
                end
                if ismember(c.Id,{'model_performance.model_permutation', ...
                        'model_performance.extra_label_permutation_gallery'}) && ...
                        ~isfield(c.Options,'ModelPermutationState') % nm2-allow: report-only optional permutation presentation is completed once by the report recipe producer.
                    c.Options.ModelPermutationState = struct( ...
                        'display',struct('histogramBins',30,'showDensity',true,'showObserved',true), ...
                        'main',struct('comparisonId','','components',struct( ...
                            'histogram',struct('visible',true),'resultsTable',struct('visible',true))), ...
                        'extraLabelGallery',struct('comparisonIds',{{}},'columns',NaN, ...
                            'components',struct('histograms',struct('visible',true))), ...
                        'focusedDetail',struct('visible',false,'comparisonId',''));
                end
                if ismember(c.Id,{'model_performance.model_permutation', ...
                        'model_performance.extra_label_permutation_gallery'})
                    columns=c.Options.ModelPermutationState.extraLabelGallery.columns;
                    if isequal(columns,'auto')
                        c.Options.ModelPermutationState.extraLabelGallery.columns=NaN;
                    end
                end
                if strcmp(c.Viewspace,'model_feature_inspection') && ~isFractionatedDx
                    c.Options=NMResultsViewerReportTools.copyMissingFields(c.Options, ...
                        struct('BrowserFeatureInspectionViewState',struct()));
                end
                if ~isstruct(c.PayloadSpec), c.PayloadSpec = struct(); end
                if ~isfield(c.PayloadSpec,'analysisIndex')
                    c.PayloadSpec.analysisIndex = reportSpec.AnalysisIndex;
                end
                if ~isfield(c.PayloadSpec,'source')
                    c.PayloadSpec.source = reportSpec.Source;
                end
                if strcmp(c.Instance.Id,'')
                    c.PayloadSpec = NMResultsViewerReportTools.copyMissingFields(c.PayloadSpec, ...
                        struct('multiClassModeIndex',reportSpec.MultiClassModeIndex));
                end
                if ~isstruct(c.Layout), c.Layout = tmpl.Layout; end
                if ~isfield(c.Layout,'Order') || isempty(c.Layout.Order), c.Layout.Order = ii; end
                if ~isfield(c.Layout,'Row') || isempty(c.Layout.Row), c.Layout.Row = ii; end
                comps(ii) = c;
            end
        end

        function [component, session] = buildComponentWithSession(session, compSpec, reportSpec)
            % Purpose: Dispatch one requested report component through the request-scoped report build session.
            % Syntax: [component,session] = NMResultsViewerReportTools.buildComponentWithSession(session,compSpec,reportSpec)
            % Inputs: session owns the read-only/current NM and request caches; compSpec identifies the component; reportSpec supplies normalized report selectors.
            % Outputs: component is the normalized report component payload; session returns with any request-local cache/materialization updates.
            % Authority and flow: Dispatch is by explicit Viewspace; stable component Id values remain opaque serialization identifiers within each viewspace.
            % Scientific/state contract: This dispatcher does not compute metrics or infer scientific coordinates; each delegated builder owns its domain contract.
            % Invariants: Unknown Viewspace/component ids raise explicitly; request-scoped NM/cache state is not replaced by browser state.
            % Materialization and performance: Cost is only dispatch plus the selected delegated builder; no independent file/resource reads, scans, or large allocations are introduced here.
            % Resource declaration: This dispatcher itself reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; delegated component builders retain their documented resource costs. Explicit report-build path, not a retained interactive renderer path.
            % Failure semantics: Unknown Viewspace/component ids raise explicitly; delegated exceptions follow their existing explicit failure semantics. A browser-declared catalogue-unavailable request returns an unavailable component with its exact catalogue reason without scientific materialization.
            % Side effects: Mutates only the request-local session value returned to the caller; caller NM is not mutated.
            % Consumers and dependencies: buildReport; cross-analysis, performance, optimization and Feature Inspection builders.
            component = NMResultsViewerReportTools.reportComponentTemplate();
            component.Id = compSpec.Id;
            component.Title = compSpec.Title;
            component.Viewspace = compSpec.Viewspace;
            component.Layout = compSpec.Layout;
            component.Instance = compSpec.Instance;
            payloadSpecForIdentity = compSpec.PayloadSpec;
            if strcmp(compSpec.Viewspace,'cross_analysis')
                analysisIndexForIdentity=NaN;
            else
                analysisIndexForIdentity=payloadSpecForIdentity.analysisIndex;
            end
            component.Metadata = struct('SchemaVersion',2,'Source','NMResultsViewerReportTools.buildComponentWithSession', ...
                'AnalysisIndex',analysisIndexForIdentity);
            requestOptions=compSpec.Options;
            if NMResultsViewerReportTools.structLogical(requestOptions,{'ReportCatalogueUnavailable'},false)
                component.Options=requestOptions;
                component.Status='unavailable';
                component.RenderStatus='unavailable';
                component.MissingReason=NMResultsViewerReportTools.structText(requestOptions, ...
                    {'ReportCatalogueMissingReason'},'The requested component is unavailable for this analysis.');
                return;
            end
            id = char(string(compSpec.Id));
            viewspace = lower(strtrim(char(string(compSpec.Viewspace))));
            switch viewspace
                case 'cross_analysis'
                    [component, session] = NMResultsViewerReportTools.buildCrossAnalysisComponentWithSession(session, compSpec, reportSpec, component);
                case 'model_optimization'
                    [component, session] = NMResultsViewerReportTools.buildModelOptimizationComponentWithSession(session, compSpec, reportSpec, component);
                case 'model_performance'
                    [component, session] = NMResultsViewerReportTools.buildModelPerformanceComponentWithSession(session, compSpec, reportSpec, component);
                case 'model_feature_inspection'
                    [component, session] = NMResultsViewerReportTools.buildModelFeatureInspectionComponentWithSession(session, compSpec, reportSpec, component);
                otherwise
                    error('NMResultsViewerReportTools:UnknownComponentViewspace', ...
                        'Report component %s declares unsupported Viewspace %s.',id,viewspace);
            end
        end

        function [component,session] = buildCrossAnalysisComponentWithSession(session,compSpec,reportSpec,component)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Build one set-level Cross-analysis Report Builder component through the canonical Cross-analysis artefact authorities.
            % Syntax: [component,session] = NMResultsViewerReportTools.buildCrossAnalysisComponentWithSession(session,compSpec,reportSpec,component)
            % Inputs: Request-scoped report session, component/report specifications and initialized component.
            % Outputs: Performance Table, Statistical Comparison or Visual Comparison component with canonical payload provenance, numerical tables and optional plot payload.
            % Authority and flow: Dispatches by component id to NMResultsViewerCrossAnalysisTools.performanceTable/statisticalComparison/visualComparison exactly once; Report Builder contains no performance-metric, Wilcoxon, Quade, FDR, pairwise-delta, CI or CV-equivalence implementation.
            % Scientific/state contract: Statistical report tables/plots are copied from cross_analysis.statistical_comparison; performance tables from cross_analysis.performance_table; descriptive aggregate metric plots/tables from cross_analysis.visual_comparison. The single adaptive Report Builder does not create parallel scientific artefacts.
            % Invariants: Explicit analysisIndices are mandatory; numeric spreadsheet tables and HTML/PDF plots originate from the same built artefact.
            % Materialization and performance: Explicit report-build action; compact performance/optimization materialization only through canonical authorities, then O(table/plot payload) copying. No new files/XML/atlas/annotation/mesh resources or feature-scale arrays.
            % Resource declaration: Reads no files directly, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays; delegated Cross-analysis authorities retain their documented costs.
            % Failure semantics: Missing analysisIndices, unknown Cross-analysis ids or unavailable canonical artefacts yield Status=unavailable; no fallback statistic/table writer is used.
            % Side effects: Mutates only returned request-local component/session values; caller NM is not mutated.
            % Consumers and dependencies: buildComponentWithSession, HTML/PDF and spreadsheet report exporters, renderCrossAnalysisComponentHtml.
            component.Options=compSpec.Options;
            payloadSpec=NMResultsViewerReportTools.componentPayloadSpec(compSpec,reportSpec,'comparison');payloadSpec.resultType='comparison';
            if ~isfield(payloadSpec,'analysisIndices')||isempty(payloadSpec.analysisIndices)
                component.Status='unavailable';component.MissingReason='Cross-analysis report components require explicit analysisIndices.';return;
            end
            id=char(string(compSpec.Id));
            try
            switch id
                case 'cross_analysis.performance_table'
                    payload=NMResultsViewerCrossAnalysisTools.performanceTable(session.CurrentNM,payloadSpec);
                    component.Payload=struct('kind','cross_analysis.performance_table','selectedAnalysisIndices',payload.selectedAnalysisIndices, ...
                        'selectedSource',payload.selectedSource,'scientificAnnotations',payload.scientificAnnotations, ...
                        'scientificDirectory',payload.scientificDirectory,'scientificState',payload.scientificState, ...
                        'warnings',{payload.warnings},'message',payload.message);
                    component.Tables=struct('performanceTable',{payload.tableCells},'performanceLong',payload.rows);component.PlotPayload=struct();
                    ok=logical(payload.ok)&&~isempty(component.Tables.performanceTable);
                case 'cross_analysis.statistical_comparison'
                    payload=NMResultsViewerCrossAnalysisTools.statisticalComparison(session.CurrentNM,payloadSpec);
                    component.Payload=struct('kind','cross_analysis.statistical_comparison','selectedAnalysisIndices',payload.selectedAnalysisIndices,'optimizationCriterion',payload.optimizationCriterion, ...
                        'testType',payload.testType,'referenceAnalysisIndex',payload.referenceAnalysisIndex,'cvCompatible',payload.cvCompatible,'matchedCV2',payload.matchedCV2, ...
                        'inference',payload.inference,'scientificAnnotations',payload.scientificAnnotations,'scientificDirectory',payload.scientificDirectory,'scientificState',payload.scientificState,'message',payload.message);
                    component.Tables=payload.tables;component.PlotPayload=payload.plotPayload;ok=logical(payload.ok);
                case 'cross_analysis.synth_overview'
                    payload=NMResultsViewerCrossAnalysisTools.synthOverview(session.CurrentNM, ...
                        payloadSpec.synthExperimentIndex,payloadSpec.synthSelection);
                    cells=cell(numel(payload.rows)+1,4);
                    if strcmp(payload.mode,'fully_synthetic')
                        cells(1,:)={'Sample N','Combination','Repetition','Criterion value'};
                        for jj=1:numel(payload.rows)
                            r=payload.rows(jj);
                            cells(jj+1,:)={r.sampleSize,r.combinationIndex,r.repetitionIndex,r.value};
                        end
                    else
                        cells(1,:)={'Total N','Permutation','Analysis','Criterion value'};
                        for jj=1:numel(payload.rows)
                            r=payload.rows(jj);
                            cells(jj+1,:)={r.sampleSize,r.permutation,r.analysisIndex,r.value};
                        end
                    end
                    component.Payload=payload;
                    component.Tables=struct('learningCurve',{cells});
                    component.PlotPayload=payload.plotPayload;
                    ok=payload.ok;
                case 'cross_analysis.visual_comparison'
                    payload=NMResultsViewerCrossAnalysisTools.visualComparison(session.CurrentNM,payloadSpec);
                    component.Payload=struct('kind','cross_analysis.visual_comparison','requestedAnalysisIndices',payload.requestedAnalysisIndices,'selectedAnalysisIndices',payload.selectedAnalysisIndices,'source',payload.source, ...
                        'targetIndex',payload.targetIndex,'modelSource',payload.modelSource,'classifierIndex',payload.classifierIndex,'multiClassModeIndex',payload.multiClassModeIndex, ...
                        'contextMode',payload.contextMode,'analysisContexts',payload.analysisContexts, ...
                        'excludedAnalyses',payload.excludedAnalyses,'cvCompatibilityRequired',payload.cvCompatibilityRequired,'cvGroups',payload.cvGroups,'selectedMetricIds',{payload.selectedMetricIds}, ...
                        'scientificAnnotations',payload.scientificAnnotations,'scientificDirectory',payload.scientificDirectory,'scientificState',payload.scientificState,'message',payload.message);
                    component.Tables=payload.tables;component.PlotPayload=payload.plotPayload;component.Warnings=payload.warnings;ok=logical(payload.ok);
                otherwise
                    error('NMResultsViewerReportTools:UnknownCrossAnalysisComponentId', ...
                        'Unknown Cross-analysis report component id "%s".',id);
            end
            catch ME
                if startsWith(char(string(ME.identifier)),'NMResultsViewerCrossAnalysisTools:')
                    component.Status='unavailable';component.MissingReason=ME.message;component.Warnings={sprintf('%s could not be materialized for this heterogeneous report scope.',component.Title)};return;
                end
                rethrow(ME);
            end
            if ok,component.Status='ok';component.MissingReason='';else,component.Status='unavailable';component.MissingReason=payload.message;end
        end

        function [component, session] = buildModelPerformanceComponentWithSession(session, compSpec, reportSpec, component)
            % buildModelPerformanceComponentWithSession  Build one API-backed model-performance report component.
            %
            % The component uses NMResultsViewerTools.getPayload as the single source
            % of scientific model-performance state. It returns component-specific
            % subpayloads and table-ready fields without inspecting browser DOM state
            % or recomputing result-viewer metrics.
            component.Options = compSpec.Options;
            payloadSpec = NMResultsViewerReportTools.componentPayloadSpec(compSpec, reportSpec, 'classification');
            requestedType = lower(strtrim(char(string(NMResultsViewerReportTools.structText(payloadSpec, {'resultType','ResultType'}, '')))));
            switch requestedType
                case {'regression','regr'}
                    payloadSpec.resultType = 'regression';
                case {'multiclass','multi_class','multi-class'}
                    payloadSpec.resultType = 'multiclass';
                case {'classification','binclass'}
                    payloadSpec.resultType = 'classification';
                otherwise
                    payloadSpec.resultType = NMResultsViewerTools.defaultPerformanceResultType(session.CurrentNM, payloadSpec.analysisIndex);
            end
            [payload, session] = NMResultsViewerReportTools.reportSessionPayload(session, 'model_performance', payloadSpec);
            component.Payload = struct('kind',payload.kind, ...
                'analysisIndex',payload.analysisIndex, ...
                'classifierIndex',payload.classifierIndex, ...
                'targetIndex',payload.targetIndex, ...
                'message',payload.message, ...
                'context',NMResultsViewerReportTools.safeField(payload,'context',struct()), ...
                'source',NMResultsViewerReportTools.safeField(payload,'selectedSource',''));
            component.Tables = struct();
            component.PlotPayload = struct();

            if ~(isstruct(payload) && isfield(payload,'ok') && logical(payload.ok))
                component.Status = 'unavailable';
                component.MissingReason = NMResultsViewerReportTools.payloadMessage(payload, 'Model-performance payload is unavailable.');
                return;
            end

            id = char(string(compSpec.Id));
            switch id
                case 'model_performance.summary'
                    component.Payload.summaryRows = payload.summaryRows;
                    component.Payload.multiClassTables = NMResultsViewerReportTools.safeField(payload,'multiClassTables',struct());
                    component.Tables.summaryRows = payload.summaryRows;
                    component.Status = NMResultsViewerReportTools.statusForPayloadFields(payload, {'summaryRows','multiClassTables'});
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No model-performance summary rows are available.');
                case 'model_performance.primary_plot'
                    component.PlotPayload.classPlot = payload.classPlot;
                    component.PlotPayload.regressionPlot = payload.regressionPlot;
                    component.PlotPayload.multiClassPlot = payload.multiClassPlot;
                    component.Status = NMResultsViewerReportTools.statusForPayloadFields(payload, {'classPlot','regressionPlot','multiClassPlot'});
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No primary model-performance plot payload is available.');
                case 'model_performance.confusion_matrix'
                    component.Payload.confusion = payload.confusion;
                    component.Tables.confusionCells = NMResultsViewerReportTools.confusionCellRows(component.Payload.confusion);
                    component.Status = NMResultsViewerReportTools.statusForPayloadFields(payload, {'confusion'});
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No confusion-matrix payload is available.');
                case 'model_performance.roc'
                    component.PlotPayload.roc = payload.roc;
                    component.Status = NMResultsViewerReportTools.statusForPayloadFields(payload, {'roc'});
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No ROC payload is available.');
                case 'model_performance.probability_distribution'
                    component.PlotPayload.pies = payload.pies;
                    component.Payload.scoreColumns = NMResultsViewerReportTools.safeField(payload,'scoreColumns',[]);
                    component.Payload.scoreRows = payload.scoreRows;
                    component.Payload.multiClassSummaryVisuals = NMResultsViewerReportTools.safeField(payload,'multiClassSummaryVisuals',struct());
                    component.Status = NMResultsViewerReportTools.statusForPayloadFields(payload, {'pies','scoreColumns','scoreRows','multiClassSummaryVisuals'});
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No probability or score-distribution payload is available.');
                case 'model_performance.calibration'
                    [actionPayload, session] = NMResultsViewerReportTools.reportSessionActionPayload(session, payloadSpec, compSpec, 'calibration');
                    component.Payload.calibration = actionPayload.calibration;
                    component.Payload.message = actionPayload.message;
                    component.Payload.method = actionPayload.method;
                    component.Payload.methodLabel = actionPayload.methodLabel;
                    component.Status = NMResultsViewerReportTools.statusForPayloadFields(actionPayload, {'calibration'});
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, NMResultsViewerReportTools.payloadMessage(actionPayload, 'Calibration action payload could not be generated for the selected context.'));
                case 'model_performance.dca'
                    [actionPayload, session] = NMResultsViewerReportTools.reportSessionActionPayload(session, payloadSpec, compSpec, 'dca');
                    component.Payload.dca = actionPayload.dca;
                    component.Payload.message = actionPayload.message;
                    component.Payload.method = actionPayload.method;
                    component.Payload.methodLabel = actionPayload.methodLabel;
                    component.Status = NMResultsViewerReportTools.statusForPayloadFields(actionPayload, {'dca'});
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, NMResultsViewerReportTools.payloadMessage(actionPayload, 'Decision-curve action payload could not be generated for the selected context.'));
                case 'model_performance.model_permutation'
                    mp = payload.modelPermutation;
                    rows = mp.rows;
                    if isempty(rows)
                        aIdx = payloadSpec.analysisIndex;
                        tIdx = payloadSpec.targetIndex;
                        cIdx = payloadSpec.classifierIndex;
                        mp = NMResultsViewerTools.modelPerformancePermutationPayload(session.CurrentNM, aIdx, tIdx, cIdx);
                        rows = mp.rows;
                    end
                    component.Payload.modelPermutation = mp;
                    component.PlotPayload.modelPermutation = mp;
                    component.Tables.modelPermutation = NMResultsViewerReportTools.modelPermutationSummaryRows(rows);
                    primaryRows = NMResultsViewerReportTools.modelPermutationRowsByRole(rows, false);
                    component.Status = NMResultsViewerReportTools.statusForRows(primaryRows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No primary model-permutation histogram payload is available.');
                case 'model_performance.extra_label_permutation_gallery'
                    mp = payload.modelPermutation;
                    rows = mp.rows;
                    if isempty(rows)
                        aIdx = payloadSpec.analysisIndex;
                        tIdx = payloadSpec.targetIndex;
                        cIdx = payloadSpec.classifierIndex;
                        mp = NMResultsViewerTools.modelPerformancePermutationPayload(session.CurrentNM, aIdx, tIdx, cIdx);
                        rows = mp.rows;
                    end
                    extraRows = NMResultsViewerReportTools.modelPermutationRowsByRole(rows, true);
                    component.Payload.modelPermutation = mp;
                    component.PlotPayload.modelPermutation = mp;
                    component.Tables.extraLabelPermutation = NMResultsViewerReportTools.modelPermutationSummaryRows(extraRows);
                    component.Status = NMResultsViewerReportTools.statusForRows(extraRows);
                    component.MissingReason = NMResultsViewerReportTools.reasonIfUnavailable(component.Status, 'No alternative-label permutation histograms are available.');
                case 'model_performance.payload'
                    component.Payload = payload;
                    component.PlotPayload = payload;
                    component.Status = 'ok';
                otherwise
                    error('NMResultsViewerReportTools:UnknownModelPerformanceComponentId', ...
                        'Unknown model-performance report component id "%s".',id);
            end
        end


        function rows = confusionCellRows(confusion)
            % confusionCellRows  Convert a confusion payload into CSV-safe long rows.
            tmpl = struct('observedClass','','predictedClass','','count',NaN,'rowPercent',NaN);
            rows = tmpl([]);
            if ~isstruct(confusion) || ~isfield(confusion,'matrix') || isempty(confusion.matrix), return; end
            M = NMResultsViewerReportTools.numericMatrixFromPayloadValues(confusion.matrix);
            if isempty(M), return; end
            K = min(size(M,1), size(M,2));
            P = [];
            if isfield(confusion,'percentMatrix')
                P = NMResultsViewerReportTools.numericMatrixFromPayloadValues(confusion.percentMatrix);
            end
            if isempty(P) || size(P,1) < K || size(P,2) < K
                P = zeros(K,K);
                rs = sum(M(1:K,1:K),2);
                for rr=1:K, if rs(rr) > 0, P(rr,:) = M(rr,1:K) ./ rs(rr) .* 100; end, end
            end
            labels = NMResultsViewerReportTools.safeCellstr(confusion.labels);
            for kk=(numel(labels)+1):K, labels{kk} = sprintf('Class %d', kk); end %#ok<AGROW>
            rows = repmat(tmpl, 1, K*K);
            idx = 0;
            for rr=1:K
                for cc=1:K
                    idx = idx + 1;
                    rows(idx).observedClass = labels{rr};
                    rows(idx).predictedClass = labels{cc};
                    rows(idx).count = double(M(rr,cc));
                    rows(idx).rowPercent = double(P(rr,cc));
                end
            end
        end

        function status = statusForPayloadFields(payload, fields)
            % statusForPayloadFields  Return ok/unavailable for component payload fields.
            if NMResultsViewerReportTools.payloadHasAny(payload, fields)
                status = 'ok';
            else
                status = 'unavailable';
            end
        end

        function reason = reasonIfUnavailable(status, reasonText)
            % reasonIfUnavailable  Emit an explicit missing reason for unavailable components.
            if strcmpi(char(string(status)), 'ok')
                reason = '';
            else
                reason = reasonText;
            end
        end

        function [component, session] = buildModelOptimizationComponentWithSession(session, compSpec, reportSpec, component)
            % buildModelOptimizationComponentWithSession  Build one optimization component using the shared payload cache.
            component.Options=compSpec.Options;
            payloadSpec = NMResultsViewerReportTools.componentPayloadSpec(compSpec, reportSpec, 'model_optimization');
            [optPayload, session] = NMResultsViewerReportTools.reportSessionPayload(session, 'model_optimization', payloadSpec);
            component.Payload = struct('Context',optPayload.context, ...
                'SelectedModelSource',optPayload.selectedModelSource);
            id = char(string(compSpec.Id));
            switch id
                case 'model_optimization.selected_metric'
                    component = NMResultsViewerReportTools.componentSelectedMetric(component, optPayload, compSpec);
                case 'model_optimization.cv_partitions'
                    component = NMResultsViewerReportTools.componentCvPartitions(component, optPayload);
                case 'model_optimization.metric_dashboard'
                    component = NMResultsViewerReportTools.componentMetricDashboard(component, optPayload);
                case 'model_optimization.sequence_diagnostics'
                    component = NMResultsViewerReportTools.componentSeqoptDiagnostics(component,optPayload,compSpec);
                case 'model_optimization.parameter_surface'
                    component = NMResultsViewerReportTools.componentParameterSurface(component, optPayload, compSpec);
                case 'model_optimization.scatter_comparison'
                    component = NMResultsViewerReportTools.componentScatterComparison(component, optPayload, compSpec, false);
                case 'model_optimization.pareto_summary'
                    component = NMResultsViewerReportTools.componentScatterComparison(component, optPayload, compSpec, true);
                case 'model_optimization.metric_registry'
                    component = NMResultsViewerReportTools.componentMetricRegistry(component, optPayload);
                case 'model_optimization.parameter_grid'
                    component = NMResultsViewerReportTools.componentParameterGrid(component, optPayload);
                otherwise
                    error('NMResultsViewerReportTools:UnknownModelOptimizationComponentId', ...
                        'Unknown model-optimization report component id "%s".',id);
            end
        end

        function payloadSpec = componentPayloadSpec(compSpec, reportSpec, resultType)
            % componentPayloadSpec  Merge component and report-level payload defaults.
            payloadSpec = compSpec.PayloadSpec;
            if ~isstruct(payloadSpec), payloadSpec = struct(); end
            if ~isfield(payloadSpec,'analysisIndex'), payloadSpec.analysisIndex = reportSpec.AnalysisIndex; end
            if ~isfield(payloadSpec,'source'), payloadSpec.source = reportSpec.Source; end
            if ~isfield(payloadSpec,'resultType'), payloadSpec.resultType = resultType; end
            if isstruct(compSpec) && isfield(compSpec,'Options') && isstruct(compSpec.Options)
                opts = compSpec.Options;
                if isfield(opts,'maxFeatures') && ~isfield(payloadSpec,'maxFeatures'), payloadSpec.maxFeatures = opts.maxFeatures; end
                if isfield(opts,'MaxFeatures') && ~isfield(payloadSpec,'maxFeatures'), payloadSpec.maxFeatures = opts.MaxFeatures; end
            end
        end

        function component = componentSeqoptDiagnostics(component,payload,compSpec)
            % Consume the existing normalized SEQOPT records; never reread GDdims or OOCV.
            D=payload.sequenceDiagnostics;
            opts=compSpec.Options;
            choices=D.candidates;
            switch opts.CandidatePolicy
                case 'winner', candidate=choices.winner;
                case 'most_selected', candidate=choices.mostSelected;
                case 'least_complex', candidate=choices.leastComplex;
                case {'current','explicit'}, candidate=opts.CandidateIndex;
                otherwise
                    error('NMResultsViewerReportTools:InvalidSeqoptCandidatePolicy', ...
                        'Unknown SEQOPT candidate policy: %s.',opts.CandidatePolicy);
            end
            if ~isscalar(candidate)||~isfinite(candidate)||candidate<1||candidate>payload.grid.nCombinations||candidate~=round(candidate)
                error('NMResultsViewerReportTools:UnavailableSeqoptCandidate','Selected SEQOPT candidate is not available.');
            end
            cvRecords=D.records(strcmp({D.records.scope},'CV2'));
            hit=find([cvRecords.combination]==candidate,1);
            if isempty(hit)
                error('NMResultsViewerReportTools:MissingSeqoptCV2Record','Selected grid row has no SEQOPT sequence diagnostics.');
            end
            cv=cvRecords(hit);
            source=compSpec.PayloadSpec.source;
            if strcmp(source,'cv')
                record=cv;
            else
                [isOOCV,cohort]=NMResultsViewerTools.parseOOCVSourceId(source);
                if ~isOOCV
                    error('NMResultsViewerReportTools:InvalidSeqoptSource','SEQOPT diagnostics require CV2 or an OOCV source.');
                end
                matches=D.records(strcmp({D.records.scope},'OOCV') & [D.records.cohort]==cohort);
                same=arrayfun(@(r)isequal(r.sequenceCols,cv.sequenceCols),matches);
                if ~any(same)
                    component.Status='unavailable';
                    component.MissingReason='No OOCV applied-model summary matches the selected candidate sequence.';
                    return;
                end
                record=matches(find(same,1));
            end
            ids=opts.MetricIds;
            if isempty(ids),error('NMResultsViewerReportTools:MissingSeqoptMetrics','Select at least one SEQOPT diagnostic metric.');end
            allowed=[{'criterion'} {D.metrics.id}];
            % nm2-allow: User-selected diagnostic metric IDs must be unique and belong to the normalized SEQOPT metric catalogue.
            if numel(unique(ids))~=numel(ids)||~all(ismember(ids,allowed))
                error('NMResultsViewerReportTools:InvalidSeqoptMetric','Unknown or duplicate SEQOPT diagnostic metric selection.');
            end
            template=struct('metricId','','metricLabel','','group','','unit','', ...
                'source','','candidateIndex',candidate,'candidateParameters',payload.grid.parameterRows(candidate).tooltip, ...
                'sequence',strjoin(record.sourceNames,' -> '),'nModels',record.nModels, ...
                'nPartitions',record.nPartitions,'stage',0,'sourceName','','mean',NaN,'sd',NaN);
            rows=repmat(template,1,0);
            for m=1:numel(ids)
                id=ids{m};
                if strcmp(id,'criterion')
                    if ~strcmp(source,'cv'),continue;end % No OOCV grid-row criterion exists.
                    measure=payload.metrics(strcmp({payload.metrics.id},'sequence_node_performance'));
                    if ~isscalar(measure),error('NMResultsViewerReportTools:MissingSeqoptCriterion','CV2 stage criterion metric is unavailable.');end
                    % nk_MLOptimizer pads CV2 performance to the configured maximum
                    % examination count; the diagnostic record owns the active prefix.
                    values=measure.values{candidate}(1:record.nStages);deviations=measure.sem{candidate}(1:record.nStages);
                    label=payload.optimizationCriterion.label;group='performance';unit=label;
                else
                    metric=D.metrics(strcmp({D.metrics.id},id));
                    values=record.values.(id);deviations=record.sd.(id);
                    label=metric.label;group=metric.group;unit=metric.unit;
                end
                % nm2-allow: The normalized SEQOPT writer produces means and SD on the same ordered examination-stage axis.
                if numel(values)~=record.nStages||numel(deviations)~=record.nStages
                    error('NMResultsViewerReportTools:InvalidSeqoptStageAxis','SEQOPT metric stage count disagrees with the selected sequence.');
                end
                for stage=1:record.nStages
                    row=template;row.metricId=id;row.metricLabel=label;row.group=group;row.unit=unit;
                    row.source=source;row.stage=stage;row.sourceName=record.sourceNames{stage};
                    row.mean=values(stage);row.sd=deviations(stage);
                    rows(end+1)=row; %#ok<AGROW>
                end
            end
            component.Tables.sequenceDiagnostics=rows;
            component.Payload.sequence=record;
            component.Payload.candidateIndex=candidate;
            component.Payload.candidateParameters=payload.grid.parameterRows(candidate).tooltip;
            component.Payload.aggregationScope=record.scope;
            if strcmp(source,'cv'),component.Payload.aggregationLabel='CV2 grid-row summary';
            else,component.Payload.aggregationLabel='OOCV selected-model sequence summary';end
            if isempty(rows)
                component.Status='unavailable';
                component.MissingReason='None of the selected metrics is defined for this evaluation source.';
            else
                component.Status='ok';
            end
        end

        function component = componentMetricRegistry(component, payload)
            % componentMetricRegistry  Attach metric-registry table rows.
            rows = NMResultsViewerReportTools.metricRegistryRows(payload.metrics);
            component.Tables.metricRegistry = rows;
            component.Payload.metrics = payload.metrics;
            if isempty(rows)
                component.Status = 'unavailable';
                component.MissingReason = 'No available optimization metrics were detected.';
            else
                component.Status = 'ok';
            end
        end

        function component = componentParameterGrid(component, payload)
            % componentParameterGrid  Attach parameter-grid rows.
            rows = NMResultsViewerReportTools.parameterGridRows(payload.grid);
            component.Tables.parameterGrid = rows;
            component.Payload.grid = payload.grid;
            if isempty(rows)
                component.Status = 'unavailable';
                component.MissingReason = 'No parameter-grid or META row metadata are available.';
            else
                component.Status = 'ok';
            end
        end

        function component = componentSelectedMetric(component, payload, compSpec)
            % componentSelectedMetric  Attach one selected optimization metric.
            metric = NMResultsViewerReportTools.selectMetric(payload, compSpec, '');
            if isempty(metric)
                component.Status = 'unavailable';
                component.MissingReason = 'No available optimization metric could be selected.';
                return;
            end
            component.Payload.metric = metric;
            component.Tables.metricValues = NMResultsViewerReportTools.metricValueRows(metric, payload.grid);
            % Selected points are materialized once from the same long-format rows
            % used by the plotted series. Static renderers must consume this object
            % rather than recomputing a best model from a separately reconstructed curve.
            component.PlotPayload.selectedPoints = NMResultsViewerReportTools.bestMetricRows(component.Tables.metricValues);
            component.Status = 'ok';
        end

        function component = componentMetricDashboard(component, payload)
            % componentMetricDashboard  Attach finite optimization metrics and registry diagnostics.
            metrics = payload.metrics;
            mask = NMResultsViewerReportTools.availableMetricMask(metrics);
            component.Payload.metrics = metrics(mask);
            component.Tables.metricRegistry = NMResultsViewerReportTools.metricRegistryRows(metrics(mask));
            component.Tables.metricValues = NMResultsViewerReportTools.allMetricValueRows(metrics(mask), payload.grid);
            registryRows = component.Tables.metricRegistry;
            missingRows = NMResultsViewerReportTools.metricRegistryUnavailableRows(registryRows);
            if ~isempty(missingRows)
                suffix = 'entry';
                if numel(missingRows) ~= 1, suffix = 'entries'; end
                component.Warnings{end+1} = sprintf('%d optimization metric registry %s omitted from the scientific summary because no finite values are available.', ...
                    numel(missingRows), suffix);
            end
            if any(mask)
                component.Status = 'ok';
            else
                component.Status = 'unavailable';
                component.MissingReason = 'No available optimization metrics are present for the dashboard component.';
            end
        end

        function component = componentCvPartitions(component, payload)
            % componentCvPartitions  Attach CV partition matrices and long-format rows.
            partitions = payload.partitions;
            rows = NMResultsViewerReportTools.partitionRows(partitions);
            if any([rows.value] == 0)
                component.Warnings{end+1} = ['Persisted CV partition values contain zero(s), but the legacy optimizer does not persist a per-partition completion mask. ' ...
                    'Finite zeros are retained; in zero-initialized ordinary result arrays, an uncomputed cell cannot be distinguished from a computed zero.'];
            end
            component.Payload.partitions = partitions;
            component.Tables.cvPartitions = rows;
            if isempty(rows)
                component.Status = 'unavailable';
                component.MissingReason = 'No CV partition matrices are available for the selected model-optimization source.';
            else
                component.Status = 'ok';
            end
        end

        function component = componentParameterSurface(component, payload, compSpec)
            % componentParameterSurface  Build 2D parameter-surface report rows.
            surfaceSpec = NMResultsViewerReportTools.surfaceSpecFromComponent(compSpec, payload);
            surface = NMResultsViewerReportTools.buildParameterSurface(payload, surfaceSpec);
            component.Payload.surfaceSpec = surfaceSpec;
            component.Payload.surface = surface;
            component.Tables.parameterSurface = NMResultsViewerReportTools.surfaceRows(surface);
            if surface.ok
                component.Status = 'ok';
            else
                component.Status = 'unavailable';
                component.MissingReason = surface.message;
            end
        end

        function component = componentScatterComparison(component, payload, compSpec, includePareto)
            % componentScatterComparison  Build scatter and optional Pareto report rows.
            scatterSpec = NMResultsViewerReportTools.scatterSpecFromComponent(compSpec, payload);
            scatter = NMResultsViewerReportTools.buildScatterComparison(payload, scatterSpec, includePareto);
            component.Payload.scatterSpec = scatterSpec;
            component.Payload.scatter = scatter;
            component.Tables.scatterPoints = NMResultsViewerReportTools.scatterRows(scatter);
            component.Tables.associations = NMResultsViewerReportTools.associationRows(scatter);
            if includePareto
                component.Tables.paretoSummary = NMResultsViewerReportTools.paretoRows(scatter);
            end
            if scatter.ok
                component.Status = 'ok';
            else
                component.Status = 'unavailable';
                component.MissingReason = scatter.message;
            end
        end

        function rows = metricRegistryRows(metrics)
            % metricRegistryRows  Convert metric registry to table-like row structs.
            tmpl = struct('metricId','','metricLabel','','seriesIndex',0,'seriesLabel','', ...
                'family','','unit','','higherIsBetter',false,'lowerIsBetter',false, ...
                'available',false,'missingReason','','nFinite',0,'nMissing',0, ...
                'min',NaN,'max',NaN,'mean',NaN,'median',NaN,'sd',NaN,'sourceFields','');
            nRows = 0;
            for ii = 1:numel(metrics)
                nRows = nRows + max(1, NMResultsViewerReportTools.metricSeriesCount(metrics(ii)));
            end
            rows = repmat(tmpl, 1, nRows);
            rr = 0;
            for ii = 1:numel(metrics)
                nSeries = max(1, NMResultsViewerReportTools.metricSeriesCount(metrics(ii)));
                for jj = 1:nSeries
                    rr = rr + 1;
                    vals = NMResultsViewerReportTools.metricSeriesValues(metrics(ii), jj);
                    rows(rr).metricId = metrics(ii).id;
                    rows(rr).metricLabel = metrics(ii).label;
                    rows(rr).seriesIndex = jj;
                    rows(rr).seriesLabel = NMResultsViewerReportTools.metricSeriesLabel(metrics(ii), jj);
                    rows(rr).family = metrics(ii).family;
                    rows(rr).unit = metrics(ii).unit;
                    rows(rr).higherIsBetter = metrics(ii).higherIsBetter;
                    rows(rr).lowerIsBetter = metrics(ii).lowerIsBetter;
                    rows(rr).available = metrics(ii).available;
                    rows(rr).missingReason = metrics(ii).missingReason;
                    rows(rr).sourceFields = strjoin(NMResultsViewerReportTools.safeCellstr(metrics(ii).sourceFields), ', ');
                    finiteVals = vals(isfinite(vals));
                    rows(rr).nFinite = numel(finiteVals);
                    rows(rr).nMissing = numel(vals) - numel(finiteVals);
                    if ~isempty(finiteVals)
                        rows(rr).min = min(finiteVals);
                        rows(rr).max = max(finiteVals);
                        rows(rr).mean = mean(finiteVals);
                        rows(rr).median = median(finiteVals);
                        rows(rr).sd = std(finiteVals);
                    end
                end
            end
        end

        function rows = parameterGridRows(grid)
            % parameterGridRows  Convert parameter-grid metadata to row structs.
            tmpl = struct('modelIndex',0,'label','','tooltip','','parameterValues','');
            if isempty(grid.parameterRows)
                rows = tmpl([]);
                return;
            end
            rows = repmat(tmpl, 1, numel(grid.parameterRows));
            for ii = 1:numel(grid.parameterRows)
                r = grid.parameterRows(ii);
                rows(ii).modelIndex = r.index;
                rows(ii).label = r.label;
                rows(ii).tooltip = r.tooltip;
                rows(ii).parameterValues = strjoin(NMResultsViewerReportTools.valueCellToText(r.values), ' | ');
            end
        end

        function rows = metricValueRows(metric, grid)
            % metricValueRows  Convert one metric to long-format value rows.
            nSeries = NMResultsViewerReportTools.metricSeriesCount(metric);
            nModel = NMResultsViewerReportTools.metricRowCount(metric);
            tmpl = struct('modelIndex',0,'modelLabel','','metricId','','metricLabel','','directionSign',1, ...
                'seriesIndex',0,'seriesLabel','','value',NaN,'sem',NaN,'parameterValues','');
            rows = repmat(tmpl, 1, max(0,nSeries*nModel));
            rr = 0;
            for ss = 1:nSeries
                vals = NMResultsViewerReportTools.metricSeriesValues(metric, ss);
                sem = NMResultsViewerReportTools.metricSeriesSem(metric, ss, numel(vals));
                for ii = 1:numel(vals)
                    rr = rr + 1;
                    rows(rr).modelIndex = ii;
                    rows(rr).modelLabel = NMResultsViewerReportTools.gridRowLabel(grid, ii);
                    rows(rr).metricId = metric.id;
                    rows(rr).metricLabel = metric.label;
                    rows(rr).directionSign = NMResultsViewerReportTools.metricDirectionSign(metric);
                    rows(rr).seriesIndex = ss;
                    rows(rr).seriesLabel = NMResultsViewerReportTools.metricSeriesLabel(metric, ss);
                    rows(rr).value = vals(ii);
                    rows(rr).sem = sem(ii);
                    rows(rr).parameterValues = NMResultsViewerReportTools.gridRowTooltip(grid, ii);
                end
            end
        end

        function rows = allMetricValueRows(metrics, grid)
            % allMetricValueRows  Convert all available metrics to long-format value rows.
            counts = zeros(1, numel(metrics));
            tmpRows = cell(1, numel(metrics));
            for ii = 1:numel(metrics)
                tmpRows{ii} = NMResultsViewerReportTools.metricValueRows(metrics(ii), grid);
                counts(ii) = numel(tmpRows{ii});
            end
            if sum(counts) == 0
                rows = NMResultsViewerReportTools.metricValueRows(NMResultsViewerReportTools.metricTemplateFallback(), grid);
                rows = rows([]);
                return;
            end
            tmpl = tmpRows{find(counts > 0, 1, 'first')}(1);
            rows = repmat(tmpl, 1, sum(counts));
            rr = 0;
            for ii = 1:numel(tmpRows)
                for jj = 1:numel(tmpRows{ii})
                    rr = rr + 1;
                    rows(rr) = tmpRows{ii}(jj);
                end
            end
        end

        function rows = partitionRows(partitions)
            % partitionRows  Convert CV partition matrices to long-format rows.
            names = {'cv1','cv2','complexity','error'};
            titles = {'CV1','CV2','Complexity','Generalization error'};
            tmpl = struct('partitionKind','','title','','permutation',0,'fold',0,'value',NaN,'computed',false,'maskSource','');
            blocks = cell(1, numel(names));
            counts = zeros(1, numel(names));
            for kk = 1:numel(names)
                part = partitions.(names{kk});
                mat = NMResultsViewerReportTools.numericMatrixFromPayloadValues(part.matrix);
                if part.ok && ~isempty(mat)
                    [nPerm, nFold] = size(mat);
                    b = repmat(tmpl, 1, nPerm*nFold);
                    rr = 0;
                    for pp = 1:nPerm
                        for ff = 1:nFold
                            rr = rr + 1;
                            b(rr).partitionKind = names{kk};
                            b(rr).title = titles{kk};
                            b(rr).permutation = pp;
                            b(rr).fold = ff;
                            b(rr).value = mat(pp,ff);
                            b(rr).computed = isfinite(mat(pp,ff));
                            if b(rr).computed
                                b(rr).maskSource = 'finite_value';
                            else
                                b(rr).maskSource = 'nonfinite_value';
                            end
                        end
                    end
                    blocks{kk} = b;
                    counts(kk) = numel(b);
                else
                    blocks{kk} = tmpl([]);
                end
            end
            if sum(counts) == 0
                rows = tmpl([]);
                return;
            end
            rows = repmat(tmpl, 1, sum(counts));
            rr = 0;
            for kk = 1:numel(blocks)
                for ii = 1:numel(blocks{kk})
                    rr = rr + 1;
                    rows(rr) = blocks{kk}(ii);
                end
            end
        end

        function surfaceSpec = surfaceSpecFromComponent(compSpec, payload)
            % surfaceSpecFromComponent  Resolve parameter-surface component options.
            opts = compSpec.Options;
            surfaceSpec = struct('MetricId',NMResultsViewerReportTools.structText(opts, {'MetricId','metricId'}, ''), ...
                'Aggregation',NMResultsViewerReportTools.structText(opts, {'Aggregation','aggregation'}, 'mean'), ...
                'XParameterIndex',NMResultsViewerReportTools.structScalar(opts, {'XParameterIndex','xParameterIndex'}, 1), ...
                'YParameterIndex',NMResultsViewerReportTools.structScalar(opts, {'YParameterIndex','yParameterIndex'}, 2));
            if isempty(surfaceSpec.MetricId)
                metric = NMResultsViewerReportTools.firstAvailableMetric(payload);
                if ~isempty(metric), surfaceSpec.MetricId = NMResultsViewerReportTools.safeField(metric,'id',''); end
            end
        end

        function surface = buildParameterSurface(payload, surfaceSpec)
            % buildParameterSurface  Aggregate one metric over two parameter dimensions.
            surface = struct('ok',false,'message','','metricId',surfaceSpec.MetricId,'aggregation',surfaceSpec.Aggregation, ...
                'xParameterIndex',surfaceSpec.XParameterIndex,'yParameterIndex',surfaceSpec.YParameterIndex, ...
                'xParameterName','','yParameterName','','directionSign',1,'series',[]);
            grid = payload.grid;
            metric = NMResultsViewerReportTools.findMetricById(payload.metrics, surfaceSpec.MetricId);
            if isempty(metric)
                surface.message = 'Selected parameter-surface metric is unavailable.';
                return;
            end
            if ~NMResultsViewerReportTools.hasParameterSurfaceInputs(payload)
                surface.message = 'Parameter-surface view requires at least two machine-readable parameter dimensions.';
                return;
            end
            paramNames = NMResultsViewerReportTools.safeCellstr(grid.parameterNames);
            xIdx = max(1, min(round(double(surfaceSpec.XParameterIndex)), numel(paramNames)));
            yIdx = max(1, min(round(double(surfaceSpec.YParameterIndex)), numel(paramNames)));
            if xIdx == yIdx && numel(paramNames) >= 2, yIdx = 2; end
            surface.xParameterIndex = xIdx;
            surface.yParameterIndex = yIdx;
            surface.xParameterName = paramNames{xIdx};
            surface.yParameterName = paramNames{yIdx};
            surface.directionSign = NMResultsViewerReportTools.metricDirectionSign(metric);
            nSeries = NMResultsViewerReportTools.metricSeriesCount(metric);
            seriesTmpl = struct('seriesIndex',0,'seriesLabel','','xValues',{{}},'yValues',{{}},'cells',[]);
            series = repmat(seriesTmpl, 1, nSeries);
            for ss = 1:nSeries
                series(ss) = NMResultsViewerReportTools.parameterSurfaceSeries(metric, ss, grid, xIdx, yIdx, surfaceSpec.Aggregation);
            end
            surface.series = series;
            surface.ok = nSeries > 0;
            surface.message = '';
        end

        function series = parameterSurfaceSeries(metric, seriesIndex, grid, xIdx, yIdx, aggregation)
            % parameterSurfaceSeries  Build one aggregated parameter-surface series.
            vals = NMResultsViewerReportTools.metricSeriesValues(metric, seriesIndex);
            n = min(numel(vals), numel(grid.parameterRows));
            xKeys = cell(1,n);
            yKeys = cell(1,n);
            xLabels = cell(1,n);
            yLabels = cell(1,n);
            for ii = 1:n
                rowVals = grid.parameterRows(ii).values;
                xVal = NMResultsViewerReportTools.valueAt(rowVals, xIdx);
                yVal = NMResultsViewerReportTools.valueAt(rowVals, yIdx);
                xKeys{ii} = NMResultsViewerReportTools.valueKey(xVal);
                yKeys{ii} = NMResultsViewerReportTools.valueKey(yVal);
                xLabels{ii} = NMResultsViewerReportTools.valueText(xVal);
                yLabels{ii} = NMResultsViewerReportTools.valueText(yVal);
            end
            [uxKeys, uxFirst] = unique(xKeys, 'stable');
            [uyKeys, uyFirst] = unique(yKeys, 'stable');
            xVals = xLabels(uxFirst);
            yVals = yLabels(uyFirst);
            cellTmpl = struct('xIndex',0,'yIndex',0,'xValue','','yValue','', ...
                'aggregateValue',NaN,'nContributingModels',0,'mean',NaN,'sd',NaN, ...
                'min',NaN,'max',NaN,'bestModelIndex',NaN,'contributingModelIndices','');
            cells = repmat(cellTmpl, 1, numel(uxKeys)*numel(uyKeys));
            rr = 0;
            for yy = 1:numel(uyKeys)
                for xx = 1:numel(uxKeys)
                    rr = rr + 1;
                    mask = strcmp(xKeys, uxKeys{xx}) & strcmp(yKeys, uyKeys{yy});
                    idx = find(mask);
                    finiteIdx = idx(isfinite(vals(idx)));
                    cells(rr).xIndex = xx;
                    cells(rr).yIndex = yy;
                    cells(rr).xValue = xVals{xx};
                    cells(rr).yValue = yVals{yy};
                    cells(rr).nContributingModels = numel(finiteIdx);
                    cells(rr).contributingModelIndices = NMResultsViewerReportTools.indexListText(finiteIdx);
                    if ~isempty(finiteIdx)
                        v = vals(finiteIdx);
                        cells(rr).mean = mean(v);
                        cells(rr).sd = std(v);
                        cells(rr).min = min(v);
                        cells(rr).max = max(v);
                        [cells(rr).aggregateValue, bestLocal] = NMResultsViewerReportTools.aggregateValues(v, aggregation, metric);
                        cells(rr).bestModelIndex = finiteIdx(bestLocal);
                    end
                end
            end
            series = struct('seriesIndex',seriesIndex,'seriesLabel',NMResultsViewerReportTools.metricSeriesLabel(metric, seriesIndex), ...
                'xValues',{xVals},'yValues',{yVals},'cells',cells);
        end

        function rows = surfaceRows(surface)
            % surfaceRows  Convert parameter-surface payload to row structs.
            tmpl = struct('metricId','','seriesIndex',0,'seriesLabel','','directionSign',1,'xParameter','','xValue','', ...
                'yParameter','','yValue','','aggregationRule','','aggregateValue',NaN, ...
                'nContributingModels',0,'mean',NaN,'sd',NaN,'min',NaN,'max',NaN, ...
                'bestModelIndex',NaN,'contributingModelIndices','');
            if ~isstruct(surface) || ~isfield(surface,'series') || isempty(surface.series)
                rows = tmpl([]);
                return;
            end
            counts = zeros(1, numel(surface.series));
            for ss = 1:numel(surface.series), counts(ss) = numel(surface.series(ss).cells); end
            rows = repmat(tmpl, 1, sum(counts));
            rr = 0;
            for ss = 1:numel(surface.series)
                for cc = 1:numel(surface.series(ss).cells)
                    rr = rr + 1;
                    c = surface.series(ss).cells(cc);
                    rows(rr).metricId = surface.metricId;
                    rows(rr).seriesIndex = surface.series(ss).seriesIndex;
                    rows(rr).seriesLabel = surface.series(ss).seriesLabel;
                    rows(rr).directionSign = surface.directionSign;
                    rows(rr).xParameter = surface.xParameterName;
                    rows(rr).xValue = c.xValue;
                    rows(rr).yParameter = surface.yParameterName;
                    rows(rr).yValue = c.yValue;
                    rows(rr).aggregationRule = surface.aggregation;
                    rows(rr).aggregateValue = c.aggregateValue;
                    rows(rr).nContributingModels = c.nContributingModels;
                    rows(rr).mean = c.mean;
                    rows(rr).sd = c.sd;
                    rows(rr).min = c.min;
                    rows(rr).max = c.max;
                    rows(rr).bestModelIndex = c.bestModelIndex;
                    rows(rr).contributingModelIndices = c.contributingModelIndices;
                end
            end
        end

        function scatterSpec = scatterSpecFromComponent(compSpec, payload)
            % scatterSpecFromComponent  Resolve scatter comparison component options.
            opts = compSpec.Options;
            scatterSpec = struct('XMetricId',NMResultsViewerReportTools.structText(opts, {'XMetricId','xMetricId'}, ''), ...
                'YMetricId',NMResultsViewerReportTools.structText(opts, {'YMetricId','yMetricId'}, ''), ...
                'FrontierMode',NMResultsViewerReportTools.structText(opts, {'FrontierMode','frontierMode'}, 'pareto'));
            if isempty(scatterSpec.XMetricId) || isempty(scatterSpec.YMetricId)
                [xMetric, yMetric] = NMResultsViewerReportTools.defaultScatterMetrics(payload);
                if isempty(scatterSpec.XMetricId) && ~isempty(xMetric), scatterSpec.XMetricId = xMetric.id; end
                if isempty(scatterSpec.YMetricId) && ~isempty(yMetric), scatterSpec.YMetricId = yMetric.id; end
            end
        end

        function scatter = buildScatterComparison(payload, scatterSpec, includePareto)
            % buildScatterComparison  Build metric-vs-metric scatter comparison payload.
            scatter = struct('ok',false,'message','','xMetricId',scatterSpec.XMetricId,'yMetricId',scatterSpec.YMetricId, ...
                'frontierMode',scatterSpec.FrontierMode,'series',[]);
            metrics = payload.metrics;
            xMetric = NMResultsViewerReportTools.findMetricById(metrics, scatterSpec.XMetricId);
            yMetric = NMResultsViewerReportTools.findMetricById(metrics, scatterSpec.YMetricId);
            if isempty(xMetric) || isempty(yMetric)
                scatter.message = 'Selected scatter metric pair is unavailable.';
                return;
            end
            nSeries = max(NMResultsViewerReportTools.metricSeriesCount(xMetric), NMResultsViewerReportTools.metricSeriesCount(yMetric));
            sTmpl = NMResultsViewerReportTools.scatterSeriesTemplate();
            series = repmat(sTmpl, 1, nSeries);
            for ss = 1:nSeries
                xSeriesIdx = min(ss, NMResultsViewerReportTools.metricSeriesCount(xMetric));
                ySeriesIdx = min(ss, NMResultsViewerReportTools.metricSeriesCount(yMetric));
                series(ss) = NMResultsViewerReportTools.scatterSeries(payload, xMetric, yMetric, xSeriesIdx, ySeriesIdx, includePareto, scatterSpec.FrontierMode);
                series(ss).seriesIndex = ss;
            end
            scatter.series = series;
            scatter.ok = any(arrayfun(@(s) s.n > 1, series));
            if scatter.ok
                scatter.message = '';
            else
                scatter.message = 'Scatter comparison requires at least two finite paired metric values.';
            end
        end

        function tmpl = scatterSeriesTemplate()
            % scatterSeriesTemplate  Create a fixed-schema scatter series payload.
            tmpl = struct('seriesIndex',0,'seriesLabel','','xSeriesIndex',0,'ySeriesIndex',0, ...
                'n',0,'nExcluded',0,'points',[],'association',NMResultsViewerReportTools.associationTemplate(), ...
                'pareto',NMResultsViewerReportTools.paretoTemplate());
        end

        function a = associationTemplate()
            % associationTemplate  Create a fixed-schema association-statistics payload.
            a = struct('n',0,'slope',NaN,'intercept',NaN,'pearsonR',NaN,'pValue',NaN, ...
                'xRange',[NaN NaN],'yRange',[NaN NaN],'lowDynamicRangeWarning','');
        end

        function p = paretoTemplate()
            % paretoTemplate  Create a fixed-schema Pareto summary payload.
            p = struct('frontierMode','none','xDirection','','yDirection','', ...
                'nFrontier',0,'nDominated',0,'frontierModelIndices','');
        end

        function series = scatterSeries(payload, xMetric, yMetric, xSeriesIdx, ySeriesIdx, includePareto, frontierMode)
            % scatterSeries  Build one displayed scatter series and diagnostics.
            x = NMResultsViewerReportTools.metricSeriesValues(xMetric, xSeriesIdx);
            y = NMResultsViewerReportTools.metricSeriesValues(yMetric, ySeriesIdx);
            n = min(numel(x), numel(y));
            x = x(1:n);
            y = y(1:n);
            valid = isfinite(x) & isfinite(y);
            idx = find(valid);
            pointTmpl = struct('modelIndex',0,'modelLabel','','xValue',NaN,'yValue',NaN, ...
                'xSem',NaN,'ySem',NaN,'isParetoFrontier',false,'isDominated',false, ...
                'parameterValues','');
            points = repmat(pointTmpl, 1, numel(idx));
            xSem = NMResultsViewerReportTools.metricSeriesSem(xMetric, xSeriesIdx, n);
            ySem = NMResultsViewerReportTools.metricSeriesSem(yMetric, ySeriesIdx, n);
            grid = payload.grid;
            for ii = 1:numel(idx)
                modelIdx = idx(ii);
                points(ii).modelIndex = modelIdx;
                points(ii).modelLabel = NMResultsViewerReportTools.gridRowLabel(grid, modelIdx);
                points(ii).xValue = x(modelIdx);
                points(ii).yValue = y(modelIdx);
                points(ii).xSem = xSem(modelIdx);
                points(ii).ySem = ySem(modelIdx);
                points(ii).parameterValues = NMResultsViewerReportTools.gridRowTooltip(grid, modelIdx);
            end
            assoc = NMResultsViewerReportTools.associationStats(x(valid), y(valid));
            pareto = NMResultsViewerReportTools.paretoTemplate();
            if includePareto && numel(points) > 0
                [frontierMask, pareto] = NMResultsViewerReportTools.computePareto(points, xMetric, yMetric, frontierMode);
                for ii = 1:numel(points)
                    points(ii).isParetoFrontier = frontierMask(ii);
                    points(ii).isDominated = ~frontierMask(ii);
                end
            end
            series = NMResultsViewerReportTools.scatterSeriesTemplate();
            series.seriesIndex = 1;
            series.seriesLabel = sprintf('%s vs %s', NMResultsViewerReportTools.metricSeriesLabel(yMetric,ySeriesIdx), NMResultsViewerReportTools.metricSeriesLabel(xMetric,xSeriesIdx));
            series.xSeriesIndex = xSeriesIdx;
            series.ySeriesIndex = ySeriesIdx;
            series.n = numel(points);
            series.nExcluded = n - numel(points);
            series.points = points;
            series.association = assoc;
            series.pareto = pareto;
        end

        function rows = scatterRows(scatter)
            % scatterRows  Convert scatter points to table-like row structs.
            tmpl = struct('seriesIndex',0,'seriesLabel','','modelIndex',0,'modelLabel','', ...
                'xMetric','','yMetric','','xValue',NaN,'yValue',NaN,'xSem',NaN,'ySem',NaN, ...
                'isParetoFrontier',false,'isDominated',false,'parameterValues','');
            if ~isstruct(scatter) || ~isfield(scatter,'series') || isempty(scatter.series)
                rows = tmpl([]);
                return;
            end
            counts = zeros(1, numel(scatter.series));
            for ss = 1:numel(scatter.series), counts(ss) = numel(scatter.series(ss).points); end
            rows = repmat(tmpl, 1, sum(counts));
            rr = 0;
            for ss = 1:numel(scatter.series)
                for ii = 1:numel(scatter.series(ss).points)
                    rr = rr + 1;
                    p = scatter.series(ss).points(ii);
                    rows(rr).seriesIndex = ss;
                    rows(rr).seriesLabel = scatter.series(ss).seriesLabel;
                    rows(rr).modelIndex = p.modelIndex;
                    rows(rr).modelLabel = p.modelLabel;
                    rows(rr).xMetric = scatter.xMetricId;
                    rows(rr).yMetric = scatter.yMetricId;
                    rows(rr).xValue = p.xValue;
                    rows(rr).yValue = p.yValue;
                    rows(rr).xSem = p.xSem;
                    rows(rr).ySem = p.ySem;
                    rows(rr).isParetoFrontier = p.isParetoFrontier;
                    rows(rr).isDominated = p.isDominated;
                    rows(rr).parameterValues = p.parameterValues;
                end
            end
        end

        function rows = associationRows(scatter)
            % associationRows  Convert association diagnostics to table-like rows.
            tmpl = struct('seriesIndex',0,'seriesLabel','','n',0,'slope',NaN,'intercept',NaN, ...
                'pearsonR',NaN,'pValue',NaN,'xRangeMin',NaN,'xRangeMax',NaN, ...
                'yRangeMin',NaN,'yRangeMax',NaN,'lowDynamicRangeWarning','');
            if ~isstruct(scatter) || ~isfield(scatter,'series') || isempty(scatter.series)
                rows = tmpl([]);
                return;
            end
            rows = repmat(tmpl, 1, numel(scatter.series));
            for ss = 1:numel(scatter.series)
                a = scatter.series(ss).association;
                rows(ss).seriesIndex = ss;
                rows(ss).seriesLabel = scatter.series(ss).seriesLabel;
                rows(ss).n = a.n;
                rows(ss).slope = a.slope;
                rows(ss).intercept = a.intercept;
                rows(ss).pearsonR = a.pearsonR;
                rows(ss).pValue = a.pValue;
                rows(ss).xRangeMin = a.xRange(1);
                rows(ss).xRangeMax = a.xRange(2);
                rows(ss).yRangeMin = a.yRange(1);
                rows(ss).yRangeMax = a.yRange(2);
                rows(ss).lowDynamicRangeWarning = a.lowDynamicRangeWarning;
            end
        end

        function rows = paretoRows(scatter)
            % paretoRows  Convert Pareto summaries to table-like rows.
            tmpl = struct('seriesIndex',0,'seriesLabel','','frontierMode','','xDirection','', ...
                'yDirection','','nFrontier',0,'nDominated',0,'frontierModelIndices','');
            if ~isstruct(scatter) || ~isfield(scatter,'series') || isempty(scatter.series)
                rows = tmpl([]);
                return;
            end
            rows = repmat(tmpl, 1, numel(scatter.series));
            for ss = 1:numel(scatter.series)
                p = scatter.series(ss).pareto;
                rows(ss).seriesIndex = ss;
                rows(ss).seriesLabel = scatter.series(ss).seriesLabel;
                rows(ss).frontierMode = p.frontierMode;
                rows(ss).xDirection = p.xDirection;
                rows(ss).yDirection = p.yDirection;
                rows(ss).nFrontier = p.nFrontier;
                rows(ss).nDominated = p.nDominated;
                rows(ss).frontierModelIndices = p.frontierModelIndices;
            end
        end

        function [frontierMask, pareto] = computePareto(points, xMetric, yMetric, frontierMode)
            % computePareto  Compute direction-aware non-dominated scatter points.
            n = numel(points);
            frontierMask = true(1,n);
            xSign = NMResultsViewerReportTools.metricDirectionSign(xMetric);
            ySign = NMResultsViewerReportTools.metricDirectionSign(yMetric);
            useSemTolerance = contains(lower(char(string(frontierMode))), 'sem');
            for ii = 1:n
                xi = xSign * points(ii).xValue;
                yi = ySign * points(ii).yValue;
                for jj = 1:n
                    if ii == jj, continue; end
                    xj = xSign * points(jj).xValue;
                    yj = ySign * points(jj).yValue;
                    xTol = 0;
                    yTol = 0;
                    if useSemTolerance
                        xTol = NMResultsViewerReportTools.maxFinite([0, abs(points(ii).xSem), abs(points(jj).xSem)]);
                        yTol = NMResultsViewerReportTools.maxFinite([0, abs(points(ii).ySem), abs(points(jj).ySem)]);
                        if ~isfinite(xTol), xTol = 0; end
                        if ~isfinite(yTol), yTol = 0; end
                    end
                    atLeast = xj >= xi - xTol && yj >= yi - yTol;
                    strict = xj > xi + xTol || yj > yi + yTol;
                    if atLeast && strict
                        frontierMask(ii) = false;
                        break;
                    end
                end
            end
            frontierIdx = [points(frontierMask).modelIndex];
            pareto = NMResultsViewerReportTools.paretoTemplate();
            pareto.frontierMode = frontierMode;
            pareto.xDirection = NMResultsViewerReportTools.metricDirectionLabel(xMetric);
            pareto.yDirection = NMResultsViewerReportTools.metricDirectionLabel(yMetric);
            pareto.nFrontier = sum(frontierMask);
            pareto.nDominated = n - pareto.nFrontier;
            pareto.frontierModelIndices = NMResultsViewerReportTools.indexListText(frontierIdx);
        end

        function assoc = associationStats(x, y)
            % associationStats  Compute simple linear association diagnostics.
            assoc = NMResultsViewerReportTools.associationTemplate();
            x = double(x(:));
            y = double(y(:));
            valid = isfinite(x) & isfinite(y);
            x = x(valid);
            y = y(valid);
            assoc.n = numel(x);
            if numel(x) < 2
                return;
            end
            assoc.xRange = [min(x) max(x)];
            assoc.yRange = [min(y) max(y)];
            if (max(x)-min(x)) <= max(1, abs(mean(x))) * 1e-6 || (max(y)-min(y)) <= max(1, abs(mean(y))) * 1e-6
                assoc.lowDynamicRangeWarning = 'One or both scatter metrics have very limited dynamic range.';
            end
            X = [ones(numel(x),1), x];
            beta = X \ y;
            assoc.intercept = beta(1);
            assoc.slope = beta(2);
            if std(x) > 0 && std(y) > 0
                R = corrcoef(x, y);
                assoc.pearsonR = R(1,2);
                df = numel(x) - 2;
                if df > 0 && abs(assoc.pearsonR) < 1
                    tval = assoc.pearsonR * sqrt(df / max(eps, 1 - assoc.pearsonR^2));
                    assoc.pValue = betainc(df / (df + tval^2), df/2, 0.5);
                elseif abs(assoc.pearsonR) == 1
                    assoc.pValue = 0;
                end
            end
        end

        function [xMetric, yMetric] = defaultScatterMetrics(payload)
            % defaultScatterMetrics  Select a reproducible default metric pair.
            metrics = payload.metrics;
            available = metrics(NMResultsViewerReportTools.availableMetricMask(metrics));
            xMetric = [];
            yMetric = [];
            xPref = {'complexity','multiclass_complexity','generalization_error','multiclass_generalization_error','diversity','multiclass_diversity'};
            yPref = {'cv_performance','multiclass_cv_performance','selection_frequency','multiclass_selection_frequency'};
            for ii = 1:numel(xPref)
                xMetric = NMResultsViewerReportTools.findMetricById(available, xPref{ii});
                if ~isempty(xMetric), break; end
            end
            for ii = 1:numel(yPref)
                yMetric = NMResultsViewerReportTools.findMetricById(available, yPref{ii});
                if ~isempty(yMetric), break; end
            end
            if isempty(xMetric) && numel(available) >= 1, xMetric = available(1); end
            if isempty(yMetric) && numel(available) >= 2, yMetric = available(2); end
        end

        function mask = availableMetricMask(metrics)
            % availableMetricMask  Identify available metric descriptors.
            %
            % metrics(ii).values: numeric matrix or JSON-safe row-cell numeric array.
            %                      The Results Viewer browser payload may store dense
            %                      optimization curves as row-cell arrays to avoid
            %                      generic heavy-array stripping during JSON transfer.
            mask = false(1, numel(metrics));
            for ii = 1:numel(metrics)
                if ~metrics(ii).available
                    continue;
                end
                vals = NMResultsViewerReportTools.numericMatrixFromPayloadValues(metrics(ii).values);
                mask(ii) = ~isempty(vals) && any(isfinite(vals(:)));
            end
        end

        function tf = hasParameterSurfaceInputs(payload)
            % hasParameterSurfaceInputs  Check whether grid metadata supports 2D surfaces.
            tf = false;
            names = NMResultsViewerReportTools.safeCellstr(payload.grid.parameterNames);
            rows = payload.grid.parameterRows;
            if numel(names) < 2 || isempty(rows), return; end
            for ii = 1:min(3, numel(rows))
                vals = rows(ii).values;
                if numel(vals) >= 2
                    tf = true;
                    return;
                end
            end
        end

        function metric = selectMetric(payload, compSpec, fallbackId)
            % selectMetric  Resolve requested metric or first available fallback.
            opts = compSpec.Options;
            metricId = NMResultsViewerReportTools.structText(opts, {'MetricId','metricId'}, fallbackId);
            metrics = payload.metrics;
            metric = [];
            if ~isempty(metricId)
                metric = NMResultsViewerReportTools.findMetricById(metrics, metricId);
            end
            if isempty(metric)
                metric = NMResultsViewerReportTools.firstAvailableMetric(payload);
            end
        end

        function metric = firstAvailableMetric(payload)
            % firstAvailableMetric  Return the first available metric descriptor.
            metric = [];
            metrics = payload.metrics;
            for ii = 1:numel(metrics)
                if metrics(ii).available
                    metric = metrics(ii);
                    return;
                end
            end
        end

        function metric = findMetricById(metrics, id)
            % findMetricById  Locate a metric descriptor by id.
            metric = [];
            if isempty(id), return; end
            for ii = 1:numel(metrics)
                if strcmp(metrics(ii).id, id)
                    metric = metrics(ii);
                    return;
                end
            end
        end


        function mat = numericMatrixFromPayloadValues(values)
            % numericMatrixFromPayloadValues  Normalize numeric or row-cell payload values.
            %
            % values: numeric array, cell matrix of numeric scalars, or row-cell array
            %         whose elements contain numeric row vectors. This helper exists
            %         because dense Results Viewer payloads are deliberately converted
            %         to JSON-safe cell encodings before browser transfer; report
            %         catalogue checks must still treat those values as legitimate
            %         numeric data. Non-numeric cells are returned as NaN placeholders
            %         rather than being silently dropped, preserving row positions.
            mat = [];
            if isnumeric(values)
                mat = double(values);
                return;
            end
            if ~iscell(values) || isempty(values)
                return;
            end

            scalarMask = cellfun(@(x) isnumeric(x) && isscalar(x), values);
            if all(scalarMask(:))
                mat = cellfun(@double, values);
                return;
            end

            nRows = numel(values);
            nCols = 0;
            rows = cell(1, nRows);
            for ii = 1:nRows
                row = NMResultsViewerReportTools.numericRowFromPayloadCell(values{ii});
                rows{ii} = row;
                nCols = max(nCols, numel(row));
            end
            if nCols < 1
                return;
            end
            mat = NaN(nRows, nCols);
            for ii = 1:nRows
                row = rows{ii};
                if isempty(row), continue; end
                mat(ii, 1:numel(row)) = row;
            end
        end

        function row = numericRowFromPayloadCell(value)
            % numericRowFromPayloadCell  Convert one JSON-safe payload row to doubles.
            %
            % value: numeric vector or cell vector containing numeric scalar elements.
            %        Invalid elements are represented as NaN to preserve positional
            %        semantics for parameter-combination and series indices.
            row = [];
            if isnumeric(value)
                row = double(value(:))';
                return;
            end
            if ~iscell(value) || isempty(value)
                return;
            end
            row = NaN(1, numel(value));
            for jj = 1:numel(value)
                x = value{jj};
                if isnumeric(x) && isscalar(x)
                    row(jj) = double(x);
                end
            end
        end

        function n = metricSeriesCount(metric)
            % metricSeriesCount  Return the number of numeric series in a metric.
            %
            % metric.values: numeric matrix or JSON-safe row-cell numeric array.
            %                Dense optimization curves may arrive in either encoding;
            %                catalogue availability must not depend on the transfer
            %                representation.
            n = 0;
            if ~isstruct(metric) || ~isfield(metric,'values')
                return;
            end
            vals = NMResultsViewerReportTools.numericMatrixFromPayloadValues(metric.values);
            if isempty(vals), return; end
            if isvector(vals)
                n = 1;
            else
                n = size(vals, 2);
            end
        end

        function n = metricRowCount(metric)
            % metricRowCount  Return the parameter-row count in a metric.
            n = 0;
            if ~isstruct(metric) || ~isfield(metric,'values') || ~isnumeric(metric.values) || isempty(metric.values)
                return;
            end
            vals = double(metric.values);
            if isvector(vals)
                n = numel(vals);
            else
                n = size(vals,1);
            end
        end

        function vals = metricSeriesValues(metric, seriesIndex)
            % metricSeriesValues  Extract one metric series as a column vector.
            %
            % metric.values: numeric matrix or JSON-safe row-cell numeric array. The
            %                conversion is read-only and preserves row/series order.
            vals = [];
            if ~isstruct(metric) || ~isfield(metric,'values')
                return;
            end
            arr = NMResultsViewerReportTools.numericMatrixFromPayloadValues(metric.values);
            if isempty(arr), return; end
            if isvector(arr)
                vals = arr(:);
            else
                seriesIndex = max(1, min(round(double(seriesIndex)), size(arr,2)));
                vals = arr(:,seriesIndex);
            end
        end

        function sem = metricSeriesSem(metric, seriesIndex, nRows)
            % metricSeriesSem  Extract one SEM/error series or NaNs when absent.
            if nargin < 3 || isempty(nRows), nRows = NMResultsViewerReportTools.metricRowCount(metric); end
            sem = NaN(nRows,1);
            if ~isstruct(metric) || ~isfield(metric,'sem') || ~isnumeric(metric.sem) || isempty(metric.sem)
                return;
            end
            arr = double(metric.sem);
            if isvector(arr)
                raw = arr(:);
            else
                seriesIndex = max(1, min(round(double(seriesIndex)), size(arr,2)));
                raw = arr(:,seriesIndex);
            end
            n = min(nRows, numel(raw));
            sem(1:n) = raw(1:n);
        end

        function label = metricSeriesLabel(metric, seriesIndex)
            % metricSeriesLabel  Return a metric-series label with fallback.
            labels = NMResultsViewerReportTools.safeCellstr(metric.seriesLabels);
            if seriesIndex >= 1 && seriesIndex <= numel(labels) && ~isempty(labels{seriesIndex})
                label = labels{seriesIndex};
            else
                label = sprintf('Series %d', seriesIndex);
            end
        end

        function metric = metricTemplateFallback()
            % metricTemplateFallback  Create an empty metric-like descriptor for schemas.
            metric = struct('id','','label','','family','','values',[],'sem',[], ...
                'seriesLabels',{{}},'unit','','higherIsBetter',false,'lowerIsBetter',false, ...
                'available',false,'missingReason','','sourceFields',{{}});
        end

        function [value, bestIndex] = aggregateValues(vals, aggregation, metric)
            % aggregateValues  Aggregate finite values for parameter-surface cells.
            vals = double(vals(:));
            aggregation = lower(strtrim(char(string(aggregation))));
            bestIndex = 1;
            switch aggregation
                case 'median'
                    value = median(vals);
                    [~, bestIndex] = min(abs(vals - value));
                case {'max','maximum'}
                    [value, bestIndex] = max(vals);
                case {'min','minimum'}
                    [value, bestIndex] = min(vals);
                case {'best','directional_best'}
                    if NMResultsViewerReportTools.metricDirectionSign(metric) > 0
                        [value, bestIndex] = max(vals);
                    else
                        [value, bestIndex] = min(vals);
                    end
                otherwise
                    value = mean(vals);
                    [~, bestIndex] = min(abs(vals - value));
            end
        end

        function signVal = metricDirectionSign(metric)
            % metricDirectionSign  Return +1 for larger-is-better and -1 otherwise.
            if metric.higherIsBetter
                signVal = 1;
            elseif metric.lowerIsBetter
                signVal = -1;
            else
                label = lower([metric.id ' ' metric.label ' ' metric.family]);
                if contains(label,'error') || contains(label,'complexity') || contains(label,'gap')
                    signVal = -1;
                else
                    signVal = 1;
                end
            end
        end

        function label = metricDirectionLabel(metric)
            % metricDirectionLabel  Return human-readable metric direction.
            if NMResultsViewerReportTools.metricDirectionSign(metric) > 0
                label = 'higher is better';
            else
                label = 'lower is better';
            end
        end

        function label = gridRowLabel(grid, idx)
            % gridRowLabel  Resolve a parameter-grid row label.
            label = sprintf('M%d', idx);
            if isstruct(grid) && isfield(grid,'parameterRows') && numel(grid.parameterRows) >= idx && isfield(grid.parameterRows(idx),'label')
                label = char(string(grid.parameterRows(idx).label));
            end
        end

        function txt = gridRowTooltip(grid, idx)
            % gridRowTooltip  Resolve a parameter-grid row tooltip.
            txt = '';
            if isstruct(grid) && isfield(grid,'parameterRows') && numel(grid.parameterRows) >= idx && isfield(grid.parameterRows(idx),'tooltip')
                txt = char(string(grid.parameterRows(idx).tooltip));
            end
        end


        function m = maxFinite(values)
            % maxFinite  Return the maximum finite value or zero when none exists.
            values = double(values(:));
            values = values(isfinite(values));
            if isempty(values)
                m = 0;
            else
                m = max(values);
            end
        end

        function v = valueAt(values, idx)
            % valueAt  Return a cell-array value at idx or an empty fallback.
            v = [];
            if iscell(values) && idx >= 1 && idx <= numel(values)
                v = values{idx};
            end
        end

        function key = valueKey(v)
            % valueKey  Create stable grouping key for parameter values.
            key = NMResultsViewerReportTools.valueText(v);
        end

        function txt = valueText(v)
            % valueText  Convert parameter value to readable text.
            if isempty(v)
                txt = '';
            elseif ischar(v) || isstring(v)
                txt = char(string(v));
            elseif isnumeric(v) || islogical(v)
                if isscalar(v)
                    txt = sprintf('%.12g', double(v));
                else
                    flat = double(v(:));
                    cells = cell(1, numel(flat));
                    for ii = 1:numel(flat), cells{ii} = sprintf('%.12g', flat(ii)); end
                    txt = ['[' strjoin(cells, ', ') ']'];
                end
            else
                txt = char(string(v));
            end
        end

        function txts = valueCellToText(values)
            % valueCellToText  Convert a value cell array to strings.
            if ~iscell(values)
                txts = {NMResultsViewerReportTools.valueText(values)};
                return;
            end
            txts = cell(1, numel(values));
            for ii = 1:numel(values)
                txts{ii} = NMResultsViewerReportTools.valueText(values{ii});
            end
        end

        function txt = indexListText(idx)
            % indexListText  Convert numeric indices to compact comma-separated text.
            idx = double(idx(:)');
            if isempty(idx)
                txt = '';
                return;
            end
            cells = cell(1, numel(idx));
            for ii = 1:numel(idx), cells{ii} = sprintf('%d', round(idx(ii))); end
            txt = strjoin(cells, ',');
        end

        function state = featureInspectionViewState(options)
            % featureInspectionViewState  Captured Feature Inspection view state, completed once per component.
            % The browser (NMResultsViewerUI_main.js::serializeFeatureInspectionViewState, schema 7) supplies
            % the full state; the report planner supplies part of it; API-built recipes omit it. The completed
            % state serves one component build or render and is never written back into Options, so recipes
            % and their serialization stay as captured. "No backprojection component selected" is NaN.
            state = struct('schemaVersion',NaN,'panels',struct(),'visiblePanelIds',{{}}, ...
                'selectedFeatureContextId','','selectedFeatureContext',struct(), ...
                'selectedBackprojectionComponentId','','selectedBackprojectionComponentIndex',NaN, ...
                'selectedBackprojectionComponentColumn',NaN,'selectedBackprojectionComponentLabel','');
            % nm2-allow: the captured state exists only for Feature Inspection captures (serializeFeatureInspectionViewState) and planner rebinds.
            if isfield(options,'BrowserFeatureInspectionViewState')
                state = NMResultsViewerReportTools.mergeStructs(state, options.BrowserFeatureInspectionViewState);
            end
            state.visiblePanelIds = NMResultsViewerReportTools.safeCellstr(state.visiblePanelIds);
        end

        function out = mergeStructs(base, overlay)
            % mergeStructs  Overlay fields from one scalar struct onto another.
            out = struct();
            if isstruct(base), out = base; end
            if ~isstruct(overlay), return; end
            names = fieldnames(overlay);
            for ii = 1:numel(names)
                out.(names{ii}) = overlay.(names{ii});
            end
        end

        function val = safeField(s, fieldName, default)
            % safeField  Read a struct field with explicit default fallback.
            val = default;
            if isstruct(s) && isfield(s, fieldName)
                val = s.(fieldName);
            end
        end



        function out = safeCellstr(raw)
            % safeCellstr  Normalize text metadata to row cellstr.
            if isempty(raw)
                out = {};
            elseif iscell(raw)
                out = cell(1, numel(raw));
                for ii = 1:numel(raw), out{ii} = char(string(raw{ii})); end
            elseif isstring(raw) || ischar(raw)
                out = cellstr(string(raw));
                out = out(:)';
            else
                out = cellstr(string(raw));
                out = out(:)';
            end
        end

        function txt = payloadMessage(payload, fallback)
            % payloadMessage  Resolve explicit payload status text.
            txt = fallback;
            if isstruct(payload) && isfield(payload,'message') && ~isempty(payload.message)
                txt = char(string(payload.message));
            end
        end

        function out = fixedStructArray(in, tmpl, label)
            % Purpose: Materialize JSON/MATLAB transport rows into one preallocated fixed-schema struct array.
            % Syntax: out = NMResultsViewerReportTools.fixedStructArray(in,tmpl,label)
            % Inputs: in is an empty value, a MATLAB struct array, or a cell array of scalar decoded JSON objects; tmpl is one scalar fixed-schema struct; label names the contract in diagnostics.
            % Outputs: out is a struct array preallocated from tmpl with input values copied only into declared fields.
            % Authority and flow: The fixed schema is owned by the supplied canonical template. This helper resolves transport representation only; it does not infer scientific or report semantics.
            % Scientific/state contract: JSON transport may erase MATLAB struct-array typing. Canonical report state is materialized from the existing schema template before downstream validation or planning.
            % Invariants: Every output row has exactly the template field set before values are assigned; undeclared fields and non-struct rows fail explicitly; no fields are added dynamically to an existing struct array.
            % Materialization and performance: O(N*F) compact metadata copies over N rows and F fixed schema fields with one preallocation; no payload, Scientific State, file/resource, voxel/vertex or feature-scale materialization.
            % Failure semantics: Invalid transport row type or undeclared field raises an explicit fixed-schema error; no permissive fallback or field repair is performed.
            % Side effects: None.
            % Consumers and dependencies: Report-spec normalization for AnalysisPlans and FeaturePresentations only.
            if nargin<3||isempty(label),label='Struct array';end
            if ~isstruct(tmpl)||~isscalar(tmpl)
                error('NMResultsViewerReportTools:InvalidFixedStructTemplate','%s requires one scalar fixed-schema template.',label);
            end
            if isempty(in)
                out=tmpl([]);
                return;
            end
            if ~(isstruct(in)||iscell(in))
                error('NMResultsViewerReportTools:InvalidFixedStructArray','%s must contain decoded struct rows.',label);
            end
            out=repmat(tmpl,1,numel(in));
            names=fieldnames(tmpl);
            for ii=1:numel(in)
                if isstruct(in),row=in(ii);else,row=in{ii};end
                if ~isstruct(row)||~isscalar(row)
                    error('NMResultsViewerReportTools:InvalidFixedStructArray','%s row %d must be one scalar struct.',label,ii);
                end
                extras=setdiff(fieldnames(row),names);
                if ~isempty(extras)
                    error('NMResultsViewerReportTools:InvalidFixedStructSchema', ...
                        '%s row %d contains undeclared field(s): %s.',label,ii,strjoin(extras,', '));
                end
                for jj=1:numel(names)
                    name=names{jj};
                    if isfield(row,name),out(ii).(name)=row.(name);end
                end
            end
        end

        function out = copyMissingFields(in, tmpl)
            % copyMissingFields  Add missing fixed-schema fields from a template.
            out = in;
            names = fieldnames(tmpl);
            for ii = 1:numel(names)
                if ~isfield(out, names{ii})
                    out.(names{ii}) = tmpl.(names{ii});
                end
            end
        end

        function txt = structText(s, names, default)
            % structText  Read one of several struct text fields.
            txt = default;
            if ~isstruct(s), return; end
            for ii = 1:numel(names)
                if isfield(s, names{ii}) && ~isempty(s.(names{ii}))
                    txt = char(string(s.(names{ii})));
                    return;
                end
            end
        end

        function x = structScalar(s, names, default)
            % structScalar  Read one of several struct scalar numeric fields.
            x = default;
            if ~isstruct(s), return; end
            for ii = 1:numel(names)
                if isfield(s, names{ii}) && ~isempty(s.(names{ii})) && isnumeric(s.(names{ii}))
                    v = double(s.(names{ii}));
                    if ~isempty(v) && isfinite(v(1))
                        x = v(1);
                        return;
                    end
                end
            end
        end

        function tf = structLogical(s, names, default)
            % structLogical  Read one of several struct logical fields.
            tf = default;
            if ~isstruct(s), return; end
            for ii = 1:numel(names)
                if isfield(s, names{ii}) && ~isempty(s.(names{ii}))
                    val = s.(names{ii});
                    if islogical(val) || isnumeric(val)
                        tf = logical(val(1));
                    else
                        txt = lower(strtrim(char(string(val))));
                        tf = any(strcmp(txt, {'true','1','yes','on'}));
                    end
                    return;
                end
            end
        end

        function validatePrebuiltReport(report)
            % Public exportReport boundary: require the fixed schema written by
            % buildReport rather than repairing missing fields in renderers.
            rootTemplate = NMResultsViewerReportTools.reportTemplate();
            componentTemplate = NMResultsViewerReportTools.reportComponentTemplate();
            % nm2-allow: external prebuilt report argument crosses the exportReport API boundary
            if ~isstruct(report) || ~isscalar(report)
                error('NMResultsViewerReportTools:InvalidPrebuiltReport', ...
                    'Prebuilt report must match the fixed buildReport/reportComponentTemplate schema.');
            end
            if ~isequal(sort(fieldnames(report)),sort(fieldnames(rootTemplate))) || ...
                    ~isequal(report.Kind,rootTemplate.Kind) || ~isequal(report.SchemaVersion,rootTemplate.SchemaVersion)
                error('NMResultsViewerReportTools:InvalidPrebuiltReport', ...
                    'Prebuilt report must match the fixed buildReport/reportComponentTemplate schema.');
            end
            % nm2-allow: external prebuilt report component schema validated at exportReport API boundary
            if ~isstruct(report.Components) || ...
                    ~isequal(sort(fieldnames(report.Components)),sort(fieldnames(componentTemplate)))
                error('NMResultsViewerReportTools:InvalidPrebuiltReport', ...
                    'Prebuilt report must match the fixed buildReport/reportComponentTemplate schema.');
            end
            contextFields = {'AnalysisTitle','Source','ResultType','ClassifierScope', ...
                'ClassifierLabels','IncludedSections','AnalysisIndices','AnalysisLabels'};
            % nm2-allow: external exportReport prebuilt Context is validated against reportContextFromSpec
            if ~isstruct(report.Context) || ~isscalar(report.Context) || ...
                    ~all(isfield(report.Context,contextFields)) || ~isstruct(report.Metadata) % nm2-allow: externally supplied report schema is validated at exportReport public boundary
                error('NMResultsViewerReportTools:InvalidPrebuiltReport', ...
                    'Prebuilt report context does not match reportContextFromSpec.');
            end
            for cc = 1:numel(report.Components)
                c = report.Components(cc);
                % nm2-allow: external exportReport prebuilt component nested tables and warnings require writer-defined types
                if ~isstruct(c.Tables) || ~isstruct(c.SidecarTables) || ...
                        ~isstruct(c.Options) || ~iscell(c.Warnings) % nm2-allow: externally supplied component values are validated at exportReport public boundary
                    error('NMResultsViewerReportTools:InvalidPrebuiltReport', ...
                        'Prebuilt report component must preserve writer-defined table, options and warning types.');
                end
            end
        end

        function exportSpec = normalizeExportSpec(exportSpec)
            % Report-export API ingress: canonical names and report-only defaults.
            if ~isstruct(exportSpec) || ~isscalar(exportSpec)
                error('NMResultsViewerReportTools:InvalidExportSpecShape', ...
                    'Export specification must be one scalar struct.');
            end
            defaults=NMResultsViewerReportTools.exportSpecDefaults();
            unknown=setdiff(fieldnames(exportSpec),fieldnames(defaults));
            if ~isempty(unknown)
                error('NMResultsViewerReportTools:UnknownExportOption', ...
                    'Unknown export option(s): %s.',strjoin(unknown,', '));
            end
            exportSpec=NMResultsViewerReportTools.copyMissingFields(exportSpec,defaults);
            exportSpec.Format=lower(strtrim(char(string(exportSpec.Format)))); % nm2-allow: report export format and presentation options are normalized at their single owner.
            if ~ismember(exportSpec.Format,{'mat','json','csv','xlsx','html','pdf'}) % nm2-allow: report export format and presentation options are normalized at their single owner.
                error('NMResultsViewerReportTools:InvalidExportFormat', ...
                    'Unsupported report export format "%s".',exportSpec.Format);
            end
            exportSpec.OutputDirectory=char(string(exportSpec.OutputDirectory)); % nm2-allow: report export format and presentation options are normalized at their single owner.
            exportSpec.OutputFile=char(string(exportSpec.OutputFile)); % nm2-allow: report export format and presentation options are normalized at their single owner.
            if isempty(exportSpec.OutputDirectory),exportSpec.OutputDirectory=pwd;end
            if isempty(exportSpec.BaseName)
                exportSpec.BaseName=['NM_results_viewer_report_' datestr(now,'yyyymmdd_HHMMSS')];
            end
            exportSpec.BaseName=NMResultsViewerReportTools.sanitizeFileToken(exportSpec.BaseName);
            exportSpec.MaxTableRows=max(1,min(1000,round(double(exportSpec.MaxTableRows))));
            exportSpec.MaxSummaryRows=max(1,min(25,round(double(exportSpec.MaxSummaryRows))));
            exportSpec.PdfRenderer=char(string(exportSpec.PdfRenderer)); % nm2-allow: report export format and presentation options are normalized at their single owner.
            exportSpec.PdfRendererKind=lower(strtrim(char(string(exportSpec.PdfRendererKind)))); % nm2-allow: report export format and presentation options are normalized at their single owner.
            mode=lower(strtrim(char(string(exportSpec.ReportMode)))); % nm2-allow: report export format and presentation options are normalized at their single owner.
            if isempty(mode)
                if ismember(exportSpec.Format,{'html','pdf'}),mode='summary';else,mode='technical';end % nm2-allow: report export format and presentation options are normalized at their single owner.
            elseif ~ismember(mode,{'summary','full','technical','technical_text'}) % nm2-allow: report export format and presentation options are normalized at their single owner.
                error('NMResultsViewerReportTools:InvalidReportMode', ...
                    'Unsupported report mode "%s".',mode);
            end
            exportSpec.ReportMode=mode;
            exportSpec.PdfTarget=logical(exportSpec.PdfTarget);
            exportSpec.PdfTempProfileDirectory=char(string(exportSpec.PdfTempProfileDirectory)); % nm2-allow: report export format and presentation options are normalized at their single owner.
        end

        function defaults = exportSpecDefaults()
            % exportSpecDefaults  The complete report-export option set with its defaults.
            % normalizeExportSpec completes and validates an export spec from this table;
            % the public component renderer completes a caller's spec from it.
            defaults=struct('Format','html','OutputDirectory',pwd,'OutputFile','', ...
                'BaseName','','IncludePayloadMat',false,'IncludeHtml',false, ...
                'MaxTableRows',100,'PdfRenderer','','PdfRendererKind','', ...
                'ReportMode','','MaxSummaryRows',8,'PdfTarget',false, ...
                'MaxPlottedFeatures',50,'LabelTopN',25,'MinFeatureLabelFontPt',9, ...
                'MaxFeatureBarSvgHeight',760,'PdfMaxPlottedFeatures',32,'PdfLabelTopN',32, ...
                'PdfMinFeatureLabelFontPt',8,'PdfMaxFeatureBarSvgHeight',620, ...
                'PdfTempProfileDirectory','');
        end

        function out = exportOut(ok, fmt, primaryPath, paths, message)
            % exportOut  Build a fixed-schema report-export status response.
            out = struct('ok',logical(ok),'message',message, ...
                'format',fmt,'path',primaryPath, ...
                'paths',{paths},'createdAt',datestr(now, 30));
        end

        function outPath = exportPath(exportSpec, ext)
            % exportPath  Resolve a non-overwriting report-export path.
            outFile = exportSpec.OutputFile;
            if ~isempty(outFile)
                [pth, nam] = fileparts(outFile);
                if isempty(pth), pth = exportSpec.OutputDirectory; end
                outPath = fullfile(pth, [NMResultsViewerReportTools.sanitizeFileToken(nam) '.' ext]);
                return;
            end
            outPath = NMSerializationTools.uniqueOutputPath(exportSpec.OutputDirectory, exportSpec.BaseName, ext);
        end

        function sidePath = sidecarPath(primaryPath, suffix, ext)
            % sidecarPath  Resolve a non-overwriting sidecar path next to a primary export.
            [pth, nam] = fileparts(primaryPath);
            sidePath = NMSerializationTools.uniqueOutputPath(pth, [nam suffix], ext);
        end

        function renderer = resolvePdfRenderer(exportSpec)
            % resolvePdfRenderer  Locate the HTML-to-PDF renderer used by PDF export.
            %
            % Renderer lookup is deterministic and explicit: a user override in
            % exportSpec.PdfRenderer is tried first, followed by installed
            % Chromium/Chrome/Edge executables and then wkhtmltopdf. The function
            % returns a fixed-schema descriptor plus a probe log suitable for the
            % NM2 message strip when no renderer is available.
            renderer = struct('ok',false,'name','none','kind','none','executable','', ...
                'probeLog','','isOverride',false);
            log = cell(1,0);
            override = exportSpec.PdfRenderer;
            candidates = NMResultsViewerReportTools.pdfRendererCandidates();
            if ~isempty(override)
                kind = exportSpec.PdfRendererKind;
                if any(strcmp(kind, {'chrome','edge'}))
                    kind = 'chromium';
                elseif ~ismember(kind, {'chromium','wkhtmltopdf'})
                    [~, basename] = fileparts(override);
                    kind = 'chromium';
                    if contains(lower(basename), 'wkhtml'), kind = 'wkhtmltopdf'; end
                end
                candidates = [struct('kind', kind, 'executable', override), candidates];
            end
            candidates(end+1) = NMResultsViewerReportTools.bundledPdfRendererCandidate();
            for ii = 1:numel(candidates)
                cand = candidates(ii);
                [exe, msg] = NMResultsViewerReportTools.resolveExecutable(cand.executable);
                isOverride = ii == 1 && ~isempty(override);
                label = cand.kind;
                if isOverride, label = 'override'; end
                log{end+1} = sprintf('%s=%s -> %s', label, cand.executable, msg); %#ok<AGROW>
                if ~isempty(exe)
                    renderer.ok = true;
                    renderer.executable = exe;
                    renderer.kind = cand.kind;
                    renderer.name = sprintf('%s:%s', renderer.kind, exe);
                    renderer.isOverride = isOverride;
                    renderer.probeLog = strjoin(log, '; ');
                    return;
                end
            end
            renderer.probeLog = strjoin(log, '; ');
        end

        function candidates = pdfRendererCandidates()
            % pdfRendererCandidates  Return platform-specific HTML-to-PDF candidates.
            candidates = struct('kind',{},'executable',{});
            if ispc
                paths = { ...
                    fullfile(getenv('ProgramFiles'), 'Google', 'Chrome', 'Application', 'chrome.exe'), ...
                    fullfile(getenv('ProgramFiles(x86)'), 'Google', 'Chrome', 'Application', 'chrome.exe'), ...
                    fullfile(getenv('LocalAppData'), 'Google', 'Chrome', 'Application', 'chrome.exe'), ...
                    fullfile(getenv('ProgramFiles'), 'Microsoft', 'Edge', 'Application', 'msedge.exe'), ...
                    fullfile(getenv('ProgramFiles(x86)'), 'Microsoft', 'Edge', 'Application', 'msedge.exe'), ...
                    'chrome.exe', 'msedge.exe', 'chromium.exe', 'wkhtmltopdf.exe'};
            elseif ismac
                paths = { ...
                    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ...
                    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge', ...
                    '/Applications/Chromium.app/Contents/MacOS/Chromium', ...
                    'google-chrome', 'chrome', 'chromium', 'chromium-browser', 'microsoft-edge', 'wkhtmltopdf'};
            else
                paths = {'google-chrome','google-chrome-stable','chromium','chromium-browser','microsoft-edge','microsoft-edge-stable','wkhtmltopdf'};
            end
            for ii = 1:numel(paths)
                candidates(end+1) = struct('kind','chromium','executable',paths{ii}); %#ok<AGROW>
            end
            candidates(end).kind = 'wkhtmltopdf';
        end

        function candidate = bundledPdfRendererCandidate()
            % Bundled Chrome for Testing Headless Shell, selected by MATLAB host architecture.
            switch computer('arch')
                case 'win64', platform = 'win64';
                case 'win32', platform = 'win32';
                case 'maci64', platform = 'mac-x64';
                case 'maca64', platform = 'mac-arm64';
                case 'glnxa64', platform = 'linux64';
                case 'glnxaarch64', platform = 'linux-arm64';
                otherwise
                    error('NMResultsViewerReportTools:UnsupportedPdfPlatform', ...
                        'No bundled PDF renderer for MATLAB architecture %s.', computer('arch'));
            end
            executable = 'chrome-headless-shell';
            if ispc, executable = [executable '.exe']; end
            root = fileparts(fileparts(which('NMResultsViewerReportTools')));
            location = fullfile(root, 'thirdparty', 'chrome-headless-shell', platform, ...
                ['chrome-headless-shell-' platform], executable);
            candidate = struct('kind', 'chromium', 'executable', location);
        end

        function [exe, msg] = resolveExecutable(candidate)
            % resolveExecutable  Resolve an executable path or PATH command token.
            exe = '';
            % Executable candidates come from normalized export input or pdfRendererCandidates.
            % nm2-allow: external PDF executable selection explicitly checks installed filesystem resources
            if exist(candidate, 'file') == 2
                exe = candidate;
                msg = 'found as file';
            else
                hasSep = contains(candidate, filesep) || contains(candidate, '/') || contains(candidate, '\');
                if hasSep
                    msg = 'not found as file';
                    return;
                end
                if ispc
                    probe = sprintf('where %s', NMResultsViewerReportTools.shellQuote(candidate));
                else
                    probe = sprintf('command -v %s', NMResultsViewerReportTools.shellQuote(candidate));
                end
                [status, output] = system(probe);
                output = strtrim(output);
                if status == 0 && ~isempty(output)
                    parts = regexp(output, '\r?\n', 'split');
                    exe = strtrim(parts{1});
                    msg = sprintf('found on PATH: %s', exe);
                else
                    msg = 'not found on PATH';
                end
            end
            % Snap launchers require snap-managed cgroups. SLURM job steps do not
            % provide those cgroups, so a discovered launcher is not usable.
            % Allow the existing candidate search to reach a native renderer.
            if ~isempty(exe) && ~isempty(getenv('SLURM_JOB_ID')) && ...
                    (startsWith(exe, '/snap/bin/') || startsWith(exe, '/var/lib/snapd/snap/bin/'))
                msg = sprintf('Snap launcher %s is not usable in a SLURM job; select a non-Snap Chrome/Chromium or wkhtmltopdf installation', exe);
                exe = '';
            end
        end

        function [ok, message] = writePdfFromHtml(htmlPath, pdfPath, renderer, exportSpec)
            % writePdfFromHtml  Convert a static HTML report into a paginated PDF.
            %
            % The generated PDF is produced from the same self-contained HTML/SVG
            % renderer used for the HTML sidecar. Failures are explicit; no textual
            % Alternate PDF rendering is produced outside ReportMode="technical_text".
            if strcmpi(renderer.kind, 'wkhtmltopdf')
                cmd = NMResultsViewerReportTools.wkhtmltopdfCommand(renderer.executable, htmlPath, pdfPath, exportSpec);
            else
                cmd = NMResultsViewerReportTools.chromiumPdfCommand(renderer.executable, htmlPath, pdfPath, exportSpec);
            end
            [status, output] = system(cmd);
            output = strtrim(output);
            if status ~= 0
                ok = false;
                message = sprintf('Command failed with status %d. %s', status, output);
                return;
            end
            % nm2-allow: external PDF command completion must be checked against the resulting output file
            if exist(pdfPath, 'file') ~= 2
                ok = false;
                message = sprintf('Renderer command completed but PDF was not created. %s', output);
                return;
            end
            d = dir(pdfPath);
            if isempty(d) || d(1).bytes < 512
                ok = false;
                message = sprintf('Renderer created an unexpectedly small PDF file. %s', output);
                return;
            end
            ok = true;
            message = sprintf('PDF created with %s.', renderer.name);
        end

        function cmd = chromiumPdfCommand(executable, htmlPath, pdfPath, exportSpec)
            % chromiumPdfCommand  Build a headless Chromium/Chrome/Edge print command.
            profileDir = exportSpec.PdfTempProfileDirectory;
            if isempty(profileDir)
                profileDir = tempname;
                mkdir(profileDir);
            % nm2-allow: PDF renderer profile directory is an externally selected filesystem resource.
            elseif exist(profileDir, 'dir') ~= 7
                mkdir(profileDir);
            end
            uri = NMResultsViewerReportTools.fileUri(htmlPath);
            parts = {NMResultsViewerReportTools.shellQuote(executable), ...
                '--headless=new', '--disable-gpu', '--no-first-run', '--disable-extensions', ...
                '--disable-dev-shm-usage', '--allow-file-access-from-files', '--no-pdf-header-footer', '--print-to-pdf-no-header', ...
                ['--user-data-dir=' NMResultsViewerReportTools.shellQuote(profileDir)], ...
                ['--print-to-pdf=' NMResultsViewerReportTools.shellQuote(pdfPath)], ...
                NMResultsViewerReportTools.shellQuote(uri)};
            cmd = strjoin(parts, ' ');
        end

        function cmd = wkhtmltopdfCommand(executable, htmlPath, pdfPath, exportSpec)
            % wkhtmltopdfCommand  Build a wkhtmltopdf command for static report HTML.
            %#ok<INUSD> exportSpec reserved for future renderer-specific options.
            parts = {NMResultsViewerReportTools.shellQuote(executable), '--enable-local-file-access', '--page-size', 'A4', ...
                '--margin-top', '15mm', '--margin-right', '15mm', '--margin-bottom', '15mm', '--margin-left', '15mm', ...
                NMResultsViewerReportTools.shellQuote(htmlPath), NMResultsViewerReportTools.shellQuote(pdfPath)};
            cmd = strjoin(parts, ' ');
        end

        function uri = fileUri(path)
            % fileUri  Convert a local file path to a file:// URI accepted by browsers.
            path = strrep(path, '\', '/');
            if ispc && ~startsWith(path, '/')
                uri = ['file:///' path];
            elseif startsWith(path, '/')
                uri = ['file://' path];
            else
                uri = ['file:///' path];
            end
        end

        function q = shellQuote(txt)
            % shellQuote  Quote one command-line argument for system shell calls.
            txt = strrep(txt, '"', '\"');
            q = ['"' txt '"'];
        end

        function token = sanitizeFileToken(txt)
            % sanitizeFileToken  Sanitize a report filename token.
            token = regexprep(txt, '[^A-Za-z0-9_\-]+', '_');
            token = regexprep(token, '_+', '_');
            token = regexprep(token, '^_+|_+$', '');
            if isempty(token), token = 'NM_results_viewer_report'; end
        end

        function html = renderReportHtml(report, exportSpec)
            % renderReportHtml  Render a static, DOM-independent HTML report.
            %
            % report: payload returned by buildReport.
            % exportSpec.ReportMode: "summary" for a curated scientific report or
            %                        "technical" for the exhaustive payload-table
            %                        audit view.
            mode = exportSpec.ReportMode;
            if strcmp(mode, 'technical')
                html = NMResultsViewerReportTools.renderReportHtmlTechnical(report, exportSpec);
            else
                html = NMResultsViewerReportTools.renderReportHtmlSummary(report, exportSpec);
            end
        end

        function html = renderReportHtmlTechnical(report, exportSpec)
            % renderReportHtml  Render a static, DOM-independent HTML report.
            %
            % report: payload returned by buildReport.
            % exportSpec.MaxTableRows: maximum rows rendered per table preview.
            titleText = NMResultsViewerReportTools.htmlEscape(report.Title);
            desc = NMResultsViewerReportTools.htmlEscape(report.Description);
            comps = report.Components;
            css = ['body{font-family:Arial,Helvetica,sans-serif;margin:24px;color:#111827;background:#fff}' ...
                'h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:22px 0 8px;border-bottom:1px solid #dbe4ef;padding-bottom:4px}' ...
                'h3{font-size:13px;margin:14px 0 6px}.reportAnalysisHeading{padding:8px 10px;border-left:6px solid #0f4c81;background:#eaf3fb;color:#0f172a}.reportOOCVGroupHeading{padding:7px 9px;border-left:4px solid #475569;background:#f8fafc;color:#0f172a}.meta{color:#475569;font-size:12px;margin-bottom:18px}.desc{color:#334155;margin:8px 0 16px}' ...
                '.component{border:1px solid #dbe4ef;border-radius:10px;padding:12px;margin:12px 0;page-break-inside:avoid}.ok{}.unavailable{border-left:4px solid #dc2626}.status{font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:#64748b}.reason{color:#9a3412;background:#fff7ed;border:1px solid #fed7aa;padding:6px 8px;border-radius:6px;margin:7px 0}table{border-collapse:collapse;width:100%;font-size:11px;margin:7px 0 12px}th,td{border:1px solid #d1d5db;padding:4px 6px;text-align:left;vertical-align:top}th{background:#f3f4f6}code,pre{font-family:Consolas,Monaco,monospace;font-size:11px}pre{background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px;padding:8px;white-space:pre-wrap;overflow-wrap:anywhere}.small{font-size:11px;color:#64748b}@media print{body{margin:12mm}.component{break-inside:avoid}}'];
            body = {sprintf('<h1>%s</h1>', titleText), sprintf('<div class="meta">Generated %s by NMResultsViewerReportTools.exportReport</div>', datestr(now)), ...
                sprintf('<div class="desc">%s</div>', desc), NMResultsViewerReportTools.reportContextHtml(report)};
            ctx=report.Context;analysisIndices=double(ctx.AnalysisIndices);analysisLabels=ctx.AnalysisLabels;lastAnalysisIndex=NaN;lastOOCVGroup='';
            for ii = 1:numel(comps)
                meta=comps(ii).Metadata;componentAnalysisIndex=meta.AnalysisIndex;
                % nm2-allow: reportContextFromSpec owns ordered analysis coordinates while optional display labels may be absent
                if numel(analysisIndices)>1&&isfinite(componentAnalysisIndex)&&~isequal(componentAnalysisIndex,lastAnalysisIndex)
                    % nm2-allow: reportContextFromSpec owns ordered analysis coordinates while optional display labels may be absent
                    pos=find(analysisIndices==componentAnalysisIndex,1,'first');if ~isempty(pos)&&pos<=numel(analysisLabels),analysisLabel=analysisLabels{pos};else,analysisLabel=sprintf('Analysis %d',round(componentAnalysisIndex));end
                    body{end+1}=sprintf('<h2 class="reportAnalysisHeading">%s</h2>',NMResultsViewerReportTools.htmlEscape(analysisLabel)); %#ok<AGROW>
                    lastAnalysisIndex=componentAnalysisIndex;lastOOCVGroup='';
                end
                viewspace=comps(ii).Viewspace;inst=comps(ii).Instance;
                oocvGroupIndex=inst.OOCVSubgroupIndex;oocvGroupLabel=inst.OOCVSubgroupLabel;
                if strcmpi(viewspace,'model_performance')&&isfinite(oocvGroupIndex)&&~isempty(oocvGroupLabel)
                    oocvGroupKey=sprintf('oocv:%d:%s',round(oocvGroupIndex),oocvGroupLabel);
                    if ~strcmp(oocvGroupKey,lastOOCVGroup),body{end+1}=sprintf('<h3 class="reportOOCVGroupHeading">%s</h3>',NMResultsViewerReportTools.htmlEscape(oocvGroupLabel));lastOOCVGroup=oocvGroupKey;end %#ok<AGROW>
                end
                body{end+1} = NMResultsViewerReportTools.componentHtml(comps(ii), exportSpec); %#ok<AGROW>
            end
            html = sprintf('<!doctype html><html><head><meta charset="utf-8"><title>%s</title><style>%s</style></head><body>%s</body></html>', ...
                titleText, css, strjoin(body, sprintf('\n')));
        end

        function html = reportContextHtml(report)
            % reportContextHtml  Render report-level context metadata.
            ctx = report.Context;
            rows = NMResultsViewerReportTools.dataToCell(ctx, 20);
            html = ['<h2>Report context</h2><div class="reportContextTable">' NMResultsViewerReportTools.cellTableHtml(rows, 20) '</div>'];
        end

        function html = componentHtml(component, exportSpec)
            % componentHtml  Render one component summary and table previews.
            status = component.Status;
            cls = 'component';
            if strcmpi(status,'ok'), cls = [cls ' ok']; else, cls = [cls ' unavailable']; end
            titleText = NMResultsViewerReportTools.htmlEscape(component.Title);
            idText = NMResultsViewerReportTools.htmlEscape(component.Id);
            viewText = NMResultsViewerReportTools.htmlEscape(component.Viewspace);
            reason = component.MissingReason;
            parts = {sprintf('<section class="%s"><h2>%s</h2><div class="status">%s | %s | %s</div>', cls, titleText, NMResultsViewerReportTools.htmlEscape(status), idText, viewText)};
            if ~isempty(reason)
                parts{end+1} = sprintf('<div class="reason">%s</div>', NMResultsViewerReportTools.htmlEscape(reason)); %#ok<AGROW>
            end
            tableHtml = NMResultsViewerReportTools.componentTablesHtml(component, exportSpec.MaxTableRows);
            if isempty(tableHtml)
                parts{end+1} = '<div class="small">No table payload was exposed by this component.</div>'; %#ok<AGROW>
            else
                parts{end+1} = tableHtml; %#ok<AGROW>
            end
            parts{end+1} = '</section>';
            html = strjoin(parts, sprintf('\n'));
        end

        function html = componentTablesHtml(component, maxRows)
            % componentTablesHtml  Render all table-like payloads of one component.
            html = '';
            tables = component.Tables;
            names = fieldnames(tables);
            chunks = cell(1,0);
            for ii = 1:numel(names)
                data = tables.(names{ii});
                if isempty(data), continue; end
                cells = NMResultsViewerReportTools.dataToCell(data, maxRows);
                if isempty(cells), continue; end
                chunks{end+1} = sprintf('<h3>%s</h3>%s', NMResultsViewerReportTools.htmlEscape(names{ii}), NMResultsViewerReportTools.cellTableHtml(cells, maxRows)); %#ok<AGROW>
            end
            html = strjoin(chunks, sprintf('\n'));
        end

        function html = cellTableHtml(cells, maxRows)
            % cellTableHtml  Render a cell matrix as bounded HTML table markup.
            if isempty(cells), html = ''; return; end
            nRows = min(size(cells,1), maxRows + 1);
            nCols = size(cells,2);
            headers = cell(1,nCols);
            for cc = 1:nCols
                headers{cc} = NMResultsViewerReportTools.valuePreview(cells{1,cc});
            end
            rows = cell(1,nRows);
            for rr = 1:nRows
                tag = 'td'; if rr == 1, tag = 'th'; end
                vals = cell(1,nCols);
                for cc = 1:nCols
                    rawValue = cells{rr,cc};
                    vals{cc} = sprintf('<%s%s>%s</%s>', tag, NMResultsViewerReportTools.tableCellClassAttr(headers{cc}, rawValue), NMResultsViewerReportTools.htmlEscape(NMResultsViewerReportTools.valuePreview(rawValue)), tag);
                end
                rows{rr} = ['<tr>' strjoin(vals, '') '</tr>'];
            end
            more = '';
            if size(cells,1) > nRows
                more = sprintf('<div class="small">Showing %d of %d rows.</div>', nRows-1, size(cells,1)-1);
            end
            html = ['<table class="scientificTable">' strjoin(rows, sprintf('\n')) '</table>' more];
        end

        function txt = htmlEscape(txt)
            % htmlEscape  Escape text for static report HTML.
            txt = strrep(txt, '&', '&amp;');
            txt = strrep(txt, '<', '&lt;');
            txt = strrep(txt, '>', '&gt;');
            txt = strrep(txt, '"', '&quot;');
            txt = strrep(txt, '''', '&#39;');
        end


        function blocks = reportTableBlocks(NM,report)
            % Export full feature metrics once; retain generic tables for other components.
            comps = report.Components;
            blocks = cell(1,0);
            selected = arrayfun(@(c) strcmp(c.Instance.ComponentType,'feature_metric'),comps);
            if any(selected)
                parts = cell(1,0);
                for c = comps(selected)
                    spec = struct('resultType','model_feature_inspection', ...
                        'analysisIndex',c.Payload.analysisIndex,'targetIndex',c.Payload.targetIndex, ...
                        'classifierIndex',c.Payload.classifierIndex,'source',report.Context.Source, ...
                        'featureContextId',c.Instance.FeatureContextId, ...
                        'backprojectionComponentId',c.Instance.BackprojectionComponentId, ...
                        'featureInspectionPayloadScope','metadata');
                    metadata = NMResultsViewerTools.getModelFeatureInspectionPayload(NM,spec);
                    assert(metadata.ok,'%s',metadata.message);
                    for ctx = metadata.contexts
                        spec.featureContextId = ctx.contextId;
                        [exact, dispersion] = NMResultsViewerTools.getModelFeatureInspectionMeasureVector(NM,spec,c.Instance.MetricId,[]);
                        assert(exact.ok,'%s',exact.message);
                        n = numel(exact.values);
                        parts{end+1} = table(repmat(exact.analysisIndex,n,1),repmat(exact.targetIndex,n,1), ...
                            repmat(exact.classifierIndex,n,1),repmat({ctx.contextId},n,1), ...
                            repmat({ctx.modalityLabel},n,1),repmat({c.Instance.BackprojectionComponentLabel},n,1), ...
                            (1:n)',exact.featureNames(:),repmat({exact.measure.measureId},n,1),exact.values(:), ...
                            'VariableNames',{'Analysis','Target','Classifier','ContextId','Modality', ...
                            'Component','FeatureIndex','FeatureName','Metric','Value'});
                        % Reuse the exact same feature coordinates for the companion statistic.
                        if ~isempty(dispersion.values)
                            parts{end+1} = parts{end};
                            parts{end}.Metric = repmat({dispersion.metricId},n,1);
                            parts{end}.Value = dispersion.values;
                        end
                    end
                end
                records = vertcat(parts{:});
                [scientific,~,featureRow] = unique(records(:,1:8),'rows','stable');
                [metricNames,~,metricColumn] = unique(records.Metric,'stable');
                values = nan(height(scientific),numel(metricNames));
                values(sub2ind(size(values),featureRow,metricColumn)) = records.Value;
                scientific = [scientific array2table(values,'VariableNames',metricNames(:)')];
                scientific.ContextId = [];
                blocks{end+1} = struct('SheetName','Features','FileToken','features', ...
                    'Cells',{[scientific.Properties.VariableNames; table2cell(scientific)]});
            end
            for ii = find(~selected)
                for group = 1:2
                    if group==1, tables=comps(ii).Tables; else, tables=comps(ii).SidecarTables; end
                    for name = fieldnames(tables)'
                        key=name{1};
                        % nm2-allow: generated sidecar table field names may collide with primary report tables
                        if group==2 && isfield(comps(ii).Tables,key), key=['sidecar_' key]; end
                        cells = NMResultsViewerReportTools.dataToCell(tables.(name{1}), Inf);
                        if isempty(cells), continue; end
                        inst=comps(ii).Instance;
                        subgroupLabel=inst.OOCVSubgroupLabel;subgroupIndex=inst.OOCVSubgroupIndex;
                        if isempty(subgroupLabel)||~isfinite(subgroupIndex),baseName=sprintf('%02d_%s',ii,key);else,baseName=sprintf('%02d_g%d_%s_%s',ii,round(subgroupIndex),subgroupLabel,key);end
                        blocks{end+1} = struct('SheetName',baseName,'FileToken',baseName,'Cells',{cells}); %#ok<AGROW>
                    end
                end
            end
        end

        function cells = dataToCell(data, maxRows)
            % dataToCell  Convert writer-produced cell tables and struct records.
            cells = cell(0,0);
            if isempty(data), return; end
            % nm2-allow: NMResultsViewerCrossAnalysisTools writes cell tables while ReportTools component writers write struct rows
            if iscell(data)
                n = min(size(data,1), maxRows);
                cells = data(1:n,:);
                return;
            end
            % nm2-allow: reportExportMetadata writes flat metadata whereas reportContextFromSpec writes composite field values
            if isscalar(data) && all(structfun(@(x) ~(isstruct(x) || iscell(x)) || ischar(x) || isstring(x), data))
                cells = [{'Field','Value'}; fieldnames(data), struct2cell(data)];
            else
                data = data(:);
                names = fieldnames(data);
                n = min(numel(data), maxRows);
                cells = [names'; reshape(struct2cell(data(1:n)),numel(names),n)'];
            end
        end

        function txt = valuePreview(v)
            % valuePreview  Format cells of the writer-produced report tables.
            if isempty(v)
                txt = '';
            % nm2-allow: component row writers produce both character and MATLAB string text
            elseif ischar(v) || isstring(v)
                txt = char(v);
            % nm2-allow: component row writers produce numeric and logical scalar or array values
            elseif isnumeric(v) || islogical(v)
                if ~isscalar(v)
                    dims = sprintf('%dx', size(v));
                    txt = sprintf('[%s %s]', dims(1:end-1), class(v));
                % nm2-allow: component row writers supply logical scalars that need boolean display words
                elseif islogical(v)
                    if v, txt = 'true'; else, txt = 'false'; end
                else
                    txt = NMResultsViewerReportTools.compactNumericText(double(v));
                end
            % nm2-allow: reportContextFromSpec includes cell vectors as metadata values
            elseif iscell(v)
                txt = sprintf('{%d cell}', numel(v));
            % nm2-allow: scientific report row fields can contain nested struct values
            elseif isstruct(v)
                txt = sprintf('[%d struct]', numel(v));
            else
                error('NMResultsViewerReportTools:UnsupportedTableValue', ...
                    'Report table cell has unsupported type %s.', class(v));
            end
        end

        function txt = compactNumericText(v)
            % compactNumericText  Format scalar numeric values for visible scientific tables.
            if ~isfinite(v)
                txt = char(8212);
                return;
            end
            if abs(v) < 100
                txt = sprintf('%.3f', v);
                txt = regexprep(txt, '0+$', '');
                txt = regexprep(txt, '\.$', '');
                if strcmp(txt, '-0'), txt = '0'; end
            else
                txt = sprintf('%.3g', v);
            end
        end

        function writeSimplePdfReport(report, outPath, exportSpec)
            % writeSimplePdfReport  Write a dependency-free textual PDF report.
            %
            % The PDF intentionally summarizes API report components and table
            % previews from the report payload. It does not use browser-rendered SVGs
            % and does not require MATLAB Report Generator.
            lines = NMResultsViewerReportTools.reportTextLines(report, exportSpec);
            wrapped = NMResultsViewerReportTools.wrapTextLines(lines, 96);
            pageLines = 58;
            nPages = max(1, ceil(numel(wrapped) / pageLines));
            objects = cell(1, 3 + 2*nPages);
            kids = cell(1, nPages);
            for pp = 1:nPages
                pageObj = 4 + (pp-1)*2;
                contObj = pageObj + 1;
                kids{pp} = sprintf('%d 0 R', pageObj);
                i1 = (pp-1)*pageLines + 1;
                i2 = min(numel(wrapped), pp*pageLines);
                content = NMResultsViewerReportTools.pdfPageContent(wrapped(i1:i2), pp, nPages);
                objects{contObj} = sprintf('<< /Length %d >>\nstream\n%s\nendstream', numel(uint8(content)), content);
                objects{pageObj} = sprintf('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>', contObj);
            end
            objects{1} = '<< /Type /Catalog /Pages 2 0 R >>';
            objects{2} = sprintf('<< /Type /Pages /Kids [%s] /Count %d >>', strjoin(kids, ' '), nPages);
            objects{3} = '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>';
            pdf = sprintf('%%PDF-1.4\n%% NM Results Viewer report\n');
            offsets = zeros(1, numel(objects));
            for ii = 1:numel(objects)
                offsets(ii) = numel(uint8(pdf));
                pdf = [pdf sprintf('%d 0 obj\n%s\nendobj\n', ii, objects{ii})]; %#ok<AGROW>
            end
            xref = numel(uint8(pdf));
            pdf = [pdf sprintf('xref\n0 %d\n0000000000 65535 f \n', numel(objects)+1)];
            for ii = 1:numel(objects)
                pdf = [pdf sprintf('%010d 00000 n \n', offsets(ii))]; %#ok<AGROW>
            end
            pdf = [pdf sprintf('trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n', numel(objects)+1, xref)];
            NMSerializationTools.writeBytes(outPath, uint8(pdf));
        end

        function lines = reportTextLines(report, exportSpec)
            % reportTextLines  Build plain-text report lines for PDF rendering.
            %
            % exportSpec.ReportMode: "summary" suppresses exhaustive payload dumps and
            %                        emits an interpretable scientific synopsis;
            %                        "technical" preserves the full table-audit view.
            mode = exportSpec.ReportMode;
            if strcmp(mode, 'technical')
                lines = NMResultsViewerReportTools.reportTechnicalTextLines(report, exportSpec);
            else
                lines = NMResultsViewerReportTools.reportSummaryTextLines(report, exportSpec);
            end
        end

        function lines = reportTechnicalTextLines(report, exportSpec)
            % reportTextLines  Build plain-text report lines for PDF rendering.
            comps = report.Components;
            lines = {NMResultsViewerReportTools.safeAscii(report.Title); ...
                ['Generated: ' datestr(now)]; ...
                ['Description: ' NMResultsViewerReportTools.safeAscii(report.Description)]; ...
                sprintf('Components: %d', numel(comps)); ''};
            maxRows = min(20, exportSpec.MaxTableRows);
            for ii = 1:numel(comps)
                status = comps(ii).Status;
                lines{end+1} = sprintf('%d. %s [%s]', ii, NMResultsViewerReportTools.safeAscii(comps(ii).Title), NMResultsViewerReportTools.safeAscii(status)); %#ok<AGROW>
                reason = comps(ii).MissingReason;
                if ~isempty(reason), lines{end+1} = ['   Reason: ' NMResultsViewerReportTools.safeAscii(reason)]; end %#ok<AGROW>
                tables = comps(ii).Tables;
                if ~isempty(fieldnames(tables))
                    names = fieldnames(tables);
                    for jj = 1:numel(names)
                        data = tables.(names{jj});
                        if isempty(data), continue; end
                        cells = NMResultsViewerReportTools.dataToCell(data, maxRows);
                        lines{end+1} = ['   Table: ' names{jj}]; %#ok<AGROW>
                        for rr = 1:min(size(cells,1), maxRows+1)
                            rowVals = cell(1,size(cells,2));
                            for cc = 1:size(cells,2), rowVals{cc} = NMResultsViewerReportTools.safeAscii(NMResultsViewerReportTools.valuePreview(cells{rr,cc})); end
                            lines{end+1} = ['     ' strjoin(rowVals, ' | ')]; %#ok<AGROW>
                        end
                    end
                end
                lines{end+1} = ''; %#ok<AGROW>
            end
        end

        function wrapped = wrapTextLines(lines, width)
            % wrapTextLines  Wrap plain-text lines to a fixed report width.
            wrapped = cell(1,0);
            for ii = 1:numel(lines)
                s = lines{ii};
                if isempty(s), wrapped{end+1} = ''; continue; end %#ok<AGROW>
                while numel(s) > width
                    cut = find(isspace(s(1:width)), 1, 'last');
                    if isempty(cut) || cut < 20, cut = width; end
                    wrapped{end+1} = strtrim(s(1:cut)); %#ok<AGROW>
                    s = strtrim(s(cut+1:end));
                end
                wrapped{end+1} = s; %#ok<AGROW>
            end
        end

        function content = pdfPageContent(lines, pageNo, nPages)
            % pdfPageContent  Build one PDF text stream for report lines.
            yStart = 802;
            parts = {sprintf('BT /F1 10 Tf 50 %d Td 12 TL', yStart)};
            for ii = 1:numel(lines)
                parts{end+1} = sprintf('(%s) Tj T*', NMResultsViewerReportTools.pdfEscape(lines{ii})); %#ok<AGROW>
            end
            parts{end+1} = sprintf('ET BT /F1 8 Tf 50 28 Td (Page %d of %d) Tj ET', pageNo, nPages);
            content = strjoin(parts, sprintf('\n'));
        end

        function txt = pdfEscape(txt)
            % pdfEscape  Escape one ASCII text value for a PDF string literal.
            txt = NMResultsViewerReportTools.safeAscii(txt);
            txt = strrep(txt, '\', '\\');
            txt = strrep(txt, '(', '\(');
            txt = strrep(txt, ')', '\)');
        end

        function txt = safeAscii(txt)
            % safeAscii  Normalize text to printable ASCII for dependency-free PDF.
            txt = regexprep(txt, '[^\x09\x0A\x0D\x20-\x7E]', '?');
        end

        function name = validMatlabIdentifier(raw, fallback)
            % validMatlabIdentifier  Sanitize generated script variable names.
            name = raw;
            if isempty(name) || ~isvarname(name)
                name = fallback;
            end
        end

        function literal = matlabStringLiteral(txt)
            % matlabStringLiteral  Quote text as a MATLAB char literal.
            txt = strrep(txt, '''', '''''');
            literal = ['''' txt ''''];
        end

        function literal = scriptValueLiteral(value)
            % scriptValueLiteral  Render a compact editable MATLAB value for generated report code.
            % nm2-allow: scriptFromReportSpec code generation must encode caller options with genuinely heterogeneous MATLAB value types
            if ischar(value) || (isstring(value) && isscalar(value))
                % nm2-allow: scriptFromReportSpec code generation must encode caller options with genuinely heterogeneous MATLAB value types
                literal = NMResultsViewerReportTools.matlabStringLiteral(char(value));
            % nm2-allow: scriptFromReportSpec code generation must encode caller options with genuinely heterogeneous MATLAB value types
            elseif islogical(value)
                if isscalar(value)
                    if value, literal='true'; else, literal='false'; end
                else
                    literal=['logical(' mat2str(double(value)) ')'];
                end
            % nm2-allow: scriptFromReportSpec code generation must encode caller options with genuinely heterogeneous MATLAB value types
            elseif isnumeric(value) && ndims(value) <= 2
                if isempty(value), literal='[]'; else, literal=mat2str(double(value),17); end
            % nm2-allow: scriptFromReportSpec code generation must encode caller options with genuinely heterogeneous MATLAB value types
            elseif isstring(value) || (iscell(value) && all(cellfun(@(v)ischar(v)||(isstring(v)&&isscalar(v)),value(:))))
                % nm2-allow: scriptFromReportSpec code generation must encode caller options with genuinely heterogeneous MATLAB value types
                values=cellstr(string(value)); quoted=cell(size(values));
                for ii=1:numel(values), quoted{ii}=NMResultsViewerReportTools.matlabStringLiteral(values{ii}); end
                literal=['{' strjoin(quoted(:).',', ') '}'];
            else
                literal=['jsondecode(' NMResultsViewerReportTools.matlabStringLiteral(jsonencode(value)) ')'];
            end
        end

        function titleText = componentTitleFromId(id)
            % componentTitleFromId  Convert a component id to a readable title.
            txt = strrep(id, '_', ' ');
            txt = strrep(txt, '.', ' / ');
            titleText = txt;
        end

        function html = renderReportHtmlSummary(report, exportSpec)
            % renderReportHtmlSummary  Render a curated scientific HTML report.
            %
            % The summary/full renderer uses the report component contract rather than
            % hard-coded viewspace digests. Each selected component is dispatched to a
            % component-specific renderer. Generic table dumping is intentionally kept out
            % of summary mode so scientific figures and explicit status blocks replace raw
            % MATLAB placeholders such as [2x2 double] or {N cell}.
            titleText = NMResultsViewerReportTools.htmlEscape(report.Title);
            comps = NMResultsViewerReportTools.combineFeatureMetricPanelComponents(report.Components);
            css = NMResultsViewerReportTools.summaryReportCss();
            bodyClass = '';
            if exportSpec.PdfTarget
                bodyClass = ' class="pdfTarget"';
            end

            % Render first so the cover counts describe actual output sections rather
            % than merely requested component specifications. Every non-empty fragment
            % must already be wrapped by figureComponentHtml/statusComponentHtml.
            fragments = cell(1,numel(comps));
            renderStatuses = cell(1,numel(comps));
            keep = false(1,numel(comps));
            for ii=1:numel(comps)
                c = NMResultsViewerReportTools.initializeComponentRenderFields(comps(ii));
                NMResultsViewerReportTools.reportProgress('Report export', ...
                    sprintf('Rendering report section %d/%d: %s.',ii,numel(comps),c.Title),94,'render_section');
                [fragments{ii}, renderStatuses{ii}] = NMResultsViewerReportTools.renderComponentHtml(c, exportSpec);
                keep(ii) = ~isempty(fragments{ii});
                if keep(ii), comps(ii).RenderStatus = renderStatuses{ii}; end
            end
            comps = comps(keep);
            fragments = fragments(keep);
            renderStatuses = renderStatuses(keep);
            reportForChrome = report;
            reportForChrome.Components = comps;

            reportForChrome.Metadata.RenderStatusCounts = NMResultsViewerReportTools.renderStatusCounts(comps);

            parts = {NMResultsViewerReportTools.reportChromeHtml(reportForChrome, exportSpec), ...
                NMResultsViewerReportTools.reportWarningsHtml(comps)};
            reportContext=reportForChrome.Context;
            reportAnalysisIndices=reportContext.AnalysisIndices;
            reportAnalysisLabels=reportContext.AnalysisLabels;
            showAnalysisHeadings=numel(reportAnalysisIndices)>1;
            lastAnalysisIndex=NaN;
            lastViewspace = '';
            lastClassifier = '';
            lastOOCVGroup = '';
            lastFeatureContext = '';
            lastFeatureComponent = '';
            performanceClassifierIndices = [];
            optimizationClassifierIndices = [];
            featureClassifierIndices = [];
            for jj=1:numel(comps)
                viewspaceProbe = comps(jj).Viewspace;
                instProbe = comps(jj).Instance;
                ci = instProbe.ClassifierIndex;
                if ~isfinite(ci), continue; end
                if strcmpi(viewspaceProbe,'model_performance')
                    performanceClassifierIndices(end+1)=round(ci); %#ok<AGROW>
                elseif strcmpi(viewspaceProbe,'model_optimization')
                    optimizationClassifierIndices(end+1)=round(ci); %#ok<AGROW>
                elseif strcmpi(viewspaceProbe,'model_feature_inspection')
                    featureClassifierIndices(end+1)=round(ci); %#ok<AGROW>
                end
            end
            showPerformanceClassifierHeadings = numel(unique(performanceClassifierIndices)) > 1;
            showOptimizationClassifierHeadings = numel(unique(optimizationClassifierIndices)) > 1;
            showFeatureClassifierHeadings = numel(unique(featureClassifierIndices)) > 1;
            nRendered = 0;
            for ii=1:numel(comps)
                c = comps(ii);
                fragment = fragments{ii};
                renderStatus = renderStatuses{ii};
                viewspace = c.Viewspace;
                componentMeta=c.Metadata;
                componentAnalysisIndex=componentMeta.AnalysisIndex;
                if showAnalysisHeadings&&isfinite(componentAnalysisIndex)&&~isequal(componentAnalysisIndex,lastAnalysisIndex)
                    labelPos=find(reportAnalysisIndices==componentAnalysisIndex,1,'first');
                    % nm2-allow: reportContextFromSpec owns analysis coordinates while display labels are optional presentation metadata
                    if ~isempty(labelPos)&&labelPos<=numel(reportAnalysisLabels),analysisLabel=reportAnalysisLabels{labelPos};else,analysisLabel=sprintf('Analysis %d',round(componentAnalysisIndex));end
                    parts{end+1}=sprintf('<h2 class="reportAnalysisHeading">%s</h2>',NMResultsViewerReportTools.htmlEscape(analysisLabel)); %#ok<AGROW>
                    lastAnalysisIndex=componentAnalysisIndex;lastViewspace='';lastClassifier='';lastOOCVGroup='';lastFeatureContext='';lastFeatureComponent='';
                end
                if ~strcmpi(viewspace, lastViewspace)
                    parts{end+1} = sprintf('<h2>%s</h2>', NMResultsViewerReportTools.htmlEscape(NMResultsViewerReportTools.viewspaceTitle(viewspace))); %#ok<AGROW>
                    lastViewspace = viewspace;
                    lastClassifier = '';
                    lastOOCVGroup = '';
                    lastFeatureContext = '';
                    lastFeatureComponent = '';
                end
                inst = c.Instance;
                oocvGroupIndex = inst.OOCVSubgroupIndex;
                oocvGroupLabel = inst.OOCVSubgroupLabel;
                if strcmpi(viewspace,'model_performance') && isfinite(oocvGroupIndex) && ~isempty(oocvGroupLabel)
                    oocvGroupKey=sprintf('oocv:%d:%s',round(oocvGroupIndex),oocvGroupLabel);
                    if ~strcmp(oocvGroupKey,lastOOCVGroup)
                        parts{end+1}=sprintf('<h3 class="reportOOCVGroupHeading">%s</h3>',NMResultsViewerReportTools.htmlEscape(oocvGroupLabel)); %#ok<AGROW>
                        lastOOCVGroup=oocvGroupKey;lastClassifier='';
                    end
                end
                classifierIndex = inst.ClassifierIndex;
                classifierKey = '';
                if isfinite(classifierIndex), classifierKey = sprintf('classifier:%d',round(classifierIndex)); end
                showClassifierHeading = (strcmpi(viewspace,'model_performance') && showPerformanceClassifierHeadings) || ...
                    (strcmpi(viewspace,'model_optimization') && showOptimizationClassifierHeadings) || ...
                    (strcmpi(viewspace,'model_feature_inspection') && showFeatureClassifierHeadings);
                if showClassifierHeading && ~strcmp(classifierKey,lastClassifier)
                    classifierLabel = inst.ClassifierLabel;
                    if strcmpi(viewspace,'model_performance')
                        headingClass = 'performanceClassifierHeading';
                    elseif strcmpi(viewspace,'model_optimization')
                        headingClass = 'optimizationClassifierHeading';
                    else
                        headingClass = 'featureClassifierHeading';
                    end
                    parts{end+1} = sprintf('<h3 class="reportClassifierHeading %s">Binary decomposition: %s</h3>', ...
                        headingClass,NMResultsViewerReportTools.htmlEscape(classifierLabel)); %#ok<AGROW>
                    lastClassifier = classifierKey;
                    lastFeatureContext = '';
                    lastFeatureComponent = '';
                end
                if strcmpi(viewspace,'model_feature_inspection')
                    if inst.IsOverview
                        if ~strcmp(lastFeatureContext,'__overview__')
                            parts{end+1} = '<h3 class="featureContextHeading">Fusion overview</h3>'; %#ok<AGROW>
                            lastFeatureContext = '__overview__';
                            lastFeatureComponent = '';
                        end
                    else
                        contextId = inst.FeatureContextId;
                        componentId = inst.BackprojectionComponentId;
                        if ~strcmp(contextId,lastFeatureContext)
                            contextLabel = inst.FeatureContextLabel;
                            parts{end+1} = sprintf('<h3 class="featureContextHeading">Feature source: %s</h3>', NMResultsViewerReportTools.htmlEscape(contextLabel)); %#ok<AGROW>
                            lastFeatureContext = contextId;
                            lastFeatureComponent = '';
                        end
                        if ~isempty(componentId) && ~strcmp(componentId,lastFeatureComponent)
                            componentLabel = inst.BackprojectionComponentLabel;
                            parts{end+1} = sprintf('<h4 class="featureComponentHeading">Backprojected component: %s</h4>', NMResultsViewerReportTools.htmlEscape(componentLabel)); %#ok<AGROW>
                            lastFeatureComponent = componentId;
                        end
                    end
                end
                nRendered = nRendered + 1;
                parts{end+1} = strrep(fragment, '__RENDER_STATUS__', NMResultsViewerReportTools.htmlEscape(renderStatus)); %#ok<AGROW>
            end
            if nRendered == 0
                parts{end+1} = '<div class="note warn">No selected report component produced a static summary section.</div>'; %#ok<AGROW>
            end
            parts{end+1} = NMResultsViewerReportTools.reportAppendixHtml(reportForChrome, exportSpec); %#ok<AGROW>
            pdfPreflight = '';
            if exportSpec.PdfTarget
                pdfPreflight = NMResultsViewerReportTools.summaryReportPdfPreflightScript();
            end
            html = sprintf('<!doctype html><html><head><meta charset="utf-8"><title>%s</title><style>%s</style></head><body%s>%s%s</body></html>', ...
                titleText, css, bodyClass, strjoin(parts, sprintf('\n')), pdfPreflight);
        end


        function compsOut = combineFeatureMetricPanelComponents(compsIn)
            % combineFeatureMetricPanelComponents  Merge selected metric bars and distributions into one report panel.
            %
            % compsOut = NMResultsViewerReportTools.combineFeatureMetricPanelComponents(compsIn)
            % keeps the report specification component-based while rendering selected
            % feature-metric bar and distribution components as one compact metric panel.
            % The method preserves sidecar tables and only changes summary-rendering
            % metadata; it does not recompute scientific payloads or mutate NM.
            compsOut = compsIn;
            if isempty(compsIn), return; end
            consumed = false(1,numel(compsIn));
            for ii = 1:numel(compsIn)
                if consumed(ii), continue; end
                if ~strcmpi(strtrim(compsIn(ii).Viewspace), 'model_feature_inspection'), continue; end
                id = compsIn(ii).Id;
                [baseId, metricId] = NMResultsViewerReportTools.modelFeatureInspectionComponentIdentity(compsIn(ii));
                if ~strcmp(baseId,'model_feature_inspection.feature_metric_bar') || isempty(metricId), continue; end
                distIdx = 0;
                for jj = 1:numel(compsIn)
                    if jj == ii || consumed(jj), continue; end
                    if ~strcmpi(strtrim(compsIn(jj).Viewspace), 'model_feature_inspection'), continue; end
                    candidateInstance = compsIn(jj).Instance;
                    if strcmp(candidateInstance.ComponentType,'feature_metric_distribution') && ...
                            strcmp(candidateInstance.MetricId,metricId) && ...
                            strcmp(compsIn(jj).Status, 'ok') && ...
                            NMResultsViewerReportTools.sameFeatureReportInstance(compsIn(ii), compsIn(jj))
                        distIdx = jj;
                        break;
                    end
                end
                if distIdx > 0
                    c = compsOut(ii);
                    dist = compsIn(distIdx);
                    plotPayload = c.PlotPayload;
                    distPayload = dist.PlotPayload;
                    plotPayload.distributionRows = dist.SidecarTables.featureMetricRows;
                    plotPayload.distributionMetricSpec = distPayload.metricSpec;
                    c.PlotPayload = plotPayload;
                    dTables = dist.Tables;
                    % nm2-allow: Feature Inspection component writer conditionally materializes this optional distribution table
                    if isfield(dTables,'featureMetricDistribution')
                        c.Tables.featureMetricDistribution = dTables.featureMetricDistribution;
                    end
                    opts = c.Options;
                    opts.CombineDistribution = true;
                    c.Options = opts;
                    metricSpec = NMResultsViewerReportTools.safeField(plotPayload,'metricSpec',struct());
                    metricLabel = NMResultsViewerReportTools.safeField(metricSpec,'label',c.Title);
                    c.Title = NMResultsViewerReportTools.metricPanelTitle(metricLabel);
                    compsOut(ii) = c;
                    consumed(distIdx) = true;
                else
                    metricSpec = NMResultsViewerReportTools.safeField(NMResultsViewerReportTools.safeField(compsOut(ii),'PlotPayload',struct()),'metricSpec',struct());
                    metricLabel = NMResultsViewerReportTools.safeField(metricSpec,'label',NMResultsViewerReportTools.safeField(compsOut(ii),'Title','Feature metric'));
                    compsOut(ii).Title = NMResultsViewerReportTools.metricPanelTitle(metricLabel);
                end
            end
            compsOut = compsOut(~consumed);
        end

        function tf = sameFeatureReportInstance(a, b)
            % sameFeatureReportInstance  Match feature components by stable context/component identity.
            ia = a.Instance;
            ib = b.Instance;
            classifierA = ia.ClassifierIndex;
            classifierB = ib.ClassifierIndex;
            sameClassifier = (isnan(classifierA) && isnan(classifierB)) || classifierA == classifierB;
            ma=a.Metadata;mb=b.Metadata;
            analysisA=ma.AnalysisIndex;
            analysisB=mb.AnalysisIndex;
            sameAnalysis=(isnan(analysisA)&&isnan(analysisB))||analysisA==analysisB;
            tf = sameAnalysis && sameClassifier && ...
                strcmp(ia.FeatureContextId, ...
                    ib.FeatureContextId) && ...
                strcmp(ia.BackprojectionComponentId, ...
                    ib.BackprojectionComponentId);
        end

        function titleText = metricPanelTitle(metricLabel)
            % metricPanelTitle  Normalize metric-panel titles without repetitive plot-type wording.
            titleText = metricLabel;
            titleText = regexprep(titleText, '\s+bar plot$', '', 'ignorecase');
            titleText = regexprep(titleText, '\s+distribution$', '', 'ignorecase');
            if isempty(titleText), titleText = 'Feature metric'; end
            if strcmpi(titleText,'Mean feature weight')
                titleText = 'Mean feature weights';
            elseif strcmpi(titleText,'Feature-selection probability')
                titleText = 'Feature-selection probabilities';
            end
        end

        function html = reportChromeHtml(report, exportSpec)
            % reportChromeHtml  Render cover/context and executive summary cards.
            titleText = NMResultsViewerReportTools.htmlEscape(report.Title);
            desc = NMResultsViewerReportTools.htmlEscape(report.Description);
            mode = NMResultsViewerReportTools.htmlEscape(exportSpec.ReportMode);
            ctx = report.Context;
            ctxRows = NMResultsViewerReportTools.reportContextDisplayRows(ctx);
            parts = {sprintf('<h1>%s</h1>', titleText), ...
                sprintf('<div class="meta">Generated %s by NMResultsViewerReportTools.exportReport &middot; %s report</div>', datestr(now), mode)};
            if ~isempty(desc), parts{end+1} = sprintf('<div class="desc">%s</div>', desc); end %#ok<AGROW>
            parts{end+1} = '<div class="section ok reportContextTable"><h3>Report context</h3>'; %#ok<AGROW>
            parts{end+1} = NMResultsViewerReportTools.cellTableHtml(ctxRows, 20); %#ok<AGROW>
            parts{end+1} = '</div>'; %#ok<AGROW>
            parts{end+1} = NMResultsViewerReportTools.reportSummaryCardsHtml(report.Components); %#ok<AGROW>
            html = strjoin(parts, sprintf('\n'));
        end

        function rows = reportContextDisplayRows(ctx)
            % reportContextDisplayRows  Return user-facing report metadata rows for the visible report header.
            rows = {'Field','Value'};
            title = ctx.AnalysisTitle;
            if ~isempty(title), rows(end+1,:) = {'Analysis', title}; end %#ok<AGROW>
            source = ctx.Source;
            if ~isempty(source)
                if strcmp(source,'cv'), source = 'Cross-validation'; end
                rows(end+1,:) = {'Source', source}; %#ok<AGROW>
            end
            resultType = ctx.ResultType;
            if ~isempty(resultType)
                rt = resultType;
                rt = strrep(rt,'_',' ');
                if ~isempty(rt), rt = [upper(rt(1)) rt(2:end)]; end
                rows(end+1,:) = {'Analysis task', rt}; %#ok<AGROW>
            end
            classifierScope = ctx.ClassifierScope;
            classifierLabels = ctx.ClassifierLabels;
            if strcmp(classifierScope,'all_binary') && ~isempty(classifierLabels)
                rows(end+1,:) = {'Binary decomposition export', ['All binary decompositions: ' strjoin(classifierLabels, '; ')]}; %#ok<AGROW>
            elseif strcmp(classifierScope,'selected') && ~isempty(classifierLabels)
                rows(end+1,:) = {'Binary decomposition export', ['Selected binary decompositions: ' strjoin(classifierLabels, '; ')]}; %#ok<AGROW>
            elseif ~isempty(classifierLabels)
                rows(end+1,:) = {'Classifier / decomposition', classifierLabels{1}}; %#ok<AGROW>
            end
            included = ctx.IncludedSections;
            if ~isempty(included), rows(end+1,:) = {'Included sections', strjoin(included, ', ')}; end %#ok<AGROW>
        end

        function titleText = viewspaceTitle(viewspace)
            % viewspaceTitle  Convert component viewspace ids into report headings.
            txt = viewspace;
            if isempty(txt), titleText = 'Report components'; return; end
            txt = strrep(txt, '_', ' ');
            parts = strsplit(strtrim(txt));
            for kk=1:numel(parts)
                if ~isempty(parts{kk})
                    parts{kk} = [upper(parts{kk}(1)) parts{kk}(2:end)];
                end
            end
            titleText = strjoin(parts, ' ');
        end

        function [html, renderStatus] = renderComponentHtml(component, exportSpec)
            % Purpose: Dispatch one successfully built report component to its static HTML/PDF renderer.
            % Syntax: [html,renderStatus] = NMResultsViewerReportTools.renderComponentHtml(component,exportSpec)
            % Inputs: component is a built report component; exportSpec carries presentation/export limits.
            % Outputs: html is static report markup; renderStatus records ok/unavailable/sidecar-only status.
            % Authority and flow: Rendering dispatches by explicit Viewspace; stable component Id values select only known renderers within that declared viewspace.
            % Scientific/state contract: HTML rendering never recalculates scientific values or changes component Scientific State/Annotation semantics.
            % Invariants: Non-ok components are rendered as explicit status blocks; renderer dispatch cannot create a second scientific authority.
            % Materialization and performance: Presentation-only string/table rendering; no NM access, files/XML/atlas/annotation/mesh loads, voxel/vertex scans, or feature-scale allocations.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; it renders already-built report data. Safe for interactive report preview/build, not a retained scientific interaction path.
            % Failure semantics: Unavailable known components produce status HTML; unknown Viewspace/component ids raise explicitly rather than routing to a plausible renderer.
            % Side effects: None.
            % Consumers and dependencies: HTML/PDF report assembly and component-specific renderers.
            id = component.Id;
            if ~strcmpi(component.Status, 'ok')
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, component.MissingReason);
                return;
            end
            viewspace = component.Viewspace;
            switch viewspace
                case 'cross_analysis'
                    [html,renderStatus]=NMResultsViewerReportTools.renderCrossAnalysisComponentHtml(component,exportSpec);
                case 'model_feature_inspection'
                    [html,renderStatus]=NMResultsViewerReportTools.renderFeatureInspectionComponentHtml(component,exportSpec);
                case 'model_optimization'
                    [html,renderStatus]=NMResultsViewerReportTools.renderOptimizationComponentHtml(component,exportSpec);
                case 'model_performance'
                    switch id
                        case 'model_performance.summary'
                            [html, renderStatus] = NMResultsViewerReportTools.renderPerfSummaryHtml(component, exportSpec);
                        case 'model_performance.primary_plot'
                            [html, renderStatus] = NMResultsViewerReportTools.renderPerfPrimaryPlotHtml(component);
                        case 'model_performance.confusion_matrix'
                            [html, renderStatus] = NMResultsViewerReportTools.renderPerfConfusionHtml(component);
                        case 'model_performance.roc'
                            [html, renderStatus] = NMResultsViewerReportTools.renderPerfRocHtml(component);
                        case 'model_performance.probability_distribution'
                            [html, renderStatus] = NMResultsViewerReportTools.renderPerfDistributionHtml(component);
                        case 'model_performance.calibration'
                            [html, renderStatus] = NMResultsViewerReportTools.renderCalibrationHtml(component);
                        case 'model_performance.dca'
                            [html, renderStatus] = NMResultsViewerReportTools.renderDcaHtml(component);
                        case 'model_performance.model_permutation'
                            [html, renderStatus] = NMResultsViewerReportTools.renderModelPermutationHtml(component, exportSpec);
                        case 'model_performance.extra_label_permutation_gallery'
                            [html, renderStatus] = NMResultsViewerReportTools.renderExtraLabelPermutationGalleryHtml(component, exportSpec);
                        case 'model_performance.payload'
                            renderStatus = 'sidecar_only';
                            html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'Full model-performance payload is available in MAT/JSON sidecars; it is not dumped into the scientific report body.');
                        otherwise
                            error('NMResultsViewerReportTools:UnknownModelPerformanceComponentId', ...
                                'Unknown model-performance report component id "%s".',id);
                    end
                otherwise
                    error('NMResultsViewerReportTools:UnknownComponentViewspace', ...
                        'Report component %s declares unsupported Viewspace %s.',id,viewspace);
            end
        end

        function [html,renderStatus] = renderCrossAnalysisComponentHtml(component,exportSpec)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Render set-level Cross-analysis Performance Table, Statistical Comparison or Visual Comparison into static HTML/PDF content.
            % Syntax: [html,renderStatus] = NMResultsViewerReportTools.renderCrossAnalysisComponentHtml(component,exportSpec)
            % Inputs: Already-built Cross-analysis component and export row-limit options.
            % Outputs: Static HTML containing canonical numerical tables and the established statistical or descriptive plot family where applicable.
            % Authority and flow: Consumes only component.Tables and component.PlotPayload produced by buildCrossAnalysisComponentWithSession; no scientific materialization, performance-metric calculation or statistical inference occurs here.
            % Scientific/state contract: HTML/PDF and spreadsheet exports represent the same cross_analysis.* artefact. Statistical plots use backend delta/summary/FDR/CI payloads; visual plots use backend aggregate performance values. Neither renderer recomputes scientific metrics or inference.
            % Invariants: Exactly-two paired Wilcoxon receives no invented plot; Quade/reference plot types are selected exclusively from the backend plotPayload.type.
            % Materialization and performance: O(table cells + compact plot payload) string/SVG serialization; no NM/files/XML/atlas/annotation/mesh resources, voxel/vertex scans or feature-scale arrays.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays; report presentation only.
            % Failure semantics: Missing required table/plot payload returns explicit unavailable markup; no substitute representation is fabricated.
            % Side effects: None.
            % Consumers and dependencies: renderComponentHtml and HTML/PDF exporters; cellTableHtml and Cross-analysis SVG helpers below.
            id=component.Id;
            maxRows=exportSpec.MaxTableRows;
            switch id
                case 'cross_analysis.performance_table'
                    cells=component.Tables.performanceTable;
                    if isempty(cells),renderStatus='unavailable';html=NMResultsViewerReportTools.statusComponentHtml(component,renderStatus,'No cross-analysis performance table rows are available.');return;end
                    source=component.Payload.selectedSource;
                    indices=component.Payload.selectedAnalysisIndices;
                    note=sprintf('Selected analyses: %s | Source: %s',strjoin(arrayfun(@(v)sprintf('%d',v),indices,'UniformOutput',false),', '),source);
                    html=sprintf('<section class="component ok"><h2>%s</h2><div class="status">%s</div>%s</section>', ...
                        NMResultsViewerReportTools.htmlEscape(component.Title), ...
                        NMResultsViewerReportTools.htmlEscape(note),NMResultsViewerReportTools.cellTableHtml(cells,maxRows));
                    renderStatus='table_only';
                case 'cross_analysis.statistical_comparison'
                    summary=component.Tables.summary;
                    if isempty(summary),renderStatus='unavailable';html=NMResultsViewerReportTools.statusComponentHtml(component,renderStatus,'No cross-analysis statistical result is available.');return;end
                    payload=component.Payload;
                    criterion=payload.optimizationCriterion;
                    note=sprintf('Test: %s | Optimization criterion: %s | Analyses: %s', ...
                        payload.testType, criterion.label, ...
                        strjoin(arrayfun(@(v)sprintf('%d',v),payload.selectedAnalysisIndices,'UniformOutput',false),', '));
                    sections={NMResultsViewerReportTools.cellTableHtml(summary,maxRows)};
                    names={'testSummary','postHoc','plotSummary'};labels={'Test result','Pairwise / post-hoc probabilities','Plot summary'};
                    for ii=1:numel(names),cells=component.Tables.(names{ii});if ~isempty(cells),sections{end+1}=sprintf('<h3>%s</h3>%s',labels{ii},NMResultsViewerReportTools.cellTableHtml(cells,maxRows));end,end %#ok<AGROW>
                    plotHtml=NMResultsViewerReportTools.crossStatisticalPlotHtml(component.PlotPayload);
                    html=sprintf('<section class="component ok"><h2>%s</h2><div class="status">%s</div>%s%s</section>', ...
                        NMResultsViewerReportTools.htmlEscape(component.Title), ...
                        NMResultsViewerReportTools.htmlEscape(note),plotHtml,strjoin(sections,''));
                    if strcmp(component.PlotPayload.type,'none'),renderStatus='table_only';else,renderStatus='rendered';end
                case 'cross_analysis.synth_overview'
                    payload=component.Payload;
                    if strcmp(payload.mode,'fully_synthetic')
                        note=sprintf('Fully synthetic populations | Marginal by N | Criterion: %s | Experiment: %s', ...
                            payload.criterion.label,payload.experimentId);
                    else
                        note=sprintf('Observed N=%d | Optimization criterion: %s | Experiment: %s', ...
                            payload.observedN,payload.criterion.label,payload.experimentId);
                    end
                    html=sprintf('<section class="component ok"><h2>%s</h2><div class="status">%s</div>%s<h3>Completed analyses</h3>%s</section>', ...
                        NMResultsViewerReportTools.htmlEscape(component.Title), ...
                        NMResultsViewerReportTools.htmlEscape(note), ...
                        NMResultsViewerReportTools.crossVisualPlotHtml(component.PlotPayload), ...
                        NMResultsViewerReportTools.cellTableHtml(component.Tables.learningCurve,maxRows));
                    renderStatus='rendered';
                case 'cross_analysis.visual_comparison'
                    cells=component.Tables.selectedMetricValues;
                    if isempty(cells),renderStatus='unavailable';html=NMResultsViewerReportTools.statusComponentHtml(component,renderStatus,'No cross-analysis visual-comparison values are available.');return;end
                    payload=component.Payload;plotPayload=component.PlotPayload;
                    note=sprintf('Aggregate OOT source: %s | Analyses: %s | CV-equivalence restriction: none', ...
                        payload.source, strjoin(arrayfun(@(v)sprintf('%d',v),payload.selectedAnalysisIndices,'UniformOutput',false),', '));
                    plotHtml=NMResultsViewerReportTools.crossVisualPlotHtml(plotPayload);
                    html=sprintf('<section class="component ok"><h2>%s</h2><div class="status">%s</div>%s<h3>Performance values</h3>%s</section>', ...
                        NMResultsViewerReportTools.htmlEscape(component.Title),NMResultsViewerReportTools.htmlEscape(note),plotHtml,NMResultsViewerReportTools.cellTableHtml(cells,maxRows));
                    if isempty(plotPayload.values),renderStatus='table_only';else,renderStatus='rendered';end
                otherwise
                    error('NMResultsViewerReportTools:UnknownCrossAnalysisComponentId', ...
                        'Unknown Cross-analysis report component id "%s".',id);
            end
        end

        function html=crossVisualPlotHtml(plotPayload)
            % Interactive/retained use: Static report presentation of an already-materialized Visual Comparator payload.
            % Purpose: Render aggregate OOT Model Performance values as the grouped-bar or line-series cross-analysis comparison.
            % Syntax: html = NMResultsViewerReportTools.crossVisualPlotHtml(plotPayload)
            % Inputs: Canonical cross_analysis.visual_comparison PlotPayload with selected metric ids/labels, values, display labels and presentation flags.
            % Outputs: Inline SVG descriptive comparison plot.
            % Authority and flow: Consumes backend metric values unchanged; sorting and axis placement are presentation transforms only.
            % Scientific/state contract: No performance metric, CV statistic or inferential quantity is computed here.
            % Invariants: Bar mode uses one shared axis; line mode may place explicitly selected metrics on the right axis; established ascending sort uses the mean of selected displayed values.
            % Materialization and performance: O(A*M) report-only SVG geometry for compact aggregate values.
            % Resource declaration: Reads no files/resources and creates no feature-scale arrays.
            % Failure semantics: Missing/invalid values return an explicit report notice.
            % Side effects: None.
            % Consumers and dependencies: renderCrossAnalysisComponentHtml.
            if ~strcmp(plotPayload.type,'aggregate_performance')
                error('NMResultsViewerReportTools:InvalidCrossVisualPayload','Unexpected Cross-analysis visual plot type.');
            end
            values=plotPayload.values;labels=plotPayload.displayLabels;metricLabels=plotPayload.metricLabels;metricIds=plotPayload.metricIds;
            if isempty(values)
                html='<div class="status">Visual-comparison values are unavailable.</div>';
                return;
            end
            % nm2-allow: visualComparison producer fixes analysis and metric axes; mismatch indicates corrupted scientific payload
            if size(values,1)~=numel(labels)||size(values,2)~=numel(metricLabels)
                error('NMResultsViewerReportTools:InvalidCrossVisualAxes', ...
                    'Visual-comparison matrix axes do not match analysis and metric labels.');
            end
            order=1:size(values,1);if plotPayload.sortAnalyses,score=mean(values,2,'omitnan');[~,order]=sort(score,'ascend');end;values=values(order,:);labels=labels(order);
            mode=plotPayload.plotMode;
            separate=plotPayload.separateAxisMetricIds;rightMask=ismember(metricIds,separate)&strcmp(mode,'line');leftMask=~rightMask;
            isLearning=~isempty(plotPayload.bandLower);
            W=900;H=430;left=72;right=72;top=25;bottom=115;
            if isLearning,right=25;bottom=65;end
            plotW=W-left-right;plotH=H-top-bottom;n=size(values,1);m=size(values,2);colors={plotPayload.metricColors.color};
            leftVals=values(:,leftMask);leftFinite=leftVals(isfinite(leftVals));
            if isLearning,band=[plotPayload.bandLower(:);plotPayload.bandUpper(:)];leftFinite=[leftFinite(:);band(isfinite(band))];end
            if isempty(leftFinite),leftLim=[0 1];else
                if isLearning,leftLim=[min(leftFinite) max(leftFinite)];else,leftLim=[min([0;leftFinite(:)]) max([0;leftFinite(:)])];end
                if ~(leftLim(2)>leftLim(1)),leftLim=leftLim+[-0.5 0.5];
                elseif isLearning,pad=0.12*(leftLim(2)-leftLim(1));leftLim=leftLim+[-pad pad];end
            end
            rightVals=values(:,rightMask);rightFinite=rightVals(isfinite(rightVals));if isempty(rightFinite),rightLim=[0 1];else,rightLim=[min([0;rightFinite(:)]) max([0;rightFinite(:)])];if ~(rightLim(2)>rightLim(1)),rightLim=rightLim+[-0.5 0.5];end,end
            yL=@(v) top+(leftLim(2)-v)/(leftLim(2)-leftLim(1))*plotH;yR=@(v) top+(rightLim(2)-v)/(rightLim(2)-rightLim(1))*plotH;
            xPositions=plotPayload.xPositions(order);
            if isLearning,x=@(i) left+(0.025+0.95*xPositions(i))*plotW;else,x=@(i) left+xPositions(i)*plotW;end
            parts={sprintf('<svg viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg"><rect x="%g" y="%g" width="%g" height="%g" fill="#fff" stroke="#cbd5e1"/>',W,H,left,top,plotW,plotH)};
            if isLearning
                for kk=0:4,yy=top+kk*plotH/4;parts{end+1}=sprintf('<line x1="%g" y1="%.1f" x2="%g" y2="%.1f" stroke="#cbd5e1"/>',left,yy,left+plotW,yy);end
                lo=plotPayload.bandLower(order);hi=plotPayload.bandUpper(order);segment=[];
                for ii=1:n+1
                    valid=ii<=n&&isfinite(lo(min(ii,n)))&&isfinite(hi(min(ii,n)));
                    if valid,segment(end+1)=ii;continue;end %#ok<AGROW>
                    if numel(segment)>1
                        xTop=arrayfun(@(k)x(k),segment);yTop=yL(hi(segment));
                        xBottom=arrayfun(@(k)x(k),fliplr(segment));yBottom=yL(lo(fliplr(segment)));
                        coords=[xTop(:) yTop(:);xBottom(:) yBottom(:)];
                        xy=strtrim(sprintf('%.1f,%.1f ',coords'));
                        parts{end+1}=sprintf('<polygon points="%s" fill="%s" fill-opacity="0.20"/>',xy,colors{1});
                    end
                    segment=[];
                end
            end
            if strcmp(mode,'bar')
                slot=plotW/max(1,n);bw=slot*0.76/max(1,m);zero=yL(0);for ii=1:n,for jj=1:m,v=values(ii,jj);if ~isfinite(v),continue;end;cx=left+(ii-1)*slot+slot*0.12+(jj-0.5)*bw;yv=yL(v);parts{end+1}=sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>',cx-bw/2,min(zero,yv),max(1,bw*0.9),max(1,abs(zero-yv)),colors{mod(jj-1,numel(colors))+1});end,end
            else
                for jj=1:m
                    pts={};c=colors{mod(jj-1,numel(colors))+1};useRight=rightMask(jj);
                    for ii=1:n+1
                        if ii<=n && isfinite(values(ii,jj))
                            v=values(ii,jj);yp=yL(v);if useRight,yp=yR(v);end
                            pts{end+1}=sprintf('%.1f,%.1f',x(ii),yp); %#ok<AGROW>
                            parts{end+1}=sprintf('<circle cx="%.1f" cy="%.1f" r="3" fill="%s"/>',x(ii),yp,c); %#ok<AGROW>
                        elseif ~isempty(pts)
                            parts{end+1}=sprintf('<polyline points="%s" fill="none" stroke="%s" stroke-width="2"/>',strjoin(pts,' '),c); %#ok<AGROW>
                            pts={};
                        end
                    end
                end
            end
            for kk=0:4,frac=kk/4;v=leftLim(1)+frac*(leftLim(2)-leftLim(1));yy=yL(v);parts{end+1}=sprintf('<line x1="%g" y1="%.1f" x2="%g" y2="%.1f" stroke="#64748b"/><text x="%g" y="%.1f" text-anchor="end" font-size="9">%.3g</text>',left-4,yy,left,yy,left-7,yy+3,v);end
            if any(rightMask),for kk=0:4,frac=kk/4;v=rightLim(1)+frac*(rightLim(2)-rightLim(1));yy=yR(v);xx=left+plotW;parts{end+1}=sprintf('<line x1="%g" y1="%.1f" x2="%g" y2="%.1f" stroke="#64748b"/><text x="%g" y="%.1f" text-anchor="start" font-size="9">%.3g</text>',xx,yy,xx+4,yy,xx+7,yy+3,v);end,end
            for ii=1:n,parts{end+1}=sprintf('<text x="%.1f" y="%g" text-anchor="end" font-size="9" transform="rotate(-45 %.1f %g)">%s</text>',x(ii),top+plotH+18,x(ii),top+plotH+18,NMResultsViewerReportTools.htmlEscape(labels{ii}));end
            if ~isLearning
                legendX=left;for jj=1:m,c=colors{mod(jj-1,numel(colors))+1};tag='';if rightMask(jj),tag=' (right axis)';end;parts{end+1}=sprintf('<rect x="%.1f" y="%g" width="10" height="10" fill="%s"/><text x="%.1f" y="%g" font-size="9">%s%s</text>',legendX,H-22,c,legendX+14,H-13,NMResultsViewerReportTools.htmlEscape(metricLabels{jj}),NMResultsViewerReportTools.htmlEscape(tag));legendX=legendX+max(105,7*(numel(metricLabels{jj})+numel(tag))+24);end
            end
            parts{end+1}=sprintf('<text x="16" y="%g" transform="rotate(-90 16 %g)" text-anchor="middle" font-size="11">%s</text><text x="%g" y="%g" text-anchor="middle" font-size="11">%s</text></svg>', ...
                top+plotH/2,top+plotH/2,NMResultsViewerReportTools.htmlEscape(plotPayload.yLabel), ...
                left+plotW/2,H-(55-35*isLearning),NMResultsViewerReportTools.htmlEscape(plotPayload.xLabel));html=strjoin(parts,'');
        end

        function html=crossStatisticalPlotHtml(plotPayload)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Render the canonical statistical plot payload into static SVG blocks for report HTML/PDF.
            % Syntax: html = NMResultsViewerReportTools.crossStatisticalPlotHtml(plotPayload)
            % Inputs: Backend plotPayload from cross_analysis.statistical_comparison.
            % Outputs: No-plot notice, reference median+95%%CI bar SVG, or Quade four-view + FDR-matrix SVG group.
            % Authority and flow: Consumes backend values/summaries/deltas/FDR/CI only; it performs presentation binning/scaling but no scientific delta/p/FDR/CI calculation.
            % Scientific/state contract: Mirrors the Stage-2 statistical comparator semantics; exactly-two Wilcoxon remains plot-free.
            % Invariants: Plot family is selected by plotPayload.type and analysis ordering is preserved.
            % Materialization and performance: O(B*A + A^2) small SVG construction during explicit report rendering.
            % Resource declaration: Reads no files/resources and creates no feature-scale arrays; static SVG strings only.
            % Failure semantics: Missing/unknown payload produces an explicit report notice.
            % Side effects: None.
            % Consumers and dependencies: renderCrossAnalysisComponentHtml and helper SVG functions.
            typ=plotPayload.type;
            switch typ
                case 'none'
                    html=sprintf('<div class="status">%s</div>',NMResultsViewerReportTools.htmlEscape(plotPayload.message));
                case 'reference_bar'
                    html=NMResultsViewerReportTools.crossReferenceBarSvg(plotPayload);
                case 'quade'
                    criterion=plotPayload.criterionLabel;
                    html=[sprintf('<h3>Performance distributions</h3>%s',NMResultsViewerReportTools.crossViolinSvg(plotPayload.performance,criterion)) ...
                        sprintf('<h3>One-vs-all performance deltas</h3>%s',NMResultsViewerReportTools.crossViolinSvg(plotPayload.oneVsAll,['Difference in ' criterion])) ...
                        sprintf('<h3>One-vs-one performance deltas</h3>%s',NMResultsViewerReportTools.crossBoxSummarySvg(plotPayload.oneVsOne,['Difference in ' criterion])) ...
                        sprintf('<h3>Median (IQR)</h3>%s',NMResultsViewerReportTools.crossBoxSummarySvg(plotPayload.medianIqr,criterion)) ...
                        sprintf('<h3>FDR-adjusted pairwise significance</h3>%s',NMResultsViewerReportTools.crossFdrMatrixSvg(plotPayload.negLog10FdrMatrix,plotPayload.labels))];
                otherwise
                    error('NMResultsViewerReportTools:InvalidCrossStatisticalPlot','Unknown Cross-analysis statistical plot type %s.',typ);
            end
        end

        function svg=crossViolinSvg(series,yLabel)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Draw a static violin from the shared canonical backend KDE rows.
            % Syntax: svg = NMResultsViewerReportTools.crossViolinSvg(series,yLabel)
            % Inputs: Series structs with label/values/summary and axis label.
            % Outputs: Inline SVG tapered KDE violin plot with backend mean and median marks.
            % Authority and flow: KDE rows and summaries come from the same NMResultsViewerTools.violinDensity authority used by browser OOCV/Cross-analysis; this report adapter computes coordinates only.
            % Scientific/state contract: Does not calculate pairwise deltas or inferential quantities.
            % Invariants: Series order/values are unchanged.
            % Materialization and performance: O(total plotted values) report-only geometry.
            % Resource declaration: Reads no files/resources and creates no feature-scale arrays.
            % Failure semantics: Empty finite data returns a status notice.
            % Side effects: None.
            % Consumers and dependencies: crossStatisticalPlotHtml.
            if isempty(series),svg='<div class="status">No finite plot values.</div>';return;end
            allVals=[];for ii=1:numel(series),d=series(ii).density;if ~isempty(d),allVals=[allVals;[d.y]'];end,end %#ok<AGROW>
            allVals=allVals(isfinite(allVals));if isempty(allVals),svg='<div class="status">No finite plot values.</div>';return;end
            lo=min(allVals);hi=max(allVals);if ~(hi>lo),lo=lo-0.5;hi=hi+0.5;end
            W=760;H=300;left=62;top=18;plotW=678;plotH=220;n=numel(series);slot=plotW/max(1,n);parts={sprintf('<svg viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg"><line x1="%g" y1="%g" x2="%g" y2="%g" stroke="#334155"/><line x1="%g" y1="%g" x2="%g" y2="%g" stroke="#334155"/>',W,H,left,top,left,top+plotH,left,top+plotH,left+plotW,top+plotH)};
            for ii=1:n
                density=series(ii).density;cx=left+slot*(ii-0.5);if ~isempty(density),dy=double([density.y]);dw=double([density.width])*slot;yp=top+(hi-dy)/(hi-lo)*plotH;xy=[cx+dw(:) yp(:);flipud([cx-dw(:) yp(:)])];pts=strtrim(sprintf('%.1f,%.1f ',xy'));parts{end+1}=sprintf('<polygon points="%s" fill="#94a3b8" fill-opacity="0.35" stroke="#475569"/>',pts);end %#ok<AGROW>
                q=series(ii).summary;statValues=[q.mean q.median];statColors={'#111827','#dc2626'};for ss=1:2,value=statValues(ss);if ~isfinite(value)||isempty(density),continue;end;[~,nearest]=min(abs(double([density.y])-value));half=max(slot*0.06,min(slot*0.34,slot*double(density(nearest).width)));y=top+(hi-value)/(hi-lo)*plotH;parts{end+1}=sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="2.6"/>',cx-half,y,cx+half,y,statColors{ss});end %#ok<AGROW>
                parts{end+1}=sprintf('<text x="%.1f" y="270" text-anchor="middle" font-size="9">%s</text>',cx,NMResultsViewerReportTools.htmlEscape(series(ii).label)); %#ok<AGROW>
            end
            parts{end+1}=sprintf('<text x="14" y="150" transform="rotate(-90 14 150)" text-anchor="middle" font-size="11">%s</text></svg>',NMResultsViewerReportTools.htmlEscape(yLabel));svg=strjoin(parts,'');
        end

        function svg=crossBoxSummarySvg(series,xLabel)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Draw backend-owned min/Q1/median/Q3/max summaries as horizontal boxes; for median-IQR payloads min/max are the supplied backend summary extrema.
            % Syntax: svg = NMResultsViewerReportTools.crossBoxSummarySvg(series,xLabel)
            % Inputs: Series/pair structs with label and summary plus axis label.
            % Outputs: Inline SVG box summary plot.
            % Authority and flow: Summary values are consumed unchanged; coordinates only are computed.
            % Scientific/state contract: No quartiles/deltas are recomputed in report rendering.
            % Invariants: Series order is preserved.
            % Materialization and performance: O(series) report-only SVG work.
            % Resource declaration: Reads no files/resources and creates no feature-scale arrays.
            % Failure semantics: Empty/invalid summaries return a notice.
            % Side effects: None.
            % Consumers and dependencies: crossStatisticalPlotHtml.
            if isempty(series),svg='<div class="status">No summary values.</div>';return;end
            ext=[];for ii=1:numel(series),q=series(ii).summary;ext=[ext q.min q.q1 q.median q.q3 q.max];end %#ok<AGROW>
            ext=double(ext);ext=ext(isfinite(ext));if isempty(ext),svg='<div class="status">No finite summary values.</div>';return;end
            lo=min(ext);hi=max(ext);if ~(hi>lo),lo=lo-0.5;hi=hi+0.5;end
            W=760;left=230;right=25;plotW=W-left-right;rowH=25;H=max(120,55+rowH*numel(series));parts={sprintf('<svg viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg">',W,H)};
            for ii=1:numel(series),q=series(ii).summary;vals=[q.min q.q1 q.median q.q3 q.max];vals=double(vals);if any(~isfinite(vals)),continue;end;x=left+(vals-lo)/(hi-lo)*plotW;cy=20+(ii-0.5)*rowH;parts{end+1}=sprintf('<text x="%g" y="%g" text-anchor="end" font-size="9">%s</text><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#475569"/><rect x="%.1f" y="%.1f" width="%.1f" height="14" fill="#cbd5e1" stroke="#475569"/><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#0f172a" stroke-width="2"/>',left-8,cy+3,NMResultsViewerReportTools.htmlEscape(series(ii).label),x(1),cy,x(5),cy,x(2),cy-7,max(1,x(4)-x(2)),x(3),cy-8,x(3),cy+8);end %#ok<AGROW>
            parts{end+1}=sprintf('<text x="%g" y="%g" text-anchor="middle" font-size="11">%s</text></svg>',left+plotW/2,H-8,NMResultsViewerReportTools.htmlEscape(xLabel));svg=strjoin(parts,'');
        end

        function svg=crossReferenceBarSvg(plotPayload)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Draw the reference-Wilcoxon median-difference bars with nm_95confint offsets.
            % Syntax: svg = NMResultsViewerReportTools.crossReferenceBarSvg(plotPayload)
            % Inputs: Canonical reference_bar payload with bars/reference/criterion.
            % Outputs: Inline SVG bars and error bars.
            % Authority and flow: Median and CI offsets are backend-owned; renderer computes only coordinates.
            % Scientific/state contract: Preserves inherited median + nm_95confint visualization semantics.
            % Invariants: Reference analysis itself is not plotted as a comparison bar.
            % Materialization and performance: O(A) report-only SVG work.
            % Resource declaration: Reads no files/resources and creates no feature-scale arrays.
            % Failure semantics: Empty bars return a notice.
            % Side effects: None.
            % Consumers and dependencies: crossStatisticalPlotHtml.
            bars=plotPayload.bars;if isempty(bars),svg='<div class="status">No reference comparisons.</div>';return;end
            ext=0;for ii=1:numel(bars),m=bars(ii).median;lo=bars(ii).ciLowOffset;hi=bars(ii).ciHighOffset;ext=[ext m+lo m+hi];end %#ok<AGROW>
            ext=ext(isfinite(ext));ymin=min(ext);ymax=max(ext);if ~(ymax>ymin),ymin=ymin-0.5;ymax=ymax+0.5;end
            W=760;H=310;left=62;top=22;plotW=678;plotH=210;n=numel(bars);slot=plotW/n;y=@(v) top+(ymax-v)/(ymax-ymin)*plotH;zero=y(0);parts={sprintf('<svg viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg"><line x1="%g" y1="%.1f" x2="%g" y2="%.1f" stroke="#334155"/>',W,H,left,zero,left+plotW,zero)};
            for ii=1:n,m=double(bars(ii).median);lo=m+double(bars(ii).ciLowOffset);hi=m+double(bars(ii).ciHighOffset);cx=left+slot*(ii-0.5);ym=y(m);yl=y(lo);yh=y(hi);parts{end+1}=sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#94a3b8" stroke="#475569"/><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#0f172a" stroke-width="2"/><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#0f172a"/><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#0f172a"/><text x="%.1f" y="270" text-anchor="middle" font-size="9">%s</text>',cx-slot*0.28,min(zero,ym),slot*0.56,max(1,abs(zero-ym)),cx,yl,cx,yh,cx-6,yl,cx+6,yl,cx-6,yh,cx+6,yh,cx,NMResultsViewerReportTools.htmlEscape(bars(ii).label));end
            criterion=plotPayload.criterionLabel;ref=plotPayload.referenceLabel;parts{end+1}=sprintf('<text x="14" y="150" transform="rotate(-90 14 150)" text-anchor="middle" font-size="11">Difference in %s</text><text x="380" y="296" text-anchor="middle" font-size="10">Reference: %s</text></svg>',NMResultsViewerReportTools.htmlEscape(criterion),NMResultsViewerReportTools.htmlEscape(ref));svg=strjoin(parts,'');
        end

        function svg=crossFdrMatrixSvg(matrix,labels)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Draw the backend corrected Quade -log10(P_FDR) comparison matrix.
            % Syntax: svg = NMResultsViewerReportTools.crossFdrMatrixSvg(matrix,labels)
            % Inputs: Numeric matrix and analysis labels from canonical plot payload.
            % Outputs: Static matrix SVG with numeric cell values.
            % Authority and flow: Matrix values are consumed unchanged; no FDR or logarithm calculation occurs here.
            % Scientific/state contract: Represents the authoritative corrected post-hoc result only when it exists.
            % Invariants: Row/column ordering follows backend analysis order.
            % Materialization and performance: O(A^2) SVG serialization.
            % Resource declaration: Reads no files/resources and creates no feature-scale arrays.
            % Failure semantics: Empty matrix returns an explicit no-post-hoc notice.
            % Side effects: None.
            % Consumers and dependencies: crossStatisticalPlotHtml.
            if isempty(matrix),svg='<div class="status">No pairwise post-hoc matrix: the Quade omnibus test did not trigger post-hoc comparisons.</div>';return;end
            n=size(matrix,1);cellW=max(30,min(58,450/max(1,n)));W=170+n*cellW;H=75+n*cellW;finiteVals=matrix(isfinite(matrix));mx=1;if ~isempty(finiteVals),mx=max(1,max(finiteVals));end;parts={sprintf('<svg viewBox="0 0 %.0f %.0f" xmlns="http://www.w3.org/2000/svg"><text x="8" y="14" font-size="10">-log10(P_FDR)</text>',W,H)};
            for ii=1:n,for jj=1:size(matrix,2),v=matrix(ii,jj);op=0.03;if isfinite(v),op=max(0.08,min(1,v/mx));end;x=145+(jj-1)*cellW;y=22+(ii-1)*cellW;txt='';if isfinite(v),txt=sprintf('%.2f',v);end;parts{end+1}=sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#334155" fill-opacity="%.3f"/><text x="%.1f" y="%.1f" text-anchor="middle" font-size="8">%s</text>',x,y,cellW,cellW,op,x+cellW/2,y+cellW/2+3,txt);end;if ii<=numel(labels),parts{end+1}=sprintf('<text x="140" y="%.1f" text-anchor="end" font-size="8">%s</text>',22+(ii-0.5)*cellW+3,NMResultsViewerReportTools.htmlEscape(labels{ii}));end,end
            parts{end+1}='</svg>';svg=strjoin(parts,'');
        end

        function rows = modelPermutationRowsByRole(rawRows, extraLabel)
            % modelPermutationRowsByRole  Partition normalized model-permutation rows by scientific role.
            if isempty(rawRows)
                rows = rawRows;
                return;
            end
            keep = false(1,numel(rawRows));
            for ii=1:numel(rawRows)
                isExtra = strcmp(rawRows(ii).mode,'extra_label');
                keep(ii) = logical(extraLabel) == isExtra;
            end
            rows = rawRows(keep);
        end

        function [html, renderStatus] = renderModelPermutationHtml(component, exportSpec)
            % renderModelPermutationHtml  Render the primary model histogram and complete permutation-results table.
            mp = component.PlotPayload.modelPermutation;
            allRows = mp.rows;
            primaryRows = NMResultsViewerReportTools.modelPermutationRowsByRole(allRows, false);
            if isempty(primaryRows)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'No primary model-permutation row is available.');
                return;
            end
            state = component.Options.ModelPermutationState;
            display = state.display;
            wanted = state.main.comparisonId;
            if isempty(wanted), wanted = mp.selectedPermutationId; end
            idx = 1;
            for ii=1:numel(primaryRows)
                if strcmp(primaryRows(ii).permutationId,wanted)
                    idx = ii; break;
                end
            end
            row = primaryRows(idx);
            histogramVisible = state.main.components.histogram.visible;
            tableVisible = state.main.components.resultsTable.visible;
            body = '';
            if histogramVisible
                svg = NMResultsViewerReportTools.modelPermutationHistogramSvg(row, display.histogramBins, display, false);
                body = [body sprintf('<div class="viz modelPermutationViz">%s</div>',svg)]; %#ok<AGROW>
            end
            if tableVisible
                summary = NMResultsViewerReportTools.modelPermutationSummaryRows(allRows);
                tableHtml = NMResultsViewerReportTools.structRowsHtml(summary, ...
                    {'comparison','comparisonType','observedValue','pValueShort','exceedanceDisplay','nPermutations'}, ...
                    {'Comparison','Type','Observed','P value','Exceedances','Permutations'}, ...
                    max(numel(summary),exportSpec.MaxTableRows));
                body = [body '<h4>Permutation results</h4>' tableHtml]; %#ok<AGROW>
            end
            renderStatus = 'rendered';
            html = NMResultsViewerReportTools.figureComponentHtml(component, body, renderStatus);
        end

        function [html, renderStatus] = renderExtraLabelPermutationGalleryHtml(component, exportSpec)
            % renderExtraLabelPermutationGalleryHtml  Render all extra-label null distributions in a deterministic gallery.
            mp = component.PlotPayload.modelPermutation;
            extraRows = NMResultsViewerReportTools.modelPermutationRowsByRole(mp.rows,true);
            if isempty(extraRows)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component,renderStatus,'No alternative-label permutation rows are available.');
                return;
            end
            state = component.Options.ModelPermutationState;
            display = state.display;
            gallery = state.extraLabelGallery;
            focused = state.focusedDetail;
            if ~isempty(gallery.comparisonIds)
                keep = false(1,numel(extraRows));
                for rr=1:numel(extraRows)
                    keep(rr) = any(strcmp(gallery.comparisonIds,extraRows(rr).permutationId));
                end
                if any(keep), extraRows = extraRows(keep); end
            end
            n = numel(extraRows);
            columns = gallery.columns;
            if ~isfinite(columns) || columns < 1
                if n < 5, columns = min(2,n); else, columns = 3; end
            end
            columns = max(1,min(3,round(columns)));
            histogramsVisible = gallery.components.histograms.visible;
            tiles = cell(1,0);
            if histogramsVisible
                tiles = cell(1,n);
                for ii=1:n
                    title = extraRows(ii).extraLabel;
                    if isempty(title), title = extraRows(ii).label; end
                    title = NMResultsViewerReportTools.htmlEscape(title);
                    svg = NMResultsViewerReportTools.modelPermutationHistogramSvg(extraRows(ii),display.histogramBins,display,true);
                    tiles{ii} = sprintf('<div style="break-inside:avoid;border:1px solid #dbe5f2;border-radius:10px;padding:8px;background:#fff"><h4 style="margin:0 0 6px">%s</h4>%s</div>',title,svg);
                end
            end
            focusedHtml = '';
            if focused.visible
                wanted = focused.comparisonId;
                for ii=1:n
                    if strcmp(extraRows(ii).permutationId,wanted)
                        focusedHtml = sprintf('<h4>Focused alternative-label comparison</h4><div class="viz modelPermutationViz">%s</div>',NMResultsViewerReportTools.modelPermutationHistogramSvg(extraRows(ii),display.histogramBins,display,false));
                        break;
                    end
                end
            end
            galleryHtml = '';
            if histogramsVisible, galleryHtml = sprintf('<div style="display:grid;grid-template-columns:repeat(%d,minmax(0,1fr));gap:12px;align-items:start">%s</div>',columns,strjoin(tiles,'')); end
            renderStatus = 'rendered';
            html = NMResultsViewerReportTools.figureComponentHtml(component, [focusedHtml galleryHtml], renderStatus);
        end

        function rows = modelPermutationSummaryRows(rawRows)
            % modelPermutationSummaryRows  Convert normalized comparisons into complete inferential summary rows.
            tmpl = struct('comparison','','comparisonType','','mode','','observedValue',NaN,'pValue',NaN,'pValueShort','', ...
                'pValueDisplay','','nPermutations',NaN,'exceedanceCount',NaN,'exceedanceDisplay','', ...
                'minimumPValue',NaN,'sourceFields','');
            rows = tmpl([]);
            if isempty(rawRows), return; end
            rows = repmat(tmpl,1,numel(rawRows));
            for ii=1:numel(rawRows)
                rows(ii).comparison = rawRows(ii).label;
                rows(ii).mode = rawRows(ii).mode;
                switch rows(ii).mode
                    case 'extra_label', rows(ii).comparisonType = 'Extra-label';
                    case 'multi_group', rows(ii).comparisonType = 'Multi-group';
                    case 'class_vs_rest', rows(ii).comparisonType = 'Class-vs-rest';
                    otherwise, rows(ii).comparisonType = 'Primary';
                end
                rows(ii).observedValue = rawRows(ii).observedValue;
                rows(ii).pValue = rawRows(ii).pValue;
                rows(ii).pValueDisplay = rawRows(ii).pValueDisplay;
                rows(ii).pValueShort = NMResultsViewerReportTools.modelPermutationPValueShort(rawRows(ii));
                rows(ii).nPermutations = rawRows(ii).nPermutations;
                rows(ii).exceedanceCount = rawRows(ii).exceedanceCount;
                if isfinite(double(rows(ii).exceedanceCount)) && isfinite(double(rows(ii).nPermutations))
                    rows(ii).exceedanceDisplay = sprintf('%d / %d',round(double(rows(ii).exceedanceCount)),round(double(rows(ii).nPermutations)));
                end
                rows(ii).minimumPValue = rawRows(ii).minimumPValue;
                rows(ii).sourceFields = strjoin(rawRows(ii).sourceFields,', ');
            end
        end

        function txt = modelPermutationPValueShort(row)
            % modelPermutationPValueShort  Format a compact corrected permutation P value.
            p = double(row.pValue);
            if isfinite(p), txt = sprintf('P = %.4g',p); return; end
            full = row.pValueDisplay;
            tok = regexp(full,'P\s*=\s*([^\s(]+)','tokens','once');
            if isempty(tok), txt = full; else, txt = ['P = ' tok{1}]; end
        end

        function svg = modelPermutationHistogramSvg(row, nBins, state, compact)
            % modelPermutationHistogramSvg  Static SVG with density and labelled observed-performance line.
            display = state;
            showDensity = display.showDensity; showObserved = display.showObserved;
            vals = double(row.nullValues); vals = vals(:); vals = vals(isfinite(vals));
            if isempty(vals), svg = '<div class="small">No finite null values available.</div>'; return; end
            obs = double(row.observedValue);
            lo = min(vals); hi = max(vals); if isfinite(obs), lo=min(lo,obs); hi=max(hi,obs); end
            if abs(hi-lo)<eps, lo=lo-0.5; hi=hi+0.5; end
            pad=0.08*(hi-lo); lo=lo-pad; hi=hi+pad;
            counts=histcounts(vals,linspace(lo,hi,nBins+1)); prob=counts./max(1,numel(vals)); maxP=max([0.05 prob(:)']);
            if compact, w=500; h=310; ml=58; mr=22; mt=24; mb=56; else, w=820; h=470; ml=78; mr=26; mt=26; mb=66; end
            pw=w-ml-mr; ph=h-mt-mb;
            xpix=@(x) ml+(double(x)-lo)./max(eps,hi-lo).*pw; ypix=@(y) mt+ph-double(y)./max(eps,maxP*1.18).*ph;
            edges=linspace(lo,hi,nBins+1); bars=cell(1,nBins); face=row.histogramFaceColor;
            for ii=1:nBins
                x0=xpix(edges(ii)); x1=xpix(edges(ii+1)); y=ypix(prob(ii)); y0=ypix(0);
                bars{ii}=sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="0.72"/>',x0+1,min(y,y0),max(1,x1-x0-2),max(1,abs(y0-y)),face);
            end
            densityLine='';
            if showDensity
                dens=NMResultsViewerReportTools.kernelDensity(vals,lo,hi,compact*100+(~compact)*180); maxD=max([eps dens(:,2)']); pts=cell(1,size(dens,1));
                for ii=1:size(dens,1), pts{ii}=sprintf('%.1f,%.1f',xpix(dens(ii,1)),ypix(dens(ii,2)/maxD*maxP)); end
                densityLine=sprintf('<polyline points="%s" fill="none" stroke="%s" stroke-width="2.3"/>',strjoin(pts,' '),row.densityColor);
            end
            obsMarkup='';
            if showObserved && isfinite(obs)
                xp=xpix(obs); lineColor=row.observedColor;
                perf=sprintf('%s = %.4g',row.criterionShortLabel,obs);
                ptxt=NMResultsViewerReportTools.modelPermutationPValueShort(row);
                boxW=min(compact*185+(~compact)*255,max(95,max(numel(perf),numel(ptxt))*(compact*5.5+(~compact)*6.3)+16)); boxH=compact*38+(~compact)*44;
                if xp < ml+pw/2, bx=min(ml+pw-boxW,xp+7); else, bx=max(ml,xp-boxW-7); end
                by=mt+7;
                obsMarkup=sprintf(['<line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2.2" stroke-dasharray="6 4"/>' ...
                    '<g><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="5" fill="#fff" fill-opacity="0.94" stroke="#fecaca"/>' ...
                    '<text x="%.1f" y="%.1f" font-size="11" font-weight="700" fill="#991b1b">%s</text><text x="%.1f" y="%.1f" font-size="11" font-weight="700" fill="#991b1b">%s</text></g>'], ...
                    xp,xp,mt,mt+ph,lineColor,bx,by,boxW,boxH,bx+8,by+(compact*15+(~compact)*17),NMResultsViewerReportTools.htmlEscape(perf),bx+8,by+(compact*30+(~compact)*34),NMResultsViewerReportTools.htmlEscape(ptxt));
            end
            xLabel=NMResultsViewerReportTools.htmlEscape(row.criterionAxisLabel);
            title=NMResultsViewerReportTools.htmlEscape(row.label);
            svg=sprintf(['<svg viewBox="0 0 %d %d" role="img" aria-label="%s"><rect x="%d" y="%d" width="%d" height="%d" fill="#fff" stroke="#dbe5f2"/>' ...
                '<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#0f172a"/><line x1="%d" x2="%d" y1="%d" y2="%d" stroke="#0f172a"/>%s%s%s' ...
                '<text x="%d" y="18" font-size="13" font-weight="700">%s</text><text x="%d" y="%d" text-anchor="middle" font-size="12">%s</text>' ...
                '<text transform="rotate(-90 18 %d)" x="18" y="%d" text-anchor="middle" font-size="12">Probability</text></svg>'], ...
                w,h,title,ml,mt,pw,ph,ml,ml,mt,mt+ph,ml,ml+pw,mt+ph,mt+ph,strjoin(bars,''),densityLine,obsMarkup,ml,title,ml+pw/2,h-14,xLabel,mt+ph/2,mt+ph/2);
        end

        function dens = kernelDensity(vals, lo, hi, n)
            % kernelDensity  Small Gaussian-kernel density helper for static reports.
            vals = vals(:); vals = vals(isfinite(vals));
            if isempty(vals), dens = zeros(0,2); return; end
            sd = std(vals,0,'omitnan'); if ~isfinite(sd) || sd <= 0, sd = max(eps,(hi-lo)/6); end
            bw = max(eps, 1.06 * sd * numel(vals)^(-1/5));
            xs = linspace(lo, hi, n)';
            ys = zeros(size(xs));
            for ii = 1:numel(xs)
                z = (xs(ii) - vals) ./ bw;
                ys(ii) = mean(exp(-0.5*z.^2) ./ (bw * sqrt(2*pi)), 'omitnan');
            end
            dens = [xs ys];
        end

        function [html, renderStatus] = renderPerfSummaryHtml(component, exportSpec)
            % renderPerfSummaryHtml  Render model-performance metric cards and compact rows.
            rows = component.Tables.summaryRows;
            if isempty(rows)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'No model-performance summary rows are available.');
                return;
            end
            maxRows = exportSpec.MaxSummaryRows;
            body = [NMResultsViewerReportTools.renderPerfSummaryCards(rows) ...
                NMResultsViewerReportTools.structRowsHtml(rows, {'metric','value','source'}, {'Metric','Value','Source'}, maxRows)];
            renderStatus = 'rendered';
            html = NMResultsViewerReportTools.figureComponentHtml(component, body, renderStatus);
        end

        function html = renderPerfSummaryCards(rows)
            % renderPerfSummaryCards  Render selected classification/regression metrics as cards.
            wanted = {'Accuracy','Sensitivity','Specificity','BAC','AUC','MCC','TP / TN','FP / FN','R²','NRMSD','MAE','RMSE'};
            cards = cell(1,0);
            for ww=1:numel(wanted)
                hit = 0;
                for rr=1:numel(rows)
                    metric = rows(rr).metric;
                    if contains(lower(metric), lower(wanted{ww}))
                        hit = rr;
                        break;
                    end
                end
                if hit > 0
                    cards{end+1} = sprintf('<div class="card"><div class="label">%s</div><div class="value smallValue">%s</div></div>', ...
                        NMResultsViewerReportTools.htmlEscape(regexprep(rows(hit).metric, ':$', '')), ...
                        NMResultsViewerReportTools.htmlEscape(rows(hit).value)); %#ok<AGROW>
                end
            end
            if isempty(cards)
                html = '<div class="note">No card-compatible summary metrics were found; see the summary table.</div>';
            else
                html = ['<div class="summaryGrid metricGrid">' strjoin(cards,'') '</div>'];
            end
        end

        function [html, renderStatus] = renderPerfPrimaryPlotHtml(component)
            % renderPerfPrimaryPlotHtml  Render binary, regression, or multiclass primary plots.
            pp = component.PlotPayload;
            fig = '';
            fig = NMResultsViewerReportFigureTools.classPlotSvg(pp.classPlot);
            if isempty(fig)
                fig = NMResultsViewerReportFigureTools.regressionScatterSvg(pp.regressionPlot);
            end
            if isempty(fig)
                fig = NMResultsViewerReportFigureTools.multiClassPlotSvg(pp.multiClassPlot);
            end
            if isempty(fig)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'Primary model-performance plot payload is absent or not renderable.');
            else
                renderStatus = 'rendered';
                html = NMResultsViewerReportTools.figureComponentHtml(component, fig, renderStatus);
            end
        end

        function [html, renderStatus] = renderPerfConfusionHtml(component)
            % renderPerfConfusionHtml  Render binary or multiclass confusion matrix SVG.
            conf = component.Payload.confusion;
            fig = NMResultsViewerReportFigureTools.confusionSvg(conf);
            if isempty(fig)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'Confusion-matrix payload is absent or not renderable.');
            else
                renderStatus = 'rendered';
                html = NMResultsViewerReportTools.figureComponentHtml(component, fig, renderStatus);
            end
        end

        function [html, renderStatus] = renderPerfRocHtml(component)
            % renderPerfRocHtml  Render ROC curve SVG or an explicit status block.
            roc = component.PlotPayload.roc;
            fig = NMResultsViewerReportFigureTools.rocSvg(roc);
            if isempty(fig)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, roc.message);
            else
                renderStatus = 'rendered';
                html = NMResultsViewerReportTools.figureComponentHtml(component, fig, renderStatus);
            end
        end

        function [html, renderStatus] = renderPerfDistributionHtml(component)
            % renderPerfDistributionHtml  Render probability/score distribution SVG.
            payload = component.Payload;
            plots = component.PlotPayload;
            fig = NMResultsViewerReportFigureTools.scoreDistributionSvg(payload.scoreRows, payload.scoreColumns, plots.pies);
            if isempty(fig)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'Probability/score-distribution payload is absent or not renderable.');
            else
                renderStatus = 'rendered';
                html = NMResultsViewerReportTools.figureComponentHtml(component, fig, renderStatus);
            end
        end

        function [html, renderStatus] = renderCalibrationHtml(component)
            % renderCalibrationHtml  Render calibration figure or explicit unavailable reason.
            cal = component.Payload.calibration;
            fig = NMResultsViewerReportFigureTools.calibrationSvg(cal);
            if isempty(fig)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, component.MissingReason);
            else
                renderStatus = 'rendered';
                html = NMResultsViewerReportTools.figureComponentHtml(component, fig, renderStatus);
            end
        end

        function [html, renderStatus] = renderDcaHtml(component)
            % renderDcaHtml  Render DCA figure or explicit unavailable reason.
            dca = component.Payload.dca;
            fig = NMResultsViewerReportFigureTools.dcaSvg(dca);
            if isempty(fig)
                renderStatus = 'unavailable';
                html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, component.MissingReason);
            else
                renderStatus = 'rendered';
                html = NMResultsViewerReportTools.figureComponentHtml(component, fig, renderStatus);
            end
        end

        function [html, renderStatus] = renderOptimizationComponentHtml(component, exportSpec)
            % renderOptimizationComponentHtml  Render current optimization summaries per component.
            id = component.Id;
            maxRows = exportSpec.MaxSummaryRows;
            switch id
                case 'model_optimization.selected_metric'
                    rows = component.Tables.metricValues;
                    if isempty(rows)
                        renderStatus = 'unavailable';
                        html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'No optimization metric values are available.');
                    else
                        selectedPoints = component.PlotPayload.selectedPoints;
                        body = [NMResultsViewerReportFigureTools.optimizationCurveSvg(rows, component.Title, selectedPoints) ...
                            NMResultsViewerReportTools.structRowsHtml(selectedPoints, {'seriesLabel','modelIndex','modelLabel','value','parameterValues'}, {'Series','Best model index','Model','Value','Parameters'}, maxRows)];
                        renderStatus = 'rendered';
                        html = NMResultsViewerReportTools.figureComponentHtml(component, body, renderStatus);
                    end
                case 'model_optimization.sequence_diagnostics'
                    rows=component.Tables.sequenceDiagnostics;
                    if isempty(rows)
                        renderStatus='unavailable';
                        html=NMResultsViewerReportTools.statusComponentHtml(component,renderStatus,'No applicable stage diagnostic values for this evaluation.');
                    else
                        if strcmp(component.Options.Representation,'tables'),plotHtml='';
                        else,plotHtml=NMResultsViewerReportFigureTools.sequenceDiagnosticsSvg(rows);end
                        body=[plotHtml ...
                            NMResultsViewerReportTools.structRowsHtml(rows, ...
                            {'metricLabel','stage','sourceName','mean','sd','unit','nModels','nPartitions'}, ...
                            {'Metric','Stage','Examination source','Mean','SD','Unit','Applied models','CV2 partitions'},maxRows)];
                        renderStatus='rendered';
                        html=NMResultsViewerReportTools.figureComponentHtml(component,body,renderStatus);
                    end
                case 'model_optimization.metric_dashboard'
                    rows = component.Tables.metricValues;
                    if isempty(rows)
                        renderStatus = 'unavailable';
                        html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'No optimization metric values are available.');
                    else
                        body = NMResultsViewerReportTools.metricDashboardPanelsHtml(rows, maxRows);
                        renderStatus = 'rendered';
                        html = NMResultsViewerReportTools.figureComponentHtml(component, body, renderStatus);
                    end
                case 'model_optimization.cv_partitions'
                    rows = component.Tables.cvPartitions;
                    if isempty(rows)
                        renderStatus = 'unavailable';
                        html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'No CV partition matrices are available.');
                    else
                        body = [NMResultsViewerReportFigureTools.partitionHeatmapsSvg(rows) ...
                            NMResultsViewerReportTools.structRowsHtml(NMResultsViewerReportTools.partitionSummaryRows(rows), {'partitionKind','title','n','nMissing','min','max','mean','maskSource'}, {'Kind','Title','N finite','N non-finite','Min','Max','Mean','Availability source'}, maxRows)];
                        renderStatus = 'rendered';
                        html = NMResultsViewerReportTools.figureComponentHtml(component, body, renderStatus);
                    end
                case 'model_optimization.metric_registry'
                    rows = component.Tables.metricRegistry;
                    finiteRows = NMResultsViewerReportTools.metricRegistryFiniteRows(rows);
                    missingRows = NMResultsViewerReportTools.metricRegistryUnavailableRows(rows);
                    body = NMResultsViewerReportTools.structRowsHtml(finiteRows, {'metricLabel','seriesLabel','available','nFinite','min','max','mean','median','sd'}, {'Metric','Series','Available','N finite','Min','Max','Mean','Median','SD'}, maxRows);
                    if ~isempty(missingRows)
                        suffix = 'y';
                        if numel(missingRows) ~= 1, suffix = 'ies'; end
                        body = [body sprintf('<div class="small">%d metric registry entr%s with no finite values were omitted from the scientific summary and should be inspected in the sidecar/technical payload.</div>', ...
                            numel(missingRows), suffix)];
                    end
                    renderStatus = 'table_only';
                    html = NMResultsViewerReportTools.figureComponentHtml(component, body, renderStatus);
                case 'model_optimization.parameter_surface'
                    rows = component.Tables.parameterSurface;
                    if isempty(rows)
                        renderStatus = 'unavailable';
                        html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'No 2D parameter-surface rows are available.');
                    else
                        body = [NMResultsViewerReportFigureTools.parameterSurfaceSvg(rows) ...
                            NMResultsViewerReportTools.structRowsHtml(NMResultsViewerReportTools.bestSurfaceRows(rows, maxRows), {'seriesLabel','xParameter','xValue','yParameter','yValue','aggregateValue','nContributingModels','bestModelIndex'}, {'Series','X parameter','X value','Y parameter','Y value','Aggregate','N models','Best model'}, maxRows)];
                        renderStatus = 'rendered';
                        html = NMResultsViewerReportTools.figureComponentHtml(component, body, renderStatus);
                    end
                case {'model_optimization.scatter_comparison','model_optimization.pareto_summary'}
                    scatterRows = component.Tables.scatterPoints;
                    associationRows = component.Tables.associations;
                    paretoRows = NMResultsViewerReportTools.componentTable(component,'paretoSummary');
                    if NMResultsViewerReportTools.allAssociationsLowDynamicRange(associationRows)
                        renderStatus = 'skipped_noninformative';
                        html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, 'Scatter/Pareto component not rendered because one metric has insufficient dynamic range.');
                    else
                        fig = NMResultsViewerReportFigureTools.scatterParetoSvg(scatterRows, associationRows, paretoRows, component.Title);
                        if isempty(fig)
                            renderStatus = 'sidecar_only';
                            html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, sprintf('Scatter/Pareto payload is available (%d scatter rows), but no informative static figure could be built. Tables are kept out of the scientific report body.', numel(scatterRows)));
                        else
                            renderStatus = 'rendered';
                            html = NMResultsViewerReportTools.figureComponentHtml(component, fig, renderStatus);
                        end
                    end
                case 'model_optimization.parameter_grid'
                    rows = component.Tables.parameterGrid;
                    renderStatus = 'sidecar_only';
                    html = NMResultsViewerReportTools.statusComponentHtml(component, renderStatus, sprintf('Parameter grid contains %d rows. Summary/full report modes keep the full grid in CSV/XLSX/MAT/JSON sidecars rather than dumping it into the body.', numel(rows)));
                otherwise
                    error('NMResultsViewerReportTools:UnknownModelOptimizationComponentId', ...
                        'Unknown model-optimization report component id "%s".',id);
            end
        end

        function html = figureComponentHtml(component, body, renderStatus)
            % figureComponentHtml  Wrap rendered component content in a stable section.
            titleText = NMResultsViewerReportTools.htmlEscape(component.Title);
            idText = NMResultsViewerReportTools.htmlEscape(component.Id);
            instance = component.Instance;
            instanceText = NMResultsViewerReportTools.htmlEscape(instance.Id);
            compactAttr = '';
            if any(strcmp(idText, {'model_performance.confusion_matrix','model_performance.roc', ...
                    'model_performance.calibration','model_performance.dca','model_performance.model_permutation'}))
                compactAttr = ' data-pdf-compact="true"';
            end
            html = sprintf('<section class="section ok %s" data-component-id="%s" data-instance-id="%s"%s><div class="status">%s</div><h3>%s</h3>%s</section>', ...
                NMResultsViewerReportTools.htmlEscape(renderStatus), idText, instanceText, compactAttr, NMResultsViewerReportTools.htmlEscape(renderStatus), titleText, body);
        end

        function html = statusComponentHtml(component, renderStatus, message)
            % statusComponentHtml  Render explicit non-empty component status sections.
            titleText = NMResultsViewerReportTools.htmlEscape(component.Title);
            idText = NMResultsViewerReportTools.htmlEscape(component.Id);
            instance = component.Instance;
            instanceText = NMResultsViewerReportTools.htmlEscape(instance.Id);
            cls = 'unavailable';
            if any(strcmpi(renderStatus, {'sidecar_only','skipped_noninformative'})), cls = 'sidecar'; end
            html = sprintf('<section class="section %s %s" data-component-id="%s" data-instance-id="%s"><div class="status">%s</div><h3>%s</h3><div class="note">%s</div></section>', ...
                cls, NMResultsViewerReportTools.htmlEscape(renderStatus), idText, instanceText, NMResultsViewerReportTools.htmlEscape(renderStatus), titleText, NMResultsViewerReportTools.htmlEscape(message));
        end

        function html = reportAppendixHtml(report, exportSpec)
            % reportAppendixHtml  Render concise static-report appendix notes.
            %#ok<INUSD> exportSpec reserved for Stage 8d5 concrete sidecar path listing.
            comps = report.Components;
            sidecarCount = 0;
            for ii=1:numel(comps)
                tables = comps(ii).SidecarTables;
                sidecarCount = sidecarCount + numel(fieldnames(tables));
            end
            html = sprintf(['<h2>Appendix / sidecars</h2><div class="note">Summary/full report modes show curated figures and compact tables. ' ...
                'Large or technical payload tables should be exported through MAT/JSON/CSV/XLSX sidecars. Component sidecar-table groups currently registered: %d.</div>'], sidecarCount);
        end

        function script = summaryReportPdfPreflightScript()
            % summaryReportPdfPreflightScript  Pack compact report components and browser artifacts into PDF pages.
            %
            % Text and table typography remains fixed. Selected compact model-performance visual
            % components may share a two-column row when that row fits the current page (or
            % when the leading component would move to a new page anyway). Only adapter-rendered
            % report artifact images are eligible for proportional scaling. Consecutive artifact
            % components are evaluated at the fixed scale set 100%, 92.5% and 85%.
            script = ['<script>(function(){' ...
                'function nmPdfPreflight(){' ...
                'var body=document.body;if(!body||!body.classList.contains("pdfTarget"))return;' ...
                'var probe=document.createElement("div");probe.setAttribute("aria-hidden","true");probe.style.cssText="position:absolute;left:-10000px;top:0;width:180mm;height:267mm;visibility:hidden;pointer-events:none";body.appendChild(probe);' ...
                'var pageHeight=probe.getBoundingClientRect().height;body.removeChild(probe);if(!(pageHeight>0))return;' ...
                'var scales=[1,.925,.85],safety=4,addedPageGap=0,maxLookahead=3;' ...
                'function docTop(el){return el.getBoundingClientRect().top+(window.scrollY||0);}' ...
                'function unitStart(section){var start=section,prev=section.previousElementSibling;while(prev&&(prev.tagName==="H2"||prev.classList.contains("reportClassifierHeading")||prev.classList.contains("featureContextHeading")||prev.classList.contains("featureComponentHeading"))){start=prev;prev=prev.previousElementSibling;}return start;}' ...
                'function artifactImage(section){var nodes=section.querySelectorAll(".rvReportViewerArtifact img");return nodes.length===1?nodes[0]:null;}' ...
                'function groupSpan(group){var first=group[0],last=group[group.length-1],start=unitStart(first.section),end=last.section;return end.getBoundingClientRect().bottom-start.getBoundingClientRect().top;}' ...
                'function groupHeight(group,scale){var natural=groupSpan(group),visual=0;for(var j=0;j<group.length;j++)visual+=group[j].height;return natural-visual+visual*scale;}' ...
                'function applyScale(item,scale){var img=item.image,r=img.getBoundingClientRect();if(!(r.width>0))return;img.style.width=Math.max(1,item.width*scale)+"px";img.style.maxWidth="100%";img.style.height="auto";img.style.marginLeft="auto";img.style.marginRight="auto";}' ...
                'function compactCandidate(section){return section&&section.getAttribute&&section.getAttribute("data-pdf-compact")==="true";}' ...
                'function compactPair(a,b){if(!compactCandidate(a)||!compactCandidate(b)||a.nextElementSibling!==b||a.parentElement!==b.parentElement)return false;var start=unitStart(a),effectiveTop=docTop(start)+addedPageGap,offset=((effectiveTop%pageHeight)+pageHeight)%pageHeight,remaining=pageHeight-offset,soloHeight=a.getBoundingClientRect().height,parent=a.parentElement,wrap=document.createElement("div");wrap.className="nmPdfCompactPair";parent.insertBefore(wrap,a);wrap.appendChild(a);wrap.appendChild(b);var pairHeight=wrap.getBoundingClientRect().height;if(pairHeight<=remaining-safety)return true;if(soloHeight>remaining-safety&&pairHeight<=pageHeight-safety){wrap.classList.add("nmPdfPageBreakBefore");addedPageGap+=remaining;return true;}parent.insertBefore(a,wrap);parent.insertBefore(b,wrap);parent.removeChild(wrap);return false;}' ...
                'function pairCompactSections(){var list=Array.prototype.slice.call(body.querySelectorAll("section.section[data-pdf-compact=\"true\"]"));for(var j=0;j+1<list.length;){if(compactPair(list[j],list[j+1]))j+=2;else j+=1;}}' ...
                'function consecutiveArtifacts(sections,index){var out=[];for(var j=index;j<sections.length&&out.length<maxLookahead;j++){var image=artifactImage(sections[j]);if(!image)break;var r=image.getBoundingClientRect();if(!(r.width>0&&r.height>0))break;out.push({section:sections[j],image:image,width:r.width,height:r.height});}return out;}' ...
                'function bestPlan(group,capacity){var best=null;for(var count=1;count<=group.length;count++){var subset=group.slice(0,count);for(var s=0;s<scales.length;s++){var scale=scales[s],h=groupHeight(subset,scale);if(h<=capacity-safety){if(!best||count>best.count||(count===best.count&&scale>best.scale))best={count:count,scale:scale,height:h};break;}}}return best;}' ...
                'pairCompactSections();var sections=body.querySelectorAll("section.section");' ...
                'for(var i=0;i<sections.length;i++){' ...
                'var firstImage=artifactImage(sections[i]);if(!firstImage)continue;' ...
                'var group=consecutiveArtifacts(sections,i);if(!group.length)continue;' ...
                'var start=unitStart(group[0].section),effectiveTop=docTop(start)+addedPageGap,offset=((effectiveTop%pageHeight)+pageHeight)%pageHeight,remaining=pageHeight-offset;' ...
                'var plan=bestPlan(group,remaining);' ...
                'if(!plan&&offset>safety){start.classList.add("nmPdfPageBreakBefore");addedPageGap+=remaining;remaining=pageHeight;plan=bestPlan(group,remaining);}' ...
                'if(!plan){plan={count:1,scale:scales[scales.length-1]};}' ...
                'for(var k=0;k<plan.count;k++)applyScale(group[k],plan.scale);' ...
                'i+=plan.count-1;' ...
                '}' ...
                'body.setAttribute("data-nm-pdf-preflight","ready");' ...
                '}' ...
                'if(document.readyState==="complete")nmPdfPreflight();else window.addEventListener("load",nmPdfPreflight,false);' ...
                '})();</script>'];
        end

        function css = summaryReportCss()
            % summaryReportCss  Return deterministic CSS for curated HTML/PDF reports.
            %
            % Syntax:
            %   css = NMResultsViewerReportTools.summaryReportCss()
            %
            % Outputs:
            %   css  One self-contained CSS character vector used by static HTML and
            %        PDF-target report documents.
            %
            % Layout contract:
            %   PDF-target HTML is fixed to the exact 180 mm A4 printable width. The
            %   PDF preflight owns compact two-column component packing plus discrete adapter-artifact
            %   scaling; CSS supplies only keep/break primitives and the two-column container.
            %   Ordinary SVG plots are never proportionally scaled, so report typography remains
            %   physically consistent; only explicitly compact components may use half-page width.
            %
            % Errors and diagnostics:
            %   None. Runtime measurement is performed by summaryReportPdfPreflightScript.
            %
            % Side effects:
            %   None.
            css = ['body{font-family:Arial,Helvetica,sans-serif;margin:24px;color:#111827;background:#fff}' ...
                'h1{font-size:24px;margin:0 0 4px}h2{font-size:18px;margin:22px 0 8px;border-bottom:1px solid #dbe4ef;padding-bottom:5px}' ...
                'h3{font-size:14px;margin:16px 0 7px}h4{font-size:12px;margin:11px 0 6px;color:#334155}.reportAnalysisHeading{margin:28px 0 10px;padding:9px 11px;border-left:6px solid #0f4c81;background:#eaf3fb;color:#0f172a}.reportOOCVGroupHeading{margin:18px 0 8px;padding:8px 10px;border-left:5px solid #475569;background:#f8fafc;color:#0f172a}.reportClassifierHeading{margin-top:22px;padding:8px 10px;border-left:5px solid #0f4c81;background:#eaf3fb;color:#0f172a}.performanceClassifierHeading{margin-top:14px}.optimizationClassifierHeading{margin-top:14px}.featureClassifierHeading{margin-top:22px}.featureContextHeading{margin-top:16px;padding:7px 9px;border-left:4px solid #2563eb;background:#eff6ff}.featureComponentHeading{margin:10px 0 5px 10px;color:#475569}.meta{color:#475569;font-size:12px;margin-bottom:14px}.desc{color:#334155;margin:8px 0 16px}' ...
                '.summaryGrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:10px;margin:14px 0 18px}' ...
                '.card{border:1px solid #dbe4ef;border-radius:10px;background:#f8fafc;padding:10px}.card .label{font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.04em}.card .value{font-size:20px;font-weight:800;color:#0f172a;margin-top:3px}.card .smallValue{font-size:16px}' ...
                '.section{border:1px solid #dbe4ef;border-radius:12px;padding:12px;margin:14px 0;page-break-inside:auto}.ok{}.unavailable{border-left:4px solid #dc2626}.sidecar{border-left:4px solid #64748b}.status{display:none}' ...
                '.note{font-size:12px;color:#475569;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:8px;margin:8px 0}.warn{color:#9a3412;background:#fff7ed;border-color:#fed7aa}' ...
                'table{border-collapse:collapse;width:100%;font-size:10.5px;margin:7px 0 12px;table-layout:fixed}th,td{border:1px solid #d1d5db;padding:4px 6px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#f3f4f6}td.numeric,th.numeric{text-align:right;white-space:nowrap}td.featureName,th.featureName{overflow-wrap:anywhere}td.wrapText,th.wrapText{white-space:normal;overflow-wrap:anywhere;word-break:break-word}' ...
                '.viz{margin:8px 0 12px;border:1px solid #e5e7eb;border-radius:10px;background:#fff;padding:8px;break-inside:avoid;page-break-inside:avoid}.viz svg{width:100%;height:auto;display:block}.rvReportViewerArtifact{margin:8px 0 12px;break-inside:avoid;page-break-inside:avoid}.rvReportViewerArtifact img{display:block;max-width:100%;height:auto;margin:0 auto}.rvReportViewerArtifact figcaption{font-size:11px;color:#475569;margin-top:4px}.rvReportViewerMetadata{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:2px 12px;margin:-6px 0 12px;padding:5px 7px;border:1px solid #e2e8f0;border-radius:7px;background:#f8fafc;color:#475569;font-size:9px;line-height:1.18;break-inside:avoid;page-break-inside:avoid}.rvReportViewerMetadata span{min-width:0;overflow-wrap:anywhere}.featureMetricPanelGrid{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(260px,.75fr);gap:10px;align-items:stretch}.featureMetricPanelGrid .viz{margin:0}.featureMetricPanelGrid>.featureBarPanel{display:flex;align-items:flex-start;box-sizing:border-box}.featureMetricPanelGrid>.featureBarPanel svg{width:100%;height:auto;min-height:0}.featureMetricPanelAside{display:grid;grid-template-rows:auto 1fr;gap:10px;align-content:stretch;height:100%}.featureMetricDistributionStats{border:1px solid #e5e7eb;border-radius:10px;background:#f8fafc;padding:8px}.featureMetricDistributionStats table{margin:6px 0 0;font-size:10.5px}.featureMetricDistributionStats th,.featureMetricDistributionStats td{padding:3px 5px}.fusionReportContext{display:flex;flex-wrap:wrap;gap:5px 14px;margin:2px 0 8px;padding:6px 8px;border:1px solid #dbeafe;border-radius:8px;background:#f8fbff;color:#334155;font-size:10.5px}.fusionReportGrid{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(300px,.75fr);gap:10px;align-items:start}.fusionReportGrid .viz{margin:0}.fusionReportTable{border:1px solid #e5e7eb;border-radius:10px;background:#fff;padding:7px;overflow:hidden}.fusionReportTable table{margin:0;font-size:9.5px}.fusionReportTable th,.fusionReportTable td{padding:3px 4px}.featureRelationReport{display:block}.relationReportDetails{border:1px solid #dbe4ef;border-radius:9px;background:#f8fafc;padding:8px;margin:6px 0 10px}.relationReportDetails table{margin:4px 0 0}.fullPrunedGraphReport{break-inside:avoid;page-break-inside:avoid}.relationPatternGallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:10px;align-items:start}.relationPatternTile{border:1px solid #dbe4ef;border-radius:10px;background:#fff;padding:7px;break-inside:avoid;page-break-inside:avoid}.relationPatternTile header{display:flex;justify-content:space-between;gap:8px;align-items:baseline;margin:0 0 4px;font-size:10.5px;color:#334155}.relationPatternTile header strong{color:#0f172a}.relationPatternTile .viz{border:0;padding:0;margin:0}.scientificTableViewport{max-width:100%;overflow-x:auto}.graphNodeStatisticsTable{table-layout:fixed}.graphNodeStatisticsTable thead{display:table-header-group}.graphNodeStatisticsTable th{white-space:normal;overflow:visible;overflow-wrap:normal;word-break:normal;line-height:1.12;vertical-align:bottom;text-align:right}.graphNodeStatisticsTable th.graphFeatureHeader{text-align:left}.graphNodeStatisticsTable td{white-space:nowrap;overflow:visible;overflow-wrap:normal;word-break:normal}.graphNodeStatisticsTable td.graphFeatureCell{text-align:left;white-space:nowrap}.graphNodeStatisticsRowSummary{margin-top:-6px;margin-bottom:10px}.graphStatisticsDisclaimer{border-left:3px solid #94a3b8;padding-left:7px}.small{font-size:11px;color:#64748b}.footerNote{font-size:11px;color:#64748b;margin-top:20px;border-top:1px solid #e2e8f0;padding-top:8px}' ...
                '@page{size:A4;margin:15mm}' ...
                'body.pdfTarget{margin:0;width:180mm;max-width:180mm}.pdfTarget h1{font-size:20px}.pdfTarget h2{break-before:auto;page-break-before:auto;font-size:15px;margin:14px 0 6px}.pdfTarget .reportAnalysisHeading{font-size:15px;margin:18px 0 7px}.pdfTarget h2,.pdfTarget .reportOOCVGroupHeading,.pdfTarget .reportClassifierHeading,.pdfTarget .featureContextHeading,.pdfTarget .featureComponentHeading{break-after:avoid;page-break-after:avoid}.pdfTarget h3{font-size:11.5px;margin:9px 0 5px}.pdfTarget .meta,.pdfTarget .note,.pdfTarget .small{font-size:9px}.pdfTarget .summaryGrid{gap:6px;margin:8px 0 10px}.pdfTarget .card{padding:6px}.pdfTarget .card .label{font-size:8px}.pdfTarget .card .value{font-size:15px}.pdfTarget .section{padding:7px;margin:8px 0}.pdfTarget table{font-size:8px;line-height:1.12;margin:4px 0 7px}.pdfTarget th,.pdfTarget td{padding:2px 3px;overflow-wrap:normal;word-break:normal}.pdfTarget tr{break-inside:avoid;page-break-inside:avoid}.pdfTarget td.numeric,.pdfTarget th.numeric{white-space:nowrap;width:46px;text-align:right}.pdfTarget td.featureName,.pdfTarget th.featureName{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:210px;overflow-wrap:normal;word-break:normal}.pdfTarget td.wrapText,.pdfTarget th.wrapText{white-space:normal!important;overflow-wrap:anywhere!important;word-break:break-word!important}.pdfTarget .featureMetricDistributionStats{padding:5px}.pdfTarget .featureMetricDistributionStats table{font-size:7.5px;margin:3px 0 0}.pdfTarget .featureMetricDistributionStats th,.pdfTarget .featureMetricDistributionStats td{padding:1px 3px}' ...
                '.pdfTarget .card,.pdfTarget .viz,.pdfTarget .rvReportViewerArtifact{break-inside:avoid;page-break-inside:avoid}.pdfTarget .section>h3{break-after:avoid;page-break-after:avoid}.pdfTarget .rvReportViewerArtifact img{max-width:100%;width:auto;height:auto}.pdfTarget .reportContextTable table{table-layout:fixed;width:100%}.pdfTarget .reportContextTable th:first-child,.pdfTarget .reportContextTable td:first-child{width:25%!important}.pdfTarget .reportContextTable th:nth-child(2),.pdfTarget .reportContextTable td:nth-child(2){width:75%!important;white-space:normal!important;overflow-wrap:anywhere!important;word-break:normal!important;text-align:left!important}.pdfTarget .nmPdfCompactPair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:6px;align-items:start;break-inside:avoid;page-break-inside:avoid}.pdfTarget .nmPdfCompactPair>.section{margin:0;min-width:0}.pdfTarget .nmPdfPageBreakBefore{break-before:page!important;page-break-before:always!important}.pdfTarget .rvReportViewerArtifact figcaption{font-size:9px}.pdfTarget .rvReportViewerMetadata{grid-template-columns:repeat(2,minmax(0,1fr));gap:1px 8px;margin:-3px 0 7px;padding:3px 5px;font-size:7px;line-height:1.12}.pdfTarget .featureMetricPanelGrid,.pdfTarget .fusionReportGrid{grid-template-columns:minmax(0,1.2fr) minmax(0,.8fr);break-inside:auto;page-break-inside:auto}.pdfTarget .fusionReportContext{font-size:8px;padding:4px 5px}.pdfTarget .fusionReportTable table{font-size:7.5px}.pdfTarget section[data-component-id^="model_feature_inspection.feature_metric_relationship"]{break-inside:avoid;page-break-inside:avoid}.pdfTarget .featureMetricRelationship{break-inside:avoid;page-break-inside:avoid}.pdfTarget .viz svg{max-height:none}.pdfTarget .featureBarPanel svg{max-height:none;height:auto}.pdfTarget .relationPatternGallery{grid-template-columns:repeat(3,minmax(0,1fr));gap:4px}.pdfTarget .relationPatternTile{padding:3px}.pdfTarget .relationPatternTile header{font-size:7.5px}.pdfTarget .relationPatternTile .viz svg{max-height:58mm}.pdfTarget .relationReportDetails{padding:4px}.pdfTarget .graphNodeStatisticsViewport{overflow:visible}.pdfTarget .graphNodeStatisticsTable{width:100%!important;min-width:0!important;table-layout:fixed;font-size:7.2px;line-height:1.08}.pdfTarget .graphNodeStatisticsTable col{width:var(--graph-col-pdf)!important}.pdfTarget .graphNodeStatisticsTable th{white-space:normal!important;width:auto!important;overflow:visible!important;overflow-wrap:normal!important;word-break:normal!important;text-align:right}.pdfTarget .graphNodeStatisticsTable th.graphFeatureHeader{text-align:left}.pdfTarget .graphNodeStatisticsTable td{white-space:nowrap!important;width:auto!important;overflow:visible!important}.pdfTarget .graphNodeStatisticsTable td.graphFeatureCell{white-space:normal!important;overflow-wrap:anywhere!important;word-break:normal!important}.pdfTarget .graphNodeStatisticsTable thead{display:table-header-group}.pdfTarget .graphNodeStatisticsTable tbody tr{break-inside:avoid;page-break-inside:avoid}' ...
                '.pdfTarget section[data-component-id="model_feature_inspection.fractionated_decision"] .viz svg{max-height:205mm;width:auto;margin:0 auto}' ...
                '.reportMatrixFigure{margin:8px 0 12px;border:1px solid #e5e7eb;border-radius:8px;padding:8px;break-inside:auto;page-break-inside:auto}.reportMatrixKey{display:flex;align-items:center;gap:5px;flex-wrap:wrap;color:#475569;font-size:10px;margin:2px 0 7px}.reportMatrixKeySwatch{width:12px;height:10px;border:1px solid #cbd5e1;display:inline-block;margin-left:8px}.reportMatrixColumnNote{margin-left:auto}.reportMatrixTable{border-collapse:collapse;table-layout:fixed;width:100%;margin:0}.reportMatrixTable thead{display:table-header-group}.reportMatrixTable tbody{display:table-row-group}.reportMatrixTable tr{break-inside:avoid;page-break-inside:avoid}.reportMatrixTable th,.reportMatrixTable td{overflow:visible;overflow-wrap:normal;word-break:normal;padding:0;text-align:center;border:0.5px solid #fff}.reportMatrixTable .reportMatrixRowHeader{white-space:normal;overflow-wrap:anywhere;word-wrap:break-word;word-break:break-word;text-align:right;padding:0 4px 0 0;background:#fff;font-size:8px;font-weight:normal;color:#475569;border-right:1px solid #94a3b8}.reportMatrixTable .reportMatrixColumnHeader{height:20px;vertical-align:middle;background:#fff;font-weight:normal;font-size:7px;line-height:1;color:#334155;white-space:nowrap}.reportMatrixTable tbody td{height:12px;min-height:12px;-webkit-print-color-adjust:exact;print-color-adjust:exact}.reportClusterMatrix .reportMatrixTable{max-width:560px}.reportClusterMatrix .reportMatrixTable tbody td{height:17px;font-size:8px;color:#0f172a}.pdfTarget .reportMatrixFigure{break-inside:auto!important;page-break-inside:auto!important}.pdfTarget .reportMatrixTable thead{display:table-header-group}.pdfTarget .reportMatrixTable tr{break-inside:avoid;page-break-inside:avoid}' ...
                '.pdfTarget .footerNote{page-break-inside:avoid}' ...
                '@media(max-width:900px){body:not(.pdfTarget) .fusionReportGrid{grid-template-columns:1fr}}' ...
                '@media print{body{margin:0}.card,.viz,.rvReportViewerArtifact{break-inside:avoid;page-break-inside:avoid}.section>h3{break-after:avoid;page-break-after:avoid}.rvReportViewerArtifact img{max-width:100%;width:auto;height:auto}h2{break-before:auto;page-break-before:auto}h2,.reportClassifierHeading,.featureContextHeading,.featureComponentHeading{break-after:avoid;page-break-after:avoid}section[data-component-id^="model_feature_inspection.feature_metric_relationship"]{break-inside:avoid;page-break-inside:avoid}.viz svg{max-height:none}.featureBarPanel svg{max-height:none;height:auto}.featureMetricPanelGrid,.fusionReportGrid{grid-template-columns:minmax(0,1.2fr) minmax(0,.8fr);break-inside:auto;page-break-inside:auto}.featureMetricPanelAside{grid-template-rows:auto 1fr}.relationPatternGallery{grid-template-columns:repeat(3,minmax(0,1fr));gap:4px}.relationPatternTile{padding:3px}.relationPatternTile header{font-size:7.5px}.relationPatternTile .viz svg{max-height:58mm}.graphNodeStatisticsViewport{overflow:visible}.graphNodeStatisticsTable{width:100%!important;min-width:0!important;table-layout:fixed;font-size:7.2px;line-height:1.08}.graphNodeStatisticsTable col{width:var(--graph-col-pdf)!important}.graphNodeStatisticsTable th{white-space:normal!important;width:auto!important;overflow:visible!important;overflow-wrap:normal!important;word-break:normal!important}.graphNodeStatisticsTable td{white-space:nowrap!important;width:auto!important;overflow:visible!important}.graphNodeStatisticsTable td.graphFeatureCell{white-space:normal!important;overflow-wrap:anywhere!important}.graphNodeStatisticsTable thead{display:table-header-group}.graphNodeStatisticsTable tbody tr{break-inside:avoid;page-break-inside:avoid}}'];
        end

        function html = reportSummaryCardsHtml(comps)
            % reportSummaryCardsHtml  Count actual report output states without conflating table-only output with unavailability.
            n = numel(comps);
            rendered = 0; tableOnly = 0; sidecarOnly = 0; skipped = 0; unavailable = 0;
            for ii = 1:n
                st = comps(ii).RenderStatus;
                switch st
                    case 'rendered'
                        rendered = rendered + 1;
                    case 'table_only'
                        tableOnly = tableOnly + 1;
                    case 'sidecar_only'
                        sidecarOnly = sidecarOnly + 1;
                    case 'skipped_noninformative'
                        skipped = skipped + 1;
                    otherwise
                        unavailable = unavailable + 1;
                end
            end
            html = sprintf(['<div class="summaryGrid">' ...
                '<div class="card"><div class="label">Output sections</div><div class="value">%d</div></div>' ...
                '<div class="card"><div class="label">Rendered</div><div class="value">%d</div></div>' ...
                '<div class="card"><div class="label">Table only</div><div class="value">%d</div></div>' ...
                '<div class="card"><div class="label">Sidecar only</div><div class="value">%d</div></div>' ...
                '<div class="card"><div class="label">Skipped</div><div class="value">%d</div></div>' ...
                '<div class="card"><div class="label">Unavailable</div><div class="value">%d</div></div>' ...
                '</div>'], n, rendered, tableOnly, sidecarOnly, skipped, unavailable);
        end

        function html = reportWarningsHtml(comps)
            % reportWarningsHtml  Render compact report warnings and non-informative diagnostics.
            warnings = {};
            for ii = 1:numel(comps)
                titleText = comps(ii).Title;
                reason = comps(ii).MissingReason;
                if ~isempty(reason)
                    warnings{end+1} = sprintf('%s: %s', titleText, reason); %#ok<AGROW>
                end
                if ~isempty(comps(ii).Warnings)
                    compWarnings = comps(ii).Warnings;
                    for ww=1:numel(compWarnings)
                        msg = compWarnings{ww};
                        if ~isempty(strtrim(msg))
                            warnings{end+1} = sprintf('%s: %s', titleText, msg); %#ok<AGROW>
                        end
                    end
                end
                assoc = NMResultsViewerReportTools.componentTable(comps(ii), 'associations');
                if ~isempty(assoc)
                    for jj = 1:numel(assoc)
                        msg = NMResultsViewerReportTools.safeField(assoc(jj),'lowDynamicRangeWarning','');
                        if ~isempty(msg)
                            warnings{end+1} = sprintf('%s: %s', titleText, msg); %#ok<AGROW>
                            break;
                        end
                    end
                end
            end
            if isempty(warnings)
                html = '<div class="note">No unavailable report components, component warnings or low-dynamic-range warnings were detected.</div>';
                return;
            end
            items = cell(1, min(numel(warnings), 10));
            for ii = 1:numel(items)
                items{ii} = ['<li>' NMResultsViewerReportTools.htmlEscape(warnings{ii}) '</li>'];
            end
            more = '';
            if numel(warnings) > numel(items), more = sprintf('<div class="small">Additional warnings: %d</div>', numel(warnings)-numel(items)); end
            html = ['<div class="note warn"><strong>Warnings / unavailable components</strong><ul>' strjoin(items, '') '</ul>' more '</div>'];
        end

        function c = componentById(comps, id)
            % componentById  Return the first report component with a matching id.
            c = [];
            for ii = 1:numel(comps)
                if strcmp(comps(ii).Id, id)
                    c = comps(ii);
                    return;
                end
            end
        end

        function rows = componentTableById(comps, id, tableName)
            % componentTableById  Return a named table from a matching component.
            c = NMResultsViewerReportTools.componentById(comps, id);
            rows = NMResultsViewerReportTools.componentTable(c, tableName);
        end

        function rows = componentTable(component, tableName)
            % componentTable  Return one component table payload by name.
            rows = [];
            if isempty(component), return; end
            tables = component.Tables;
            % nm2-allow: reportComponentTemplate Tables holds optional component-specific table fields, selected by renderer
            if isfield(tables, tableName)
                rows = tables.(tableName);
            end
        end



        function rows = metricRegistryFiniteRows(registryRows)
            % metricRegistryFiniteRows  Keep metric-registry rows with usable finite values for report body.
            rows = registryRows;
            if isempty(registryRows), return; end
            keep = false(1,numel(registryRows));
            for ii=1:numel(registryRows)
                nFinite = registryRows(ii).nFinite;
                keep(ii) = isfinite(nFinite) && nFinite > 0;
            end
            rows = registryRows(keep);
        end

        function rows = metricRegistryUnavailableRows(registryRows)
            % metricRegistryUnavailableRows  Return metric-registry rows omitted from scientific summaries.
            rows = registryRows;
            if isempty(registryRows), return; end
            keep = false(1,numel(registryRows));
            for ii=1:numel(registryRows)
                nFinite = registryRows(ii).nFinite;
                available = registryRows(ii).available;
                keep(ii) = ~available || ~isfinite(nFinite) || nFinite <= 0;
            end
            rows = registryRows(keep);
        end

        function html = metricDashboardPanelsHtml(metricRows, maxRows)
            % metricDashboardPanelsHtml  Render metric-dashboard curves as unit-consistent panels.
            if isempty(metricRows), html = ''; return; end
            metricKeys = NMResultsViewerReportTools.rowTextArray(metricRows, 'metricId');
            metricLabels = NMResultsViewerReportTools.rowTextArray(metricRows, 'metricLabel');
            for ii=1:numel(metricKeys)
                if isempty(metricKeys{ii}), metricKeys{ii} = metricLabels{ii}; end
                if isempty(metricKeys{ii}), metricKeys{ii} = 'metric'; end
            end
            uKeys = unique(metricKeys, 'stable');
            chunks = cell(1,0);
            bestRows = struct('seriesLabel',{},'modelIndex',{},'modelLabel',{},'value',{},'parameterValues',{});
            for kk=1:min(numel(uKeys), max(1,maxRows))
                mask = strcmp(metricKeys, uKeys{kk});
                panelRows = metricRows(mask);
                titleText = uKeys{kk};
                if ~isempty(panelRows)
                    labelText = panelRows(1).metricLabel;
                    if ~isempty(labelText), titleText = labelText; end
                end
                chunks{end+1} = NMResultsViewerReportFigureTools.optimizationCurveSvg(panelRows, titleText); %#ok<AGROW>
                br = NMResultsViewerReportTools.bestMetricRows(panelRows);
                if ~isempty(br), bestRows = [bestRows br]; end %#ok<AGROW>
            end
            note = '';
            if numel(uKeys) > maxRows
                note = sprintf('<div class="small">Showing %d of %d metric families; full metric rows are sidecar/technical payloads.</div>', maxRows, numel(uKeys));
            end
            html = [strjoin(chunks,'') note NMResultsViewerReportTools.structRowsHtml(bestRows, {'seriesLabel','modelIndex','modelLabel','value','parameterValues'}, {'Series','Best model index','Model','Value','Parameters'}, maxRows)];
        end

        function rows = bestMetricRows(metricValues)
            % bestMetricRows  Select finite extrema on the producer-resolved metric direction.
            tmpl = struct('seriesLabel','','modelIndex',NaN,'modelLabel','','value',NaN,'parameterValues','');
            rows = tmpl([]);
            if isempty(metricValues), return; end
            labels = {metricValues.seriesLabel};
            uLabels = unique(labels, 'stable');
            tmp = repmat(tmpl, 1, numel(uLabels));
            nKeep = 0;
            for ss = 1:numel(uLabels)
                idx = find(strcmp(labels, uLabels{ss}));
                direction = [metricValues(idx).directionSign];
                if ~ismember(direction(1),[-1 1]) || any(direction ~= direction(1))
                    error('NMResultsViewerReportTools:InvalidMetricDirection', ...
                        'Optimization rows with one series identity must share a valid directionSign.');
                end
                values = [metricValues(idx).value];
                if ~any(isfinite(values)), continue; end
                ranked = direction(1) * values;
                ranked(~isfinite(ranked)) = -Inf;
                [~,bestLocal] = max(ranked);
                r = metricValues(idx(bestLocal));
                nKeep = nKeep + 1;
                tmp(nKeep).seriesLabel = uLabels{ss};
                tmp(nKeep).modelIndex = r.modelIndex;
                tmp(nKeep).modelLabel = r.modelLabel;
                tmp(nKeep).value = r.value;
                tmp(nKeep).parameterValues = r.parameterValues;
            end
            rows = tmp(1:nKeep);
        end

        function rows = bestSurfaceRows(surfaceRows, maxRows)
            % bestSurfaceRows  Rank surface cells using the producer-resolved directionSign.
            rows = surfaceRows;
            if isempty(surfaceRows), return; end
            directions = [surfaceRows.directionSign];
            if any(~ismember(directions,[-1 1]))
                error('NMResultsViewerReportTools:InvalidMetricDirection', ...
                    'Parameter-surface rows must carry the resolved optimization directionSign.');
            end
            [~,ord] = sort([surfaceRows.aggregateValue] .* directions, 'descend', 'MissingPlacement','last');
            ord = ord(1:min(numel(ord), maxRows));
            rows = surfaceRows(ord);
        end

        function rows = partitionSummaryRows(cvRows)
            % partitionSummaryRows  Summarize finite numerical entries, not inferred execution completion.
            kinds = NMResultsViewerReportTools.uniqueRowText(cvRows, 'partitionKind');
            tmpl = struct('partitionKind','','title','','n',0,'nMissing',0,'min',NaN,'max',NaN,'mean',NaN,'maskSource','');
            rows = repmat(tmpl, 1, numel(kinds));
            for kk = 1:numel(kinds)
                mask = strcmp(NMResultsViewerReportTools.rowTextArray(cvRows,'partitionKind'), kinds{kk});
                partRows = cvRows(mask);
                vals = NMResultsViewerReportTools.rowNumberArray(partRows,'value');
                computed = [partRows.computed];
                src = {partRows.maskSource};
                sourceText = strjoin(unique(src(~cellfun(@isempty,src)), 'stable'), ', ');
                good = vals(computed(:)');
                rows(kk).partitionKind = kinds{kk};
                rows(kk).title = kinds{kk};
                rows(kk).n = numel(good);
                rows(kk).nMissing = nnz(~computed);
                rows(kk).maskSource = sourceText;
                if ~isempty(good)
                    rows(kk).min = min(good); rows(kk).max = max(good); rows(kk).mean = mean(good);
                end
            end
        end



        function tf = allAssociationsLowDynamicRange(rows)
            % allAssociationsLowDynamicRange  Detect non-informative scatter/Pareto components.
            tf = false;
            if isempty(rows), return; end
            nSeen = 0;
            nLow = 0;
            for ii=1:numel(rows)
                msg = rows(ii).lowDynamicRangeWarning;
                nSeen = nSeen + 1;
                if ~isempty(strtrim(msg)), nLow = nLow + 1; end
            end
            tf = nSeen > 0 && nLow == nSeen;
        end

        function html = featureMetricCompactTableHtml(rows, maxRows)
            % featureMetricCompactTableHtml  Render a non-redundant feature-metric table preview.
            %
            % The visible report table avoids repeating threshold-pass states, source
            % field names and per-row modality provenance because those are either encoded
            % in the plot or preserved in sidecars for audit/reproducibility.
            if isempty(rows)
                html = '<div class="small">No feature rows available.</div>';
                return;
            end
            fields = {'featureName','displayValue','displaySE','sortAbsRank'};
            labels = {'Feature','Value','SE','Rank'};
            html = NMResultsViewerReportTools.structRowsHtml(rows, fields, labels, maxRows, {{'displaySE'}});
        end

        function [fields, labels] = featureMetricVisibleTableColumns(rows)
            % featureMetricVisibleTableColumns  Keep only informative feature-metric columns for summary reports.
            allFields = {'featureName','meanWeight','crossValidationRatio','featureSelectionProbability','signConsistencyZ','signConsistencyLogP','permutationLogQ','analyticalLogQ','featureKind'};
            allLabels = {'Feature','Mean weight','CV ratio','Selection probability','SBC z','SBC -log10(P)','Permutation -log10(q)','Analytical -log10(q)','Kind'};
            fields = allFields; labels = allLabels;
            if isempty(rows), return; end
            % nm2-allow: buildModelFeatureInspectionComponentWithSession writes modality only for combined feature-metric tables.
            if isfield(rows,'modality')
                allFields = [allFields(1) {'modality'} allFields(2:end)];
                allLabels = [allLabels(1) {'Modality'} allLabels(2:end)];
            end
            keep = true(1,numel(allFields));
            for ii = 2:numel(allFields)
                if strcmp(allFields{ii}, 'modality')
                    continue;
                elseif strcmp(allFields{ii}, 'featureKind')
                    vals = NMResultsViewerReportTools.rowTextArray(rows, allFields{ii});
                    keep(ii) = numel(unique(vals(~cellfun(@isempty, vals)))) > 1;
                else
                    vals = NMResultsViewerReportTools.structNumericArray(rows, allFields{ii});
                    keep(ii) = any(isfinite(vals));
                end
            end
            fields = allFields(keep); labels = allLabels(keep);
        end

        function html = modelFeatureGraphNodeStatisticsTableHtml(rows, graph)
            % modelFeatureGraphNodeStatisticsTableHtml  Render the complete canonical graph-node table with adaptive widths.
            %
            % Syntax:
            %   html = NMResultsViewerReportTools.modelFeatureGraphNodeStatisticsTableHtml(rows,graph)
            %
            % Inputs:
            %   rows   Canonical node rows from the full exported pruned graph.
            %   graph  Canonical graph contract containing nodeCount and scientific identity.
            %
            % Outputs:
            %   html  Scroll-safe HTML and paginated PDF table containing every graph node.
            %
            % Scientific contract:
            %   Exactly one row is emitted for every node in the exported full pruned graph.
            %   Generic report-preview limits and feature-panel TableRowCount values do not
            %   truncate this canonical scientific table.
            %
            % Layout contract:
            %   The Feature column is measured from the actual rendered labels. Numeric-column
            %   minima are measured from their formatted body values and longest semantic header
            %   token. Residual width is allocated by a deterministic weighted water-filling
            %   algorithm. HTML preserves the natural minimum table width and scrolls when
            %   necessary; PDF uses semantic two-line headers and wraps only feature labels.
            %
            % Errors and diagnostics:
            %   Throws NMResultsViewer:GraphNodeTableRowMismatch when graph nodeCount and the
            %   canonical row count disagree. Width metadata is embedded in data attributes.
            %
            % Side effects:
            %   None.
            if isempty(rows)
                html='<div class="small">No graph-node statistics are available.</div>';
                return;
            end
            expected=double(graph.nodeCount);
            if ~isscalar(expected) || ~isfinite(expected), expected=numel(rows); end
            expected=round(expected);
            if expected~=numel(rows)
                error('NMResultsViewer:GraphNodeTableRowMismatch', ...
                    'The exported graph contains %d nodes but its canonical node-statistics table contains %d rows.',expected,numel(rows));
            end
            descriptors=NMResultsViewerReportTools.graphNodeStatisticsColumnDescriptors();
            layout=NMResultsViewerReportTools.computeGraphNodeStatisticsColumnWidths(rows,descriptors);
            cols=cell(1,numel(descriptors));
            heads=cell(1,numel(descriptors));
            for cc=1:numel(descriptors)
                cols{cc}=sprintf(['<col class="graphNodeStatisticsCol graphNodeStatisticsCol-%s" ' ...
                    'style="--graph-col-html:%.3fpx;--graph-col-pdf:%.5f%%;width:var(--graph-col-html)">'], ...
                    descriptors(cc).cssToken,layout.htmlWidths(cc),layout.pdfPercent(cc));
                lines=descriptors(cc).headerLines;
                escaped=cell(size(lines));
                for ll=1:numel(lines), escaped{ll}=NMResultsViewerReportTools.htmlEscape(lines{ll}); end
                headClass='graphNodeStatisticsHeader';
                if strcmp(descriptors(cc).type,'text'), headClass=[headClass ' graphFeatureHeader']; else, headClass=[headClass ' numeric']; end %#ok<AGROW>
                heads{cc}=sprintf('<th class="%s" scope="col"><span>%s</span></th>',headClass,strjoin(escaped,'<br>'));
            end
            body=cell(1,numel(rows));
            for rr=1:numel(rows)
                cells=cell(1,numel(descriptors));
                for cc=1:numel(descriptors)
                    txt=NMResultsViewerReportTools.graphNodeStatisticsFormattedValue(rows(rr),descriptors(cc));
                    if strcmp(descriptors(cc).type,'text')
                        cls='graphFeatureCell';
                    else
                        cls='numeric graphNodeNumericCell';
                    end
                    cells{cc}=sprintf('<td class="%s">%s</td>',cls,NMResultsViewerReportTools.htmlEscape(txt));
                end
                body{rr}=sprintf('<tr class="graphNodeStatisticsRow" data-node-row="%d">%s</tr>',rr,strjoin(cells,''));
            end
            footer=sprintf('<div class="small graphNodeStatisticsRowSummary">%d nodes &middot; %d rows shown</div>',expected,numel(rows));
            html=sprintf(['<div class="scientificTableViewport graphNodeStatisticsViewport" ' ...
                'data-layout-width="%.3f" data-feature-column-width="%.3f" ' ...
                'data-feature-natural-width="%.3f" data-minimum-table-width="%.3f" data-row-count="%d">' ...
                '<table class="scientificTable graphNodeStatisticsTable" style="width:%.3fpx;min-width:%.3fpx">' ...
                '<colgroup>%s</colgroup><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>%s'], ...
                layout.htmlTotalWidth,layout.htmlWidths(1),layout.featureNaturalWidth,layout.minimumTableWidth,numel(rows), ...
                layout.htmlTotalWidth,layout.htmlTotalWidth,strjoin(cols,''),strjoin(heads,''),strjoin(body,sprintf('\n')),footer);
        end

        function descriptors = graphNodeStatisticsColumnDescriptors()
            % graphNodeStatisticsColumnDescriptors  Return the semantic schema for graph-node report columns.
            %
            % Outputs:
            %   descriptors  Fixed-schema column descriptors defining field, semantic header
            %                lines, value type, CSS token, and expansion priority.
            %
            % Side effects:
            %   None.
            descriptors=struct( ...
                'field',{'label','featureIndex','degree','absoluteStrength','positiveStrength','negativeStrength','betweennessCentrality','harmonicCloseness','eigenvectorCentrality','connectedComponentId','componentSize'}, ...
                'headerLines',{{'Feature'},{'Index'},{'Degree'},{'Absolute','strength'},{'Positive','strength'},{'Negative','strength'},{'Betweenness'},{'Harmonic','closeness'},{'Eigenvector','centrality'},{'Component'},{'Component','size'}}, ...
                'type',{'text','integer','integer','metric','metric','metric','metric','metric','metric','integer','integer'}, ...
                'cssToken',{'feature','index','degree','absolute-strength','positive-strength','negative-strength','betweenness','harmonic-closeness','eigenvector-centrality','component','component-size'}, ...
                'expansionWeight',{4.0,0.5,0.5,1.3,1.2,1.2,1.1,1.8,1.8,0.6,0.7});
        end

        function layout = computeGraphNodeStatisticsColumnWidths(rows,descriptors)
            % computeGraphNodeStatisticsColumnWidths  Measure and allocate graph-node table columns without toolboxes.
            %
            % Inputs:
            %   rows         Canonical node-statistics rows.
            %   descriptors  Semantic descriptors from graphNodeStatisticsColumnDescriptors.
            %
            % Outputs:
            %   layout  HTML pixel widths, PDF percentages, measured feature width, and
            %           minimum-width diagnostics.
            %
            % Layout algorithm:
            %   Body values and semantic header tokens define hard minima. Complete headers
            %   define preferred widths. Remaining width is distributed according to unmet
            %   preferred-width demand and expansion weights. Columns stop growing at their
            %   preferred width; residual space then belongs to the Feature column.
            %
            % Side effects:
            %   None.
            n=numel(descriptors);
            htmlFont=10.5; pdfFont=7.2;
            htmlPad=14; pdfPad=8;
            htmlMin=zeros(1,n); htmlPref=zeros(1,n);
            pdfMin=zeros(1,n); pdfPref=zeros(1,n);
            for cc=1:n
                body=cell(1,numel(rows));
                for rr=1:numel(rows)
                    body{rr}=NMResultsViewerReportTools.graphNodeStatisticsFormattedValue(rows(rr),descriptors(cc));
                end
                bodyHtml=0; bodyPdf=0;
                for rr=1:numel(body)
                    bodyHtml=max(bodyHtml,NMResultsViewerReportTools.reportApproxTextWidthPx(body{rr},htmlFont));
                    bodyPdf=max(bodyPdf,NMResultsViewerReportTools.reportApproxTextWidthPx(body{rr},pdfFont));
                end
                lineHtml=0; linePdf=0;
                for ll=1:numel(descriptors(cc).headerLines)
                    lineHtml=max(lineHtml,NMResultsViewerReportTools.reportApproxTextWidthPx(descriptors(cc).headerLines{ll},htmlFont));
                    linePdf=max(linePdf,NMResultsViewerReportTools.reportApproxTextWidthPx(descriptors(cc).headerLines{ll},pdfFont));
                end
                fullHeader=strjoin(descriptors(cc).headerLines,' ');
                htmlMin(cc)=max(bodyHtml,lineHtml)+htmlPad;
                htmlPref(cc)=max(bodyHtml,NMResultsViewerReportTools.reportApproxTextWidthPx(fullHeader,htmlFont))+htmlPad;
                pdfMin(cc)=max(bodyPdf,linePdf)+pdfPad;
                pdfPref(cc)=max(bodyPdf,NMResultsViewerReportTools.reportApproxTextWidthPx(fullHeader,pdfFont))+pdfPad;
            end
            featureNatural=htmlMin(1);
            htmlMin(1)=max(130,featureNatural);
            htmlPref(1)=max(htmlMin(1),featureNatural);
            htmlTarget=max(1040,sum(htmlMin));
            htmlWidths=NMResultsViewerReportTools.allocateReportColumnWidths(htmlMin,htmlPref,[descriptors.expansionWeight],htmlTarget,1);

            % Portrait PDF layout: preserve a readable feature column and semantic header
            % tokens. Long feature labels wrap; numeric values remain single-line.
            pdfMin(1)=max(92,min(pdfMin(1),160));
            pdfPref(1)=max(pdfMin(1),min(pdfPref(1),190));
            numericFloor=[0 34 38 46 46 46 48 52 56 50 50];
            pdfMin=max(pdfMin,numericFloor);
            pdfTarget=680;
            if sum(pdfMin)>pdfTarget
                compressible=2:n;
                excess=sum(pdfMin)-pdfTarget;
                room=max(0,pdfMin(compressible)-numericFloor(compressible));
                if sum(room)>0
                    take=min(room,excess*room/sum(room));
                    pdfMin(compressible)=pdfMin(compressible)-take;
                end
            end
            if sum(pdfMin)>pdfTarget+1e-6
                error('NMResultsViewer:InfeasibleReportTableLayout', ...
                    'The graph-node statistics table minimum width %.2f exceeds the PDF layout width %.2f.',sum(pdfMin),pdfTarget);
            end
            pdfWidths=NMResultsViewerReportTools.allocateReportColumnWidths(pdfMin,pdfPref,[descriptors.expansionWeight],pdfTarget,1);
            layout=struct('htmlWidths',htmlWidths,'htmlTotalWidth',sum(htmlWidths), ...
                'pdfWidths',pdfWidths,'pdfPercent',100*pdfWidths/sum(pdfWidths), ...
                'featureNaturalWidth',featureNatural,'minimumTableWidth',sum(htmlMin));
        end

        function widths = allocateReportColumnWidths(minWidths,preferredWidths,weights,targetWidth,featureColumn)
            % allocateReportColumnWidths  Allocate residual width by deterministic weighted water filling.
            %
            % Inputs:
            %   minWidths       Hard lower widths.
            %   preferredWidths Widths at which complete headings/body values fit.
            %   weights         Semantic expansion priorities.
            %   targetWidth     Total available width.
            %   featureColumn   Column receiving residual width after all preferences are met.
            %
            % Outputs:
            %   widths  Assigned widths summing to targetWidth within floating-point tolerance.
            %
            % Errors and diagnostics:
            %   Throws NMResultsViewer:InfeasibleReportTableLayout when minima exceed target.
            %
            % Side effects:
            %   None.
            minWidths=double(minWidths(:)');
            preferredWidths=max(minWidths,double(preferredWidths(:)'));
            weights=max(0,double(weights(:)'));
            targetWidth=double(targetWidth);
            if sum(minWidths)>targetWidth+1e-6
                error('NMResultsViewer:InfeasibleReportTableLayout', ...
                    'Report-table column minima %.2f exceed the available width %.2f.',sum(minWidths),targetWidth);
            end
            widths=minWidths;
            remaining=targetWidth-sum(widths);
            demand=max(0,preferredWidths-widths);
            active=demand>1e-9 & weights>0;
            guard=0;
            while remaining>1e-8 && any(active) && guard<64
                guard=guard+1;
                score=weights.*demand;
                score(~active)=0;
                if sum(score)<=0, break; end
                grant=remaining*score/sum(score);
                grant=min(grant,demand);
                widths=widths+grant;
                used=sum(grant);
                remaining=remaining-used;
                demand=max(0,preferredWidths-widths);
                active=demand>1e-9 & weights>0;
                if used<=1e-10, break; end
            end
            if remaining>0
                widths(featureColumn)=widths(featureColumn)+remaining;
            end
            widths(featureColumn)=widths(featureColumn)+(targetWidth-sum(widths));
        end

        function txt = graphNodeStatisticsFormattedValue(row,descriptor)
            % graphNodeStatisticsFormattedValue  Format one graph-node table value deterministically.
            raw=row.(descriptor.field);
            switch descriptor.type
                case 'text'
                    % nm2-allow: NMResultsViewerFeatureGraphTools node statistics contain conditional missing values and distinct numeric versus text presentation fields
                    txt=char(string(raw));
                case 'integer'
                    % nm2-allow: NMResultsViewerFeatureGraphTools node statistics contain conditional missing values and distinct numeric versus text presentation fields
                    if isnumeric(raw) && ~isempty(raw) && isfinite(double(raw(1)))
                        txt=sprintf('%d',round(double(raw(1))));
                    else
                        txt='--';
                    end
                otherwise
                    % nm2-allow: NMResultsViewerFeatureGraphTools node statistics contain conditional missing values and distinct numeric versus text presentation fields
                    if isnumeric(raw) && ~isempty(raw) && isfinite(double(raw(1)))
                        txt=sprintf('%.3f',double(raw(1)));
                    else
                        txt='--';
                    end
            end
        end

        function width = reportApproxTextWidthPx(txt,fontSize)
            % reportApproxTextWidthPx  Estimate Arial text width deterministically without graphics/toolboxes.
            %
            % The estimator is deliberately conservative and is used only for static report
            % layout. It does not alter scientific values or browser geometry.
            chars=txt;
            if isempty(chars), width=0; return; end
            em=0;
            narrow='ilI.,:;|!''`';
            wide='MW@#%&QG';
            for ii=1:numel(chars)
                ch=chars(ii);
                if isspace(ch)
                    factor=0.28;
                elseif contains(narrow,ch)
                    factor=0.28;
                elseif contains(wide,ch)
                    factor=0.84;
                elseif isstrprop(ch,'digit')
                    factor=0.56;
                elseif isstrprop(ch,'upper')
                    factor=0.64;
                elseif isstrprop(ch,'lower')
                    factor=0.53;
                else
                    factor=0.58;
                end
                em=em+factor;
            end
            width=ceil(double(fontSize)*em+1.5);
        end

        function html = structRowsHtml(rows, fields, labels, maxRows, optionalGroups)
            % structRowsHtml  Render selected struct fields as a compact HTML table.
            %
            % optionalGroups is a cell array of field-name groups. An optional
            % singleton column is shown only when at least one row contains an
            % available value. A paired group such as {'lo95','hi95'} is shown only
            % when at least one row contains the complete pair. Numeric zero is a
            % valid value; NaN, empty text and absent fields are unavailable.
            % nm2-allow: report component writer calls omit optionalGroups in established four-argument rendering paths
            if nargin < 5 || isempty(optionalGroups), optionalGroups = {}; end
            if isempty(rows), html = '<div class="small">No summary rows available.</div>'; return; end
            [fields, labels] = NMResultsViewerReportTools.availableStructTableColumns( ...
                rows, fields, labels, optionalGroups);
            if isempty(fields), html = '<div class="small">No informative summary columns are available.</div>'; return; end
            n = min(numel(rows), maxRows);
            head = cell(1,numel(labels));
            for cc = 1:numel(labels)
                head{cc} = ['<th' NMResultsViewerReportTools.tableCellClassAttr(labels{cc}, []) '>' NMResultsViewerReportTools.htmlEscape(labels{cc}) '</th>'];
            end
            tr = {['<tr>' strjoin(head,'') '</tr>']};
            % MATLAB struct arrays share one field map; resolve optional columns once.
            % nm2-allow: Struct-row tables admit optional columns; field presence is resolved outside the display-cell loop.
            hasColumn = cellfun(@(field)isfield(rows,field),fields);
            for rr = 1:n
                vals = cell(1,numel(fields));
                for cc = 1:numel(fields)
                    if hasColumn(cc)
                        rawValue=rows(rr).(fields{cc});
                    else
                        rawValue='';
                    end
                    vals{cc} = ['<td' NMResultsViewerReportTools.tableCellClassAttr(labels{cc}, rawValue) '>' NMResultsViewerReportTools.htmlEscape(NMResultsViewerReportTools.valuePreview(rawValue)) '</td>'];
                end
                tr{end+1} = ['<tr>' strjoin(vals,'') '</tr>']; %#ok<AGROW>
            end
            more = '';
            if numel(rows) > n, more = sprintf('<div class="small">Showing %d of %d rows.</div>', n, numel(rows)); end
            html = ['<table class="scientificTable">' strjoin(tr,sprintf('\n')) '</table>' more];
        end

        function [fields, labels] = availableStructTableColumns(rows, fields, labels, optionalGroups)
            % availableStructTableColumns  Remove unavailable explicitly optional report columns.
            %
            % Mandatory fields are preserved. Each optional group is removed as a
            % unit unless at least one row contains every member. This keeps error
            % limits paired and prevents empty SE/CI columns in HTML/PDF output.
            if isempty(optionalGroups) || isempty(rows), return; end
            keep = true(1,numel(fields));
            for gg = 1:numel(optionalGroups)
                group = optionalGroups{gg};
                if isempty(group), continue; end
                positions = find(ismember(fields,group));
                if isempty(positions), continue; end
                % nm2-allow: Homogeneous MATLAB struct-array fields allow one availability check per optional column group.
                if ~all(cellfun(@(field)isfield(rows,field),group))
                    keep(positions)=false;
                    continue;
                end
                available = false;
                for rr = 1:numel(rows)
                    rowAvailable = true;
                    for ff = 1:numel(group)
                        rowAvailable = rowAvailable && NMResultsViewerReportTools.structTableValueAvailable(rows(rr).(group{ff}));
                    end
                    if rowAvailable, available = true; break; end
                end
                if ~available, keep(positions) = false; end
            end
            fields = fields(keep);
            labels = labels(keep);
        end

        function tf = structTableValueAvailable(value)
            % structTableValueAvailable  Test one report-table value without treating zero as missing.
            % nm2-allow: writer-conditioned optional table columns may contain heterogeneous numerical, logical and textual presentation values
            if isnumeric(value)
                tf = ~isempty(value) && any(isfinite(double(value(:))));
            % nm2-allow: writer-conditioned optional table columns may contain heterogeneous numerical, logical and textual presentation values
            elseif islogical(value)
                tf = ~isempty(value);
            % nm2-allow: writer-conditioned optional table columns may contain heterogeneous numerical, logical and textual presentation values
            elseif ischar(value) || isstring(value)
                % nm2-allow: writer-conditioned optional table columns may contain heterogeneous numerical, logical and textual presentation values
                tf = ~isempty(strtrim(char(string(value))));
            % nm2-allow: writer-conditioned optional table columns may contain heterogeneous numerical, logical and textual presentation values
            elseif iscell(value)
                tf = ~isempty(value);
            else
                tf = ~isempty(value);
            end
        end

        function attr = tableCellClassAttr(label, rawValue)
            % tableCellClassAttr  Return optional CSS class attribute for compact report table cells.
            cls = NMResultsViewerReportTools.tableCellClass(label, rawValue);
            if isempty(cls)
                attr = '';
            else
                attr = [' class="' cls '"'];
            end
        end

        function cls = tableCellClass(label, rawValue)
            % tableCellClass  Classify report table columns for PDF-aware compact styling.
            % nm2-allow: heterogeneous table values determine display-only CSS classes at export rendering boundary
            labelText = lower(strtrim(label));
            cls = '';
            if ~isempty(strfind(labelText, 'feature')) || strcmp(labelText, 'protein') || strcmp(labelText, 'identifier')
                cls = 'featureName';
                return;
            end
            if strcmp(labelText,'mask source')
                cls = 'wrapText';
                return;
            end
            numericLabels = {'value','se','rank','abs. rank','signed rank','mean weight','cv ratio','selection probability','sbc z','sbc -log10(p)','sbc -log10(q)','x value','y value','n','min','q1','median','q3','max','mean','sd'};
            % nm2-allow: heterogeneous table values determine display-only CSS classes at export rendering boundary
            if isnumeric(rawValue) || islogical(rawValue) || any(strcmp(labelText, numericLabels)) || ~isempty(strfind(labelText, 'log10')) || ~isempty(strfind(labelText, 'ratio'))
                cls = 'numeric';
            end
        end

        function arrText = rowTextArray(rows, fieldName)
            % rowTextArray  Extract a struct field from rows as a cellstr vector.
            arrText = cell(1,numel(rows));
            for ii = 1:numel(rows)
                arrText{ii} = rows(ii).(fieldName);
            end
        end

        function vals = rowNumberArray(rows, fieldName)
            % rowNumberArray  Extract a numeric struct field from rows.
            vals = NaN(1,numel(rows));
            for ii = 1:numel(rows), vals(ii) = NMResultsViewerReportTools.rowNumber(rows(ii), fieldName); end
        end

        function vals = structNumericArray(rows, fieldName)
            % structNumericArray  Extract a numeric scalar field from a struct row array.
            vals = NaN(numel(rows),1);
            if isempty(rows) || isempty(fieldName), return; end
            for ii = 1:numel(rows)
                % nm2-allow: NMResultsViewerTools Feature Inspection rows have writer-conditioned optional numeric metric columns
                if isfield(rows(ii), fieldName) && isnumeric(rows(ii).(fieldName)) && ~isempty(rows(ii).(fieldName))
                    tmp = rows(ii).(fieldName);
                    vals(ii) = double(tmp(1));
                end
            end
        end

        function labels = uniqueRowText(rows, fieldName)
            % uniqueRowText  Return stable unique text values from a row field.
            if isempty(rows), labels = {}; return; end
            labels = unique(NMResultsViewerReportTools.rowTextArray(rows, fieldName), 'stable');
        end

        function x = rowNumber(row, fieldName)
            % rowNumber  Read one numeric scalar from a struct row.
            x = NaN;
            v = row.(fieldName);
            % nm2-allow: metric and association display rows may contain unavailable numeric values at report representation boundary
            if isnumeric(v) && ~isempty(v), x = double(v(1)); end
        end

        function lines = reportSummaryTextLines(report, exportSpec)
            % reportSummaryTextLines  Build a concise scientific text report for PDF.
            comps = report.Components;
            lines = {NMResultsViewerReportTools.safeAscii(report.Title); ...
                ['Generated: ' datestr(now)]; ...
                'Mode: summary'; ...
                sprintf('Components selected: %d', numel(comps)); ''};
            metricValues = NMResultsViewerReportTools.componentTableById(comps, 'model_optimization.selected_metric', 'metricValues');
            if isempty(metricValues), metricValues = NMResultsViewerReportTools.componentTableById(comps, 'model_optimization.metric_dashboard', 'metricValues'); end
            if ~isempty(metricValues)
                lines{end+1} = 'Selected optimization metric - best rows:'; %#ok<AGROW>
                bestRows = NMResultsViewerReportTools.bestMetricRows(metricValues);
                for ii = 1:numel(bestRows)
                    lines{end+1} = sprintf('  %s: model %g, value %.6g, %s', ...
                        NMResultsViewerReportTools.safeAscii(bestRows(ii).seriesLabel), bestRows(ii).modelIndex, bestRows(ii).value, ...
                        NMResultsViewerReportTools.safeAscii(bestRows(ii).parameterValues)); %#ok<AGROW>
                end
                lines{end+1} = ''; %#ok<AGROW>
            end
            registry = NMResultsViewerReportTools.componentTableById(comps, 'model_optimization.metric_registry', 'metricRegistry');
            if isempty(registry), registry = NMResultsViewerReportTools.componentTableById(comps, 'model_optimization.metric_dashboard', 'metricRegistry'); end
            if ~isempty(registry)
                lines{end+1} = 'Optimization metric summary:'; %#ok<AGROW>
                n = min(numel(registry), exportSpec.MaxSummaryRows);
                for ii = 1:n
                    lines{end+1} = sprintf('  %s / %s: n=%g, min=%.6g, max=%.6g, mean=%.6g', ...
                        NMResultsViewerReportTools.safeAscii(registry(ii).metricLabel), ...
                        NMResultsViewerReportTools.safeAscii(registry(ii).seriesLabel), ...
                        NMResultsViewerReportTools.rowNumber(registry(ii),'nFinite'), NMResultsViewerReportTools.rowNumber(registry(ii),'min'), ...
                        NMResultsViewerReportTools.rowNumber(registry(ii),'max'), NMResultsViewerReportTools.rowNumber(registry(ii),'mean')); %#ok<AGROW>
                end
                lines{end+1} = ''; %#ok<AGROW>
            end
            assoc = NMResultsViewerReportTools.componentTableById(comps, 'model_optimization.scatter_comparison', 'associations');
            if ~isempty(assoc)
                lines{end+1} = 'Scatter/Pareto diagnostic notes:'; %#ok<AGROW>
                for ii = 1:min(numel(assoc), exportSpec.MaxSummaryRows)
                    warning = assoc(ii).lowDynamicRangeWarning;
                    lines{end+1} = sprintf('  %s: r=%.6g, p=%.6g%s', ...
                        NMResultsViewerReportTools.safeAscii(assoc(ii).seriesLabel), ...
                        NMResultsViewerReportTools.rowNumber(assoc(ii),'pearsonR'), NMResultsViewerReportTools.rowNumber(assoc(ii),'pValue'), ...
                        NMResultsViewerReportTools.safeAscii([' ' warning])); %#ok<AGROW>
                end
                lines{end+1} = ''; %#ok<AGROW>
            end
            lines{end+1} = 'Large metric, partition, surface and scatter tables are omitted from summary PDF.';
            lines{end+1} = 'Use HTML summary for compact static visuals, or ReportMode="technical" / CSV/XLSX/MAT for exhaustive payload tables.';
        end

        function label = reportComponentProgressLabel(componentSpec, idx)
            % reportComponentProgressLabel  Return a compact user-facing label for progress reporting.
            %
            % The Report Builder progress viewer should describe the actual component being rendered without exposing raw component ids unless no better label is available.
            label = componentSpec.Title;
            if isempty(strtrim(label))
                label = strrep(componentSpec.Id,'_',' ');
            end
            if isempty(strtrim(label))
                label = sprintf('component %d',idx);
            end
        end

        function reportProgress(title, message, percent, phase)
            % reportProgress  Publish deterministic Report Builder progress when a browser progress context is active.
            %
            % This helper keeps report-generation progress advisory and browser-specific. It does not mutate NM results and it avoids a dependency on the shared progress class when the report API is called from a plain MATLAB session.
            % nm2-allow: optional NMRuntimeProgressTools service is an external runtime resource boundary
            if exist('NMRuntimeProgressTools','class') == 8 || exist('NMRuntimeProgressTools','file') == 2
                NMRuntimeProgressTools.writeGenericProgressSafe(title, message, percent, phase);
                NMResultsViewerReportTools.yieldReportProgressPoller();
            end
        end

        function yieldReportProgressPoller()
            % yieldReportProgressPoller  Briefly yield after browser progress writes.
            %
            % The file-backed progress viewer is polled by the browser bridge while MATLAB
            % renders report components. Without a small yield, a fast component loop can
            % write many progress states before the bridge/browser has a chance to read
            % them, causing the viewer to remain at the initial percentage and jump to the
            % final state. This helper is Report Builder-specific and does not affect
            % DataIO or runtime-runner progress contracts.
            try
                drawnow('limitrate');
            catch
                try, drawnow; catch, end %#ok<CTCH>
            end
            try
                pause(0.02);
            catch
            end
        end


    end
end

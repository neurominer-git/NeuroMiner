classdef NMResultsViewerCrossAnalysisTools
% NMResultsViewerCrossAnalysisTools
% -------------------------------------------------------------------------
% Cross-analysis orchestration for the NM2 Results Viewer.
%
% Purpose
%   Expose cross-analysis catalogues, performance tables, inferential statistical
%   comparison and descriptive aggregate-performance visual comparison without
%   creating a second interpreter of NM analysis/result structures. This class consumes
%   the existing Results Viewer selector/materialization authorities and the
%   Scientific Annotation / Scientific State contracts.
%
% Syntax
%   payload = NMResultsViewerCrossAnalysisTools.workspacePayload(NM,spec)
%   tablePayload = NMResultsViewerCrossAnalysisTools.performanceTable(NM,spec)
%   statPayload = NMResultsViewerCrossAnalysisTools.statisticalComparison(NM,spec)
%   visualPayload = NMResultsViewerCrossAnalysisTools.visualComparison(NM,spec)
%
% Inputs
%   NM   Read-only NeuroMiner workspace supplied by the owning Results Viewer
%        service boundary.
%   spec Optional request struct carrying analysis-set identity plus the explicit
%        Performance/Statistical/Visual scientific and presentation selectors.
%
% Outputs
%   workspacePayload returns the completed-analysis catalogue, common CV/OOCV
%   source options and current selection. The three analysis-set consumers return
%   canonical performance-table, statistical-comparison or visual-comparison
%   artefacts plus the Scientific Annotation/Directory/State provenance needed by
%   the browser and the single adaptive Report Builder.
%
% Authority and flow
%   NM -> NMResultsViewerTools selector/materialization authorities
%      -> scientificAnnotation on each materialized Model Performance/Optimization payload
%      -> Scientific Directory + Scientific State
%      -> cross-analysis table/statistical/visual/report consumers.
%
% Scientific/state contract
%   This class never discovers scientific facts by traversing NM.analysis,
%   GDdims, OOCV containers, params, or labels. Analysis completion, targets,
%   model sources, classifiers, application sources and performance payloads are
%   requested from their existing authorities. Cross-analysis state is therefore
%   orchestration state, not a competing scientific authority.
%
% Invariants
%   * The Cross-analysis result type is available only when at least two
%     completed analyses exist, but the Performance table may tabulate any
%     non-empty subset of those analyses.
%   * One shared CV/OOCV source is selectable only when that source is enabled
%     for every selected analysis.
%   * Performance values come from the existing model-performance payload
%     performanceTabulationRows projection; no metric definition is reimplemented
%     here. True multi-class class-vs-REST rows are obtained by materializing the same
%     multiClassModeIndex contexts used by the Model Performance workspace.
%   * Each tabulated scientific context retains its canonical annotation.
%   * Statistical comparison alone requires the nk_GetAnalysisStatus-backed CV
%     equivalence group and matched CV2 matrices. Visual comparison is descriptive:
%     it projects the inherited aggregate classification catalogue from Model
%     Performance source=cv without any CV-equivalence gate or inferential test.
%
% Materialization and performance
%   workspacePayload performs only catalogue/selector queries and does not load
%   feature-scale arrays. The analysis-set consumers materialize only their existing
%   compact Model Performance or Model Optimization payloads at explicit Generate/
%   Report boundaries; performanceTable materializes one compact model-performance
%   payload per enabled analysis x target x model-source x classifier context. It performs no voxel/vertex scans, imaging reads, atlas
%   loading or feature-scale allocation. Cost scales with requested compact
%   performance contexts, not imaging dimensionality.
%
% Failure semantics
%   Invalid or empty selections fail explicitly. Individual scientifically
%   unavailable contexts are retained as warnings while valid contexts continue
%   to tabulate; a request with no valid context returns ok=false.
%
% Side effects
%   None. NM is not mutated and no file is written.
%
% Consumers and dependencies
%   NMResultsViewerTools, NMResultsViewerScientificAnnotation,
%   NMResultsViewerScientificDirectory, NMResultsViewerScientificState,
%   NMResultsViewerUI and NMResultsViewerReportTools.
% -------------------------------------------------------------------------

    methods (Static)
        function payload = workspacePayload(NM,spec)
            % Purpose: Build the Cross-analysis workspace catalogue without materializing performance values.
            % Syntax: payload = NMResultsViewerCrossAnalysisTools.workspacePayload(NM,spec)
            % Inputs: NM is read-only; spec optionally supplies analysisIndices and requested cross-analysis source.
            % Outputs: JSON-safe comparison workspace payload with completed analyses, per-analysis/common source options, selected source, empty table/scientific materialization fields and status message.
            % Authority and flow: Consumes NMResultsViewerTools.listAnalyses/sourcesForAnalysis through shared selector authorities; it does not traverse NM.analysis/result containers directly.
            % Scientific/state contract: Workspace availability requires at least two completed analyses. Before table generation, Scientific Directory/State are valid empty materialization views and no annotation is claimed.
            % Invariants: Selected analyses are a subset of completed analysis ids; common source options are enabled for every selected analysis.
            % Materialization and performance: O(A*S) compact catalogue work for A analyses and small source catalogues; no model-performance payloads, files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays. Safe on result-type switching/refresh.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Fewer than two completed analyses returns ok=false with an explanatory message; invalid requested indices are filtered by selectedAnalysisIndices.
            % Side effects: None; NM is not mutated.
            % Consumers and dependencies: NMResultsViewerTools.getPayload/buildInitialState, NMResultsViewerUI and NMResultsViewerCrossAnalysis.js.
            % nm2-allow: public Cross-analysis workspace boundary supports an omitted request spec.
            if nargin < 2 || isempty(spec), spec=struct(); end
            analyses=NMResultsViewerTools.listAnalyses(NM);
            completed=analyses([analyses.completed]);
            completedIndices=[completed.index];
            selected=NMResultsViewerCrossAnalysisTools.selectedAnalysisIndices(completedIndices,spec);
            if isempty(selected), selected=completedIndices; end
            analysisSourceOptions=NMResultsViewerCrossAnalysisTools.sourceOptionsByAnalysis(NM,completedIndices,analyses);
            sourceOptions=NMResultsViewerCrossAnalysisTools.commonSourceOptionsFromCatalogue(analysisSourceOptions,selected);
            selectedSource=NMResultsViewerCrossAnalysisTools.selectedSource(sourceOptions,spec);
            payload=struct( ...
                'ok',numel(completedIndices)>=2, ...
                'kind','comparison', ...
                'contractVersion','NM-CROSS-ANALYSIS-V1', ...
                'analysisCount',double(numel(completedIndices)), ...
                'analyses',completed, ...
                'selectedAnalysisIndices',double(selected(:)'), ...
                'analysisSourceOptions',analysisSourceOptions, ...
                'sourceOptions',sourceOptions, ...
                'selectedSource',selectedSource, ...
                'metricOptions',repmat(struct('id','','label','','enabled',true),1,0), ...
                'rows',repmat(NMResultsViewerCrossAnalysisTools.rowTemplate(),1,0), ...
                'tableCells',{{}}, ...
                'scientificAnnotations',repmat(NMResultsViewerScientificAnnotation.template(),1,0), ...
                'scientificDirectory',NMResultsViewerScientificDirectory.build([]), ...
                'scientificState',NMResultsViewerScientificState.clientView(NMResultsViewerScientificState.fromPayloads({},spec)), ...
                'warnings',{{}}, ...
                'message','');
            if payload.ok
                payload.message=sprintf('Cross-analysis workspace is available for %d completed analyses.',numel(completedIndices));
            else
                payload.message='Cross-analysis requires at least two completed analyses.';
            end
        end

        function out = synthOverview(NM,experimentIndex,varargin)
            % Read-only projection of the end-of-run persisted summary.
            % Analysis indices are resolved by stable child ID after rebasing.
            parent=NM.SYNTH.analysis{experimentIndex};
            summary=parent.performanceSummary;
            assert(~isempty(summary),'NMResultsViewerCrossAnalysisTools:SynthSummaryAbsent', ...
                'SYNTH has no completion-only performance summary. Complete or resume its execution to produce one.');
            rows=summary.rows;
            ids=cellfun(@(a)a.id,NM.analysis,'UniformOutput',false);
            for ii=1:numel(rows)
                matches=find(strcmp(ids,rows(ii).analysisId));
                assert(isscalar(matches),'NMResultsViewerCrossAnalysisTools:SynthStaleChild', ...
                    'SYNTH summary child %s cannot be resolved uniquely.',rows(ii).analysisId);
                assert(ismember(matches,parent.analysisIndices), ...
                    'NMResultsViewerCrossAnalysisTools:SynthStaleMembership', ...
                    'SYNTH summary child %s is not an active member of its experiment.',rows(ii).analysisId);
                rows(ii).analysisIndex=matches;
            end
            % The parent owns all numerical aggregation; this read path only
            % selects persisted mean/SD coordinates for the default criterion.
            context=summary.contexts(1);metricId=summary.criterion.metricId;
            if ~isempty(varargin)
                selection=varargin{1};
                match=find([summary.contexts.targetNativeIndex]==selection.targetNativeIndex & ...
                    [summary.contexts.classifierIndex]==selection.classifierIndex & ...
                    [summary.contexts.multiClassModeIndex]==selection.multiClassModeIndex & ...
                    strcmp({summary.contexts.modelSource},selection.modelSource));
                assert(isscalar(match),'NMResultsViewerCrossAnalysisTools:SynthContextUnavailable', ...
                    'The selected SYNTH target/classifier/contrast context is not persisted.');
                context=summary.contexts(match);metricId=selection.metricId;
            end
            hit=find(strcmp(context.metricIds,metricId));
            assert(isscalar(hit),'NMResultsViewerCrossAnalysisTools:SynthCriterionUnavailable', ...
                'Persisted summary does not expose the optimization criterion.');
            sizes=summary.sampleSizes;
            values=context.mean(:,hit);lower=values-context.sd(:,hit);upper=values+context.sd(:,hit);
            lower(context.count(:,hit)<=5)=NaN;upper(context.count(:,hit)<=5)=NaN;
            if strcmp(metricId,summary.criterion.metricId)
                yLabel=summary.criterion.label;
            else
                yLabel=context.metricLabels{hit};
            end
            labels=arrayfun(@(v)sprintf('N=%d',v),sizes,'UniformOutput',false);
            colorRows=NMResultsViewerCrossAnalysisTools.visualMetricColors({'Mean'},struct());
            if numel(sizes)==1,xPositions=0.5;
            else,xPositions=(sizes-min(sizes))/(max(sizes)-min(sizes));end
            xLabel='Cumulative cohort size (N)';
            if strcmp(parent.mode,'fully_synthetic'),xLabel='Sample size (N)';end
            plotPayload=struct('type','aggregate_performance','values',values, ...
                'displayLabels',{labels},'metricLabels',{{'Mean'}},'metricIds',{{'Mean'}}, ...
                'sortAnalyses',false,'plotMode','line','separateAxisMetricIds',{{}}, ...
                'metricColors',colorRows,'xLabel',xLabel, ...
                'yLabel',yLabel,'xPositions',xPositions, ...
                'bandLower',lower,'bandUpper',upper);
            material=NMResultsViewerScientificAnnotation.synthMaterialTemplate();
            material.experimentIndex=experimentIndex;material.experimentId=parent.id;
            material.mode=parent.mode;
            if strcmp(parent.mode,'fully_synthetic')
                % Pre-data experiments have no observed source or subject count.
                material.sourceAnalysisIndex=0;material.observedN=0;
            else
                material.sourceAnalysisIndex=parent.sourceAnalysisIndex;
                material.observedN=parent.observedN;
            end
            material.analysisIndices=parent.analysisIndices;
            material.status=parent.status;material.configuration=parent.configuration;
            annotation=NMResultsViewerScientificAnnotation.fromSynthExperiment(material);
            out=struct('ok',true,'experimentId',parent.id, ...
                'experimentIndex',experimentIndex,'mode',parent.mode, ...
                'observedN',material.observedN, ...
                'status',parent.status,'criterion',summary.criterion,'rows',rows, ...
                'contexts',summary.contexts,'selectedMetricId',metricId, ...
                'plotPayload',plotPayload,'scientificAnnotation',annotation);
            if strcmp(parent.mode,'fully_synthetic')
                out.parameterNames=summary.parameterNames;
                out.parameterRows=summary.parameterRows;
            end
        end

        function out = performanceTable(NM,spec)
            % Purpose: Materialize the normalized cross-analysis performance table from existing Model Performance authorities.
            % Syntax: out = NMResultsViewerCrossAnalysisTools.performanceTable(NM,spec)
            % Inputs: NM is read-only; spec supplies selected analysisIndices, common CV/OOCV source, optional aliases and metricIds; subgroupExpression must be empty until an authoritative subgroup recomputation contract exists.
            % Outputs: Long-form/allRows, selected metric rows, pivot tableCells, metric options, warnings, materialized Scientific Annotations, Scientific Directory and multi-context Scientific State.
            % Authority and flow: For each selected analysis, resultTypesForAnalysis/defaultPerformanceResultType supplies canonical Model Performance identity; target/model-source/classifier payloads then come from NMResultsViewerTools. Multiclass class-vs-REST contexts are materialized through NMResultsViewerTools.multiClassModeOptions/getPayload; metric values come only from payload.performanceTabulationRows.
            % Scientific/state contract: Every retained context contributes its canonical Scientific Annotation; aggregate multiclass browser summary is not substituted for inherited class-vs-REST tabulation. Scientific State/Directory are built from the same materialized payload set used for rows.
            % Invariants: One common source must be enabled for all selected analyses; no metric formula, target/class identity, or model-source identity is rediscovered here; invalid subgroup requests are rejected.
            % Materialization and performance: Cost scales with compact requested performance contexts A×T×M×C×Q and returned metric rows. No voxel/vertex scans, imaging reads, XML parsing, atlas/annotation/mesh loads, directory scans or feature-scale allocations are introduced.
            % Resource declaration: Directly reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; it delegates only to established compact Model Performance materialization and builds metric-scale tables. Safe for explicit Generate/Report Builder actions, not intended as a high-frequency retained interaction.
            % Failure semantics: Empty selection/unavailable common source/subgroup request fails explicitly. Individual unavailable contexts become warnings; if none materialize, out.ok=false.
            % Side effects: None; NM is not mutated and no export file is written.
            % Consumers and dependencies: Browser Cross-analysis workspace and NMResultsViewerReportTools.
            % nm2-allow: public Cross-analysis performance-table boundary supports an omitted request spec.
            if nargin < 2 || isempty(spec), spec=struct(); end
            ws=NMResultsViewerCrossAnalysisTools.workspacePayload(NM,spec);
            if ~ws.ok
                out=ws;
                out.message='Performance table requires a NeuroMiner workspace with at least two completed analyses.';
                return;
            end
            selected=NMResultsViewerCrossAnalysisTools.selectedAnalysisIndices([ws.analyses.index],spec);
            if isempty(selected)
                error('NMResultsViewerCrossAnalysisTools:NoAnalysisSelection', ...
                    'Select at least one completed analysis for the cross-analysis performance table.');
            end
            sourceOptions=NMResultsViewerCrossAnalysisTools.commonSourceOptions(NM,selected,ws.analyses);
            source=NMResultsViewerCrossAnalysisTools.selectedSource(sourceOptions,spec);
            requested=NMResultsViewerCrossAnalysisTools.specText(spec,{'crossAnalysisSource','source'},source);
            if ~strcmp(source,requested)
                error('NMResultsViewerCrossAnalysisTools:UnavailableCommonSource', ...
                    'Source %s is not enabled for every selected analysis.',requested);
            end

            aliases=NMResultsViewerCrossAnalysisTools.analysisAliasMap(spec,ws.analyses);
            subgroupExpression=strtrim(NMResultsViewerCrossAnalysisTools.specText(spec,{'subgroupExpression'},''));
            if ~isempty(subgroupExpression)
                error('NMResultsViewerCrossAnalysisTools:NoSubgroupMetricAuthority', ...
                    ['Subgroup-specific cross-analysis performance tabulation is not exposed because ', ...
                     'the current normalized performance payload does not provide an authoritative ', ...
                     'subgroup metric recomputation contract.']);
            end
            rows=repmat(NMResultsViewerCrossAnalysisTools.rowTemplate(),1,0);
            payloads={}; records=repmat(struct('reference','','scientificAnnotation',NMResultsViewerScientificAnnotation.template()),1,0);
            warnings={}; materializedCount=0;

            for aa=1:numel(selected)
                analysisIndex=selected(aa);
                analysisRow=NMResultsViewerCrossAnalysisTools.analysisRow(ws.analyses,analysisIndex);
                if isempty(analysisRow), continue; end
                resultTypes=NMResultsViewerTools.resultTypesForAnalysis(NM,analysisIndex,struct('analysisIndex',analysisIndex),ws.analyses);
                resultType=NMResultsViewerTools.defaultPerformanceResultType(NM,analysisIndex,resultTypes);
                targets=NMResultsViewerTools.targetOptions(NM,analysisIndex);
                targets=targets([targets.enabled]);
                if isempty(targets)
                    warnings{end+1}=sprintf('Analysis %d has no enabled analyzed target.',analysisIndex); %#ok<AGROW>
                    continue;
                end
                baseSpec=struct('analysisIndex',analysisIndex,'resultType',resultType,'source',source, ...
                    'graphType',1,'subgroupExpression',subgroupExpression);
                modelSources=NMResultsViewerTools.modelSourcesForAnalysis(NM,analysisIndex,resultType,baseSpec);
                modelSources=modelSources([modelSources.enabled]);
                if isempty(modelSources)
                    modelSources=struct('id','','label','Primary model source','enabled',true,'reason','','kind','primary','index',NaN);
                end
                for tt=1:numel(targets)
                    targetDisplay=targets(tt).name;
                    if numel(targets)>1,targetDisplay=targets(tt).label;end
                    for mm=1:numel(modelSources)
                        contextSpec=baseSpec;
                        contextSpec.targetNativeIndex=double(targets(tt).index);
                        contextSpec.targetIndex=double(targets(tt).resultIndex);
                        if ~isempty(modelSources(mm).id), contextSpec.modelSource=modelSources(mm).id; end
                        classifiers=NMResultsViewerTools.classifierOptions(NM,analysisIndex,resultType,contextSpec);
                        classifiers=classifiers([classifiers.enabled]);
                        if isempty(classifiers)
                            warnings{end+1}=sprintf('Analysis %d target %s model source %s exposes no enabled model.', ...
                                analysisIndex,targets(tt).label,modelSources(mm).label); %#ok<AGROW>
                            continue;
                        end
                        for cc=1:numel(classifiers)
                            request=contextSpec;
                            request.classifierIndex=double(classifiers(cc).index);
                            payload=NMResultsViewerTools.getPayload(NM,request);
                            if ~payload.ok
                                warnings{end+1}=sprintf('Analysis %d / %s / %s / %s was unavailable: %s', ...
                                    analysisIndex,targets(tt).label,modelSources(mm).label,classifiers(cc).label,payload.message); %#ok<AGROW>
                                continue;
                            end

                            % True multi-class performance has two established NM2
                            % presentation families: the aggregate multi-group view
                            % (multiClassModeIndex==1) and one class-vs-REST view per
                            % group. The inherited Performance Tabulator exports the
                            % binary decomposition rows plus the per-class MultiClass
                            % contingency rows, not the aggregate browser summary.
                            % Reuse the exact Model Performance selector authority
                            % rather than reopening MultiClass.class here.
                            if strcmp(payload.kind,'multiclass')
                                modes=NMResultsViewerTools.multiClassModeOptions(NM,analysisIndex,request);
                                modes=modes([modes.enabled] & [modes.index]>1);
                                if isempty(modes)
                                    warnings{end+1}=sprintf('Analysis %d / %s / %s exposes a multi-group classifier but no enabled class-vs-REST Model Performance modes.', ...
                                        analysisIndex,targets(tt).label,modelSources(mm).label); %#ok<AGROW>
                                    continue;
                                end
                                for qq=1:numel(modes)
                                    modeRequest=request;
                                    modeRequest.resultType='multiclass';
                                    modeRequest.multiClassModeIndex=double(modes(qq).index);
                                    modePayload=NMResultsViewerTools.getPayload(NM,modeRequest);
                                    if ~modePayload.ok
                                        warnings{end+1}=sprintf('Analysis %d / %s / %s / %s was unavailable: %s', ...
                                            analysisIndex,targets(tt).label,modelSources(mm).label,modes(qq).label,modePayload.message); %#ok<AGROW>
                                        continue;
                                    end
                                    [payloads,records,rows,materializedCount]=NMResultsViewerCrossAnalysisTools.appendPerformancePayload( ...
                                        payloads,records,rows,materializedCount,modePayload,analysisIndex,analysisRow.title, ...
                                        aliases{analysisIndex},'multiclass',source,targetDisplay,modelSources(mm).label, ...
                                        sprintf('Multi-group: %s',modes(qq).label));
                                end
                                continue;
                            end

                            [payloads,records,rows,materializedCount]=NMResultsViewerCrossAnalysisTools.appendPerformancePayload( ...
                                payloads,records,rows,materializedCount,payload,analysisIndex,analysisRow.title, ...
                                aliases{analysisIndex},resultType,source,targetDisplay,modelSources(mm).label, ...
                                classifiers(cc).label);
                        end
                    end
                end
            end

            metricOptions=NMResultsViewerCrossAnalysisTools.metricOptions(rows);
            selectedMetricIds=NMResultsViewerCrossAnalysisTools.selectedMetricIds(metricOptions,spec);
            filteredRows=NMResultsViewerCrossAnalysisTools.filterMetricRows(rows,selectedMetricIds);
            tableCells=NMResultsViewerCrossAnalysisTools.pivotTable(filteredRows,metricOptions,selectedMetricIds);
            directory=NMResultsViewerScientificDirectory.build(records);
            scientificState=NMResultsViewerScientificState.clientView(NMResultsViewerScientificState.fromPayloads(payloads,spec));
            scientificState.scope=struct('type','analysis_set','analysisIndices',double(selected(:)'), ...
                'identity',sprintf('analysis_set:%s',strjoin(arrayfun(@num2str,selected,'UniformOutput',false),',')));
            scientificState.directory=directory;
            scientificState.derivedArtefacts=struct('id','cross_analysis.performance_table','scope','analysis_set', ...
                'analysisIndices',double(selected(:)'),'source',source,'materialized',true);
            annotations=repmat(NMResultsViewerScientificAnnotation.template(),1,numel(records));
            for ii=1:numel(records),annotations(ii)=records(ii).scientificAnnotation;end

            out=ws;
            out.ok=~isempty(rows);
            out.selectedAnalysisIndices=double(selected(:)');
            out.sourceOptions=sourceOptions;
            out.selectedSource=source;
            out.metricOptions=metricOptions;
            out.selectedMetricIds=selectedMetricIds;
            out.rows=filteredRows;
            out.allRows=rows;
            out.tableCells=tableCells;
            out.scientificAnnotations=annotations;
            out.scientificDirectory=directory;
            out.scientificState=scientificState;
            out.warnings=warnings;
            out.materializedContextCount=double(materializedCount);
            if out.ok
                out.message=sprintf('Performance table materialized %d scientific context(s) across %d selected analysis/analyses.',materializedCount,numel(selected));
            else
                out.message='No selected cross-analysis context exposed an available model-performance payload.';
            end
        end


        function out = statisticalComparison(NM,spec,analysisSetState)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Materialize one authoritative matched-CV2 cross-analysis statistical-comparison artefact.
            % Syntax: out = NMResultsViewerCrossAnalysisTools.statisticalComparison(NM,spec[,analysisSetState])
            % Inputs: NM is read-only; spec supplies analysisIndices plus optional targetIndex, modelSource, classifierIndex and referenceAnalysisIndex/referenceAnalysisIndices; analysisSetState is the resident queried analysis_set Scientific State when the UI/session already owns it.
            % Outputs: cross_analysis.statistical_comparison payload containing the selected scientific coordinates, canonical matched CV2 criterion matrix, inferential result, numerical report tables, backend-derived plot summaries and Scientific Annotation/Directory/State provenance.
            % Authority and flow: analysis_set equivalence comes only from NMResultsViewerScientificState, whose CV groups come from nk_GetAnalysisStatus and whose criterion identity comes from NMResultsViewerTools.modelOptimizationCriterionIdentity; each admitted analysis is then materialized once through NMResultsViewerTools.getModelOptimizationPayload; inference dispatches only to wilcoxon/quadetest and plot deltas to nk_ComputeMnMdPairWiseDiff.
            % Scientific/state contract: Exactly two analyses use paired Wilcoxon. More than two use Quade without a reference and reference-vs-other paired Wilcoxon with exactly one reference. Multiple references are invalid. Scientific State CV-equivalence and exact shared optimization-criterion identity define admission before matched CV2 materialization; target, model-source, model-result and fusion identity are comparison attributes rather than equality constraints.
            % Invariants: No raw NM.analysis/GDdims/CV/TrainInd/result-container traversal occurs here; the matched matrix is built exclusively from model_optimization.partitions.cv2.matrix, and every inferential/plot/report projection derives from that one matrix/result.
            % Materialization and performance: Explicit Generate/Report action only. It performs A compact Model Optimization materializations, one O(B*A) matched-matrix allocation for B CV2 cells and A analyses, and O(B*A^2) pairwise-delta work for Quade; no imaging files/XML/atlas/annotation/mesh resources, voxel/vertex scans or feature-scale arrays are touched.
            % Resource declaration: Reads no files directly, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; it consumes compact resident Model Optimization payloads and statistical vectors only. Not intended for high-frequency retained interaction.
            % Failure semantics: Fewer than two selected analyses, stale/mismatched analysis_set state, >1 reference, CV-incompatible groups, unavailable optimization payloads, incompatible optimization criteria, unequal CV2 matrix shapes or non-finite CV2 values fail explicitly; no substitute statistic or row dropping is used.
            % Side effects: None; NM and analysisSetState are not mutated and no files are written.
            % Consumers and dependencies: NMResultsViewerUI statistical service operation, Cross-analysis browser, NMResultsViewerReportTools; depends on Scientific State, Model Optimization payload authority, wilcoxon, quadetest, fdr_bh, nm_95confint and nk_ComputeMnMdPairWiseDiff.
            % nm2-allow: public Cross-analysis statistical boundary supports an omitted request spec.
            % nm2-allow: public Cross-analysis visual boundary supports an omitted request spec.
            if nargin<2||isempty(spec),spec=struct();end
            ws=NMResultsViewerCrossAnalysisTools.workspacePayload(NM,spec);
            selected=NMResultsViewerCrossAnalysisTools.selectedAnalysisIndices([ws.analyses.index],spec);
            if numel(selected)<2
                error('NMResultsViewerCrossAnalysisTools:StatisticalSelection','Statistical comparison requires at least two completed analyses.');
            end
            % nm2-allow: public statistical boundary accepts an omitted resident analysis-set state and materializes the canonical state once.
            if nargin<3||isempty(analysisSetState)
                analysisSetState=NMResultsViewerScientificState.forAnalysisSet(NM,selected,spec);
            end
            NMResultsViewerCrossAnalysisTools.validateAnalysisSetState(analysisSetState,selected,'Statistical comparison');
            inventory=analysisSetState.inventory;
            % nm2-allow: analysis-set inventory cardinality and CV-group equality are scientific compatibility validations on the canonical state.
            if numel(inventory)~=numel(selected)||numel(unique(double([inventory.cvGroup])))~=1
                error('NMResultsViewerCrossAnalysisTools:CVIncompatible','Selected analyses are CV-incompatible according to the nk_GetAnalysisStatus-backed Scientific State inventory.');
            end
            if any(~arrayfun(@(x)logical(x.capabilities.modelOptimization),inventory))
                error('NMResultsViewerCrossAnalysisTools:OptimizationUnavailable','Every selected analysis must expose Model Optimization capability for statistical comparison.');
            end
            criterionKeys={inventory.optimizationCriterion};
            criterionKeys=cellfun(@(x)x.key,criterionKeys,'UniformOutput',false);
            if any(cellfun(@isempty,criterionKeys))
                error('NMResultsViewerCrossAnalysisTools:MissingCriterion','Statistical comparison requires explicit optimization-criterion identity in the queried Scientific State inventory.');
            end
            if numel(unique(criterionKeys))~=1
                error('NMResultsViewerCrossAnalysisTools:CriterionMismatch','Only analyses sharing the same optimization criterion are eligible for statistical comparison.');
            end
            criterionIdentity=inventory(1).optimizationCriterion;

            references=[];
            % nm2-allow: public statistical request boundary accepts the documented plural reference selector.
            if isfield(spec,'referenceAnalysisIndices')&&~isempty(spec.referenceAnalysisIndices),references=double(spec.referenceAnalysisIndices(:)');end
            % nm2-allow: public statistical request boundary accepts the documented scalar reference selector.
            if isfield(spec,'referenceAnalysisIndex')&&~isempty(spec.referenceAnalysisIndex)
                scalarReference=double(spec.referenceAnalysisIndex(1));
                if isfinite(scalarReference)&&scalarReference>0,references=[references scalarReference];end %#ok<AGROW>
            end
            references=unique(references,'stable');
            if numel(references)>1
                error('NMResultsViewerCrossAnalysisTools:MultipleReferences','Statistical comparison permits at most one reference analysis.');
            end
            if ~isempty(references)&&~ismember(references,selected)
                error('NMResultsViewerCrossAnalysisTools:InvalidReference','The reference analysis must belong to the selected analysis set.');
            end

            firstIndex=selected(1);
            targets=NMResultsViewerTools.targetOptions(NM,firstIndex); targets=targets([targets.enabled]);
            if isempty(targets),error('NMResultsViewerCrossAnalysisTools:NoTarget','The selected analyses expose no Model Optimization target context.');end
            targetIndex=NMResultsViewerCrossAnalysisTools.specNumeric(spec,{'targetIndex'},double(targets(1).resultIndex));
            targetHit=find([targets.resultIndex]==targetIndex,1);
            if isempty(targetHit),error('NMResultsViewerCrossAnalysisTools:InvalidTarget','The requested target is unavailable in the first selected analysis.');end

            baseSpec=struct('resultType','model_optimization','analysisIndex',firstIndex,'targetIndex',targetIndex);
            firstSources=NMResultsViewerTools.modelSourcesForAnalysis(NM,firstIndex,'model_optimization',baseSpec); firstSources=firstSources([firstSources.enabled]);
            if isempty(firstSources),error('NMResultsViewerCrossAnalysisTools:NoModelSource','The selected analyses expose no Model Optimization model source.');end
            % nm2-allow: modelSource is absent from partial MATLAB specs (H14); viewerPlotOptions writes it for viewer specs; default is the first model source.
            requestedModelSource=NMResultsViewerCrossAnalysisTools.specText(spec,{'modelSource'},firstSources(1).id);
            if ~any(strcmp({firstSources.id},requestedModelSource)),error('NMResultsViewerCrossAnalysisTools:InvalidModelSource','The requested model source is unavailable in the first selected analysis.');end
            baseSpec.modelSource=requestedModelSource;
            firstClassifiers=NMResultsViewerTools.classifierOptions(NM,firstIndex,'model_optimization',baseSpec); firstClassifiers=firstClassifiers([firstClassifiers.enabled]);
            if isempty(firstClassifiers),error('NMResultsViewerCrossAnalysisTools:NoClassifier','The selected Model Optimization context exposes no classifier/model result.');end
            classifierIndex=NMResultsViewerCrossAnalysisTools.specNumeric(spec,{'classifierIndex'},double(firstClassifiers(1).index));
            if ~any([firstClassifiers.index]==classifierIndex),error('NMResultsViewerCrossAnalysisTools:InvalidClassifier','The requested classifier/model result is unavailable in the first selected analysis.');end

            aliases=NMResultsViewerCrossAnalysisTools.analysisAliasMap(spec,ws.analyses);
            matrices=cell(1,numel(selected)); payloads=cell(1,numel(selected)); annotations=repmat(NMResultsViewerScientificAnnotation.template(),1,numel(selected));
            canonicalLabels=cell(1,numel(selected));labels=cell(1,numel(selected));expectedSize=[];
            randomTemplate=NMResultsViewerTools.modelOptimizationRandomReference(criterionIdentity,struct());
            randomReferences=repmat(randomTemplate,1,numel(selected));
            for aa=1:numel(selected)
                idx=selected(aa);
                request=struct('resultType','model_optimization','analysisIndex',idx,'targetIndex',targetIndex,'modelSource',requestedModelSource,'classifierIndex',classifierIndex);
                payload=NMResultsViewerTools.getModelOptimizationPayload(NM,request);
                if ~payload.ok
                    error('NMResultsViewerCrossAnalysisTools:OptimizationPayloadUnavailable','Analysis %d Model Optimization payload is unavailable: %s',idx,payload.message);
                end
                if ~payload.partitions.cv2.ok || isempty(payload.partitions.cv2.matrix)
                    error('NMResultsViewerCrossAnalysisTools:CV2Unavailable','Analysis %d does not expose the authoritative matched CV2 optimization-criterion matrix.',idx);
                end
                matrix=NMResultsViewerCrossAnalysisTools.rowCellMatrix(payload.partitions.cv2.matrix);
                if isempty(expectedSize),expectedSize=size(matrix);elseif ~isequal(size(matrix),expectedSize)
                    error('NMResultsViewerCrossAnalysisTools:CV2ShapeMismatch','Selected analyses expose different CV2 criterion-matrix shapes and cannot be matched cell-by-cell.');
                end
                if any(~isfinite(matrix(:)))
                    error('NMResultsViewerCrossAnalysisTools:NonFiniteCV2','Matched CV2 criterion matrices must be fully finite; no implicit row deletion is permitted.');
                end
                if ~strcmp(payload.optimizationCriterion.key,criterionKeys{aa})
                    error('NMResultsViewerCrossAnalysisTools:CriterionMismatch','Analysis %d materialized a different optimization criterion than the queried Scientific State inventory.',idx);
                end
                annotation=payload.scientificAnnotation;
                matrices{aa}=matrix;payloads{aa}=payload;annotations(aa)=annotation;
                localClassifiers=NMResultsViewerTools.classifierOptions(NM,idx,'model_optimization',request);
                classifierHit=find([localClassifiers.index]==classifierIndex&[localClassifiers.enabled],1);
                if isempty(classifierHit),error('NMResultsViewerCrossAnalysisTools:InvalidClassifier','Analysis %d does not expose the selected classifier/model result.',idx);end
                randomReferences(aa)=NMResultsViewerTools.modelOptimizationRandomReference(criterionIdentity,localClassifiers(classifierHit));
                invHit=find([inventory.analysisIndex]==idx,1);canonicalLabels{aa}=inventory(invHit).label;labels{aa}=aliases{idx};
            end
            criterionLabel=criterionIdentity.label;
            randomReference=randomTemplate;
            availableRandom=[randomReferences.available];
            if all(availableRandom)
                values=[randomReferences.value];types={randomReferences.resultType};classCounts=[randomReferences.classCount];
                if max(abs(values-values(1)))<=eps(max(1,abs(values(1))))&&numel(unique(types))==1&&numel(unique(classCounts))==1
                    randomReference=randomReferences(1);
                else
                    randomReference.reason='Selected analyses do not share one random-performance classification reference.';
                end
            elseif any(availableRandom)
                randomReference.reason='Only some selected analyses expose the same random-performance classification reference.';
            else
                reasons={randomReferences.reason};if ~isempty(reasons),randomReference.reason=reasons{1};end
            end
            G=zeros(prod(expectedSize),numel(selected));
            for aa=1:numel(selected),G(:,aa)=matrices{aa}(:);end
            blockNames=arrayfun(@(ii)sprintf('CV2 cell %d',ii),1:size(G,1),'UniformOutput',false);

            referenceIndex=[];referencePosition=[];
            if numel(selected)==2
                testType='paired_wilcoxon';
                [stats,diff]=feval('wilcoxon',G(:,1)',G(:,2)',0.05,blockNames,labels,[]);
                pRaw=double(stats.p); pFdr=pRaw;
                inference=struct('testType',testType,'alpha',0.05,'p',pRaw,'pFdr',pFdr,'stats',stats,'difference',double(diff(:)));
                plotPayload=struct('type','none','message','Legacy two-analysis paired Wilcoxon has no dedicated statistical-comparison plot.');
            elseif isempty(references)
                testType='quade';
                legacyTableLabels=matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(labels));
                stats=feval('quadetest',G,blockNames,legacyTableLabels,[],0.05);
                inference=struct('testType',testType,'alpha',0.05,'omnibusW',double(stats.W),'omnibusP',double(stats.p),'stats',stats);
                [oneVsAll,oneVsAllMedian]=feval('nk_ComputeMnMdPairWiseDiff',G,'md','meandiff');
                [oneVsOne,oneVsOneMedian]=feval('nk_ComputeMnMdPairWiseDiff',G,'md','alldiff');
                plotPayload=NMResultsViewerCrossAnalysisTools.quadePlotPayload(G,selected,labels,oneVsAll,oneVsAllMedian,oneVsOne,oneVsOneMedian,stats,criterionIdentity,randomReference);
            else
                testType='reference_wilcoxon'; referenceIndex=references(1); referencePosition=find(selected==referenceIndex,1);
                otherPositions=setdiff(1:numel(selected),referencePosition,'stable'); otherLabels=labels(otherPositions);
                [stats,diff]=feval('wilcoxon',G(:,referencePosition)',G(:,otherPositions)',0.05,blockNames,[labels(referencePosition) otherLabels],[]);
                pRaw=double([stats.p]); [~,~,~,pFdr]=feval('fdr_bh',pRaw,0.05,'pdep'); pFdr=double(pFdr(:)');
                differences=double(diff'); % matched cells x comparison model
                med=nm_nanmedian(differences); ci=nm_95confint(differences);
                inference=struct('testType',testType,'alpha',0.05,'referenceAnalysisIndex',referenceIndex, ...
                    'otherAnalysisIndices',double(selected(otherPositions)),'p',pRaw,'pFdr',pFdr,'stats',stats,'differences',differences);
                bars=repmat(struct('analysisIndex',0,'label','','median',NaN,'ciLowOffset',NaN,'ciHighOffset',NaN,'p',NaN,'pFdr',NaN),1,numel(otherPositions));
                for jj=1:numel(otherPositions)
                    bars(jj)=struct('analysisIndex',double(selected(otherPositions(jj))),'label',otherLabels{jj},'median',double(med(jj)), ...
                        'ciLowOffset',double(ci(1,jj)),'ciHighOffset',double(ci(2,jj)),'p',double(pRaw(jj)),'pFdr',double(pFdr(jj)));
                end
                plotPayload=struct('type','reference_bar','criterionLabel',criterionLabel,'criterion',criterionIdentity,'randomPerformanceReference',randomReference,'referenceAnalysisIndex',referenceIndex,'referenceLabel',labels{referencePosition},'bars',bars);
            end

            tables=NMResultsViewerCrossAnalysisTools.statisticalTables(selected,labels,G,criterionLabel,testType,referenceIndex,inference,plotPayload);
            records=repmat(struct('reference','','scientificAnnotation',NMResultsViewerScientificAnnotation.template()),1,numel(annotations));
            for ii=1:numel(annotations),records(ii)=struct('reference',sprintf('analysis:%d|model_optimization',selected(ii)),'scientificAnnotation',annotations(ii));end
            directory=NMResultsViewerScientificDirectory.build(records);
            state=NMResultsViewerScientificState.clientView(analysisSetState); state.directory=directory;
            state.derivedArtefacts=struct('id','cross_analysis.statistical_comparison','scope','analysis_set','analysisIndices',double(selected(:)'), ...
                'materialized',true,'testType',testType,'optimizationCriterion',criterionLabel,'referenceAnalysisIndex',referenceIndex);
            selectorOptions=struct('targets',targets,'modelSources',firstSources,'classifiers',firstClassifiers,'selectedTargetIndex',targetIndex, ...
                'selectedModelSource',requestedModelSource,'selectedClassifierIndex',classifierIndex,'referenceOptions',NMResultsViewerCrossAnalysisTools.referenceOptions(selected,labels));
            out=struct('ok',true,'kind','cross_analysis.statistical_comparison','contractVersion','NM-CROSS-STATISTICAL-V1', ...
                'selectedAnalysisIndices',double(selected(:)'),'analysisLabels',{canonicalLabels},'analysisDisplayLabels',{labels},'optimizationCriterion',criterionIdentity,'randomPerformanceReference',randomReference, ...
                'targetIndex',targetIndex,'modelSource',requestedModelSource,'classifierIndex',classifierIndex,'cvCompatible',true,'cvGroup',double(inventory(1).cvGroup), ...
                'testType',testType,'referenceAnalysisIndex',referenceIndex,'matchedCV2',struct('matrix',G,'sourceShape',double(expectedSize),'blockCount',size(G,1)), ...
                'inference',inference,'plotPayload',plotPayload,'tables',tables,'selectorOptions',selectorOptions, ...
                'scientificAnnotations',annotations,'scientificDirectory',directory,'scientificState',state,'message',sprintf('%s comparison materialized across %d analyses and %d matched CV2 cells.',testType,numel(selected),size(G,1)));
        end

        function out = visualComparison(NM,spec,analysisSetState)
            % Interactive/retained use: Intended only for the explicit Visual comparison Generate/Report action; it introduces no hidden retained scientific rematerialization.
            % Purpose: Materialize the inherited Cross-analysis Visual Comparator as one descriptive aggregate OOT-performance artefact.
            % Syntax: out = NMResultsViewerCrossAnalysisTools.visualComparison(NM,spec[,analysisSetState])
            % Inputs: NM is read-only; spec supplies analysisIndices plus optional visualTargetIndex, visualModelSource, visualClassifierIndex, visualMultiClassModeIndex, visualMetricIds and presentation selectors; visualContextMode=per_analysis_default is the Report Builder composition contract, while the default shared mode is the interactive comparator contract. analysisSetState is the resident queried analysis_set Scientific State when available.
            % Outputs: cross_analysis.visual_comparison payload with one analysis-by-metric matrix, selector catalogues, long/pivot numerical tables, presentation plot payload, and Scientific Annotation/Directory/State provenance.
            % Authority and flow: Set identity/capabilities come from Scientific State; each aggregate held-out value comes only from Model Performance payload.performanceTabulationRows for source=cv. This function never reads GDdims/prob_contigency or computes a performance metric.
            % Scientific/state contract: Visual comparison is descriptive. Interactive shared mode matches effective target and class-contrast semantics while resolving model-source and classifier indices per analysis. Report Builder per_analysis_default mode resolves each analysis independently through the existing Model Performance selector authorities, records the exact Scientific Annotation context, and excludes unavailable members without narrowing the report scope.
            % Invariants: No CV-equivalence restriction is applied; visual comparison does not use matched CV2 matrices or inferential tests. Classification retains the 17 inherited metrics; regression metric identities come only from Model Performance. Sorting, bar/line mode, right-axis assignment, aliases and colours are presentation state and do not alter Scientific State.
            % Materialization and performance: Explicit Generate/Report action. O(A) compact Model Performance materializations plus O(A*M) metric projection for analyses A and at most 17 inherited metrics M; no imaging files/XML/atlas/annotation/mesh resources, voxel/vertex scans or feature-scale allocations.
            % Resource declaration: Reads no files directly, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; it consumes compact Model Performance payloads only.
            % Failure semantics: Fewer than two materializable analyses, stale analysis_set state, incompatible targets, contrasts, performance result types or sources, and absence of a common finite Model Performance metric fail explicitly. In per_analysis_default mode individual unavailable contexts become recorded exclusions; no substitute metric or CV-equivalence inference is used.
            % Side effects: None; NM and analysisSetState are not mutated and no files are written.
            % Consumers and dependencies: NMResultsViewerUI visual-comparison service, NMResultsViewerCrossAnalysis browser, and the single adaptive NMResultsViewerReportTools implementation.
            % nm2-allow: public Cross-analysis visual boundary supports an omitted request spec.
            if nargin<2||isempty(spec),spec=struct();end
            ws=NMResultsViewerCrossAnalysisTools.workspacePayload(NM,spec);
            selected=NMResultsViewerCrossAnalysisTools.selectedAnalysisIndices([ws.analyses.index],spec);
            if numel(selected)<2
                error('NMResultsViewerCrossAnalysisTools:VisualSelection','Visual comparison requires at least two completed analyses.');
            end
            % nm2-allow: public visual boundary accepts an omitted resident analysis-set state and materializes the canonical state once.
            if nargin<3||isempty(analysisSetState)
                analysisSetState=NMResultsViewerScientificState.forAnalysisSet(NM,selected,spec);
            end
            NMResultsViewerCrossAnalysisTools.validateAnalysisSetState(analysisSetState,selected,'Visual comparison');
            inventory=analysisSetState.inventory;
            % nm2-allow: visual context mode is explicit caller presentation state normalized at the public request boundary.
            contextMode=lower(strtrim(NMResultsViewerCrossAnalysisTools.specText(spec,{'visualContextMode'},'shared')));
            if ~ismember(contextMode,{'shared','per_analysis_default'})
                error('NMResultsViewerCrossAnalysisTools:InvalidVisualContextMode','Visual context mode must be shared or per_analysis_default.');
            end
            perAnalysisDefault=strcmp(contextMode,'per_analysis_default');
            performanceMask=arrayfun(@(x)logical(x.capabilities.modelPerformance),inventory);
            % nm2-allow: canonical analysis-set inventory cardinality and capability alignment are scientific validations.
            if numel(inventory)~=numel(selected)
                error('NMResultsViewerCrossAnalysisTools:InvalidAnalysisSetState', ...
                    'The analysis-set inventory has %d records for %d selected analyses.',numel(inventory),numel(selected));
            end
            if ~perAnalysisDefault&&any(~performanceMask)
                error('NMResultsViewerCrossAnalysisTools:PerformanceUnavailable', ...
                    'Analysis indices %s do not expose Model Performance capability.',mat2str(selected(~performanceMask)));
            elseif perAnalysisDefault&&sum(performanceMask)<2
                error('NMResultsViewerCrossAnalysisTools:PerformanceUnavailable','Fewer than two selected analyses expose Model Performance capability for visual comparison.');
            end

            if perAnalysisDefault
                sourceOptions=struct('id','cv','label','Cross-validation','enabled',true,'reason','');
            else
                sourceOptions=NMResultsViewerCrossAnalysisTools.commonSourceOptions(NM,selected,ws.analyses);
                if ~any(arrayfun(@(x)logical(x.enabled)&&strcmp(x.id,'cv'),sourceOptions))
                    error('NMResultsViewerCrossAnalysisTools:VisualCVUnavailable','Visual comparison requires the aggregate cross-validation (OOT) Model Performance source for every selected analysis.');
                end
            end

            aliases=NMResultsViewerCrossAnalysisTools.analysisAliasMap(spec,ws.analyses);
            requestedAnalysisIndices=selected;
            payloadCache=cell(1,0);contextTemplate=NMResultsViewerCrossAnalysisTools.visualAnalysisContextTemplate();analysisContexts=contextTemplate([]);excludedAnalyses=repmat(struct('analysisIndex',0,'reason',''),1,0);warnings={};
            if perAnalysisDefault
                retained=[];selectorBundles=cell(1,0);
                for aa=1:numel(selected)
                    idx=selected(aa);invHit=find([inventory.analysisIndex]==idx,1);
                    if isempty(invHit)||~logical(inventory(invHit).capabilities.modelPerformance)
                        excludedAnalyses(end+1)=struct('analysisIndex',double(idx),'reason','Model Performance capability is unavailable.'); %#ok<AGROW>
                        continue;
                    end
                    try
                        [payload,analysisContext,selectorBundle]=NMResultsViewerCrossAnalysisTools.visualDefaultPayloadContext(NM,idx,inventory(invHit));
                        retained(end+1)=idx;payloadCache{end+1}=payload;analysisContexts(end+1)=analysisContext;selectorBundles{end+1}=selectorBundle; %#ok<AGROW>
                    % nm2-allow: per-analysis report composition records explicit scientific unavailability and continues the requested set.
                    catch ME
                        excludedAnalyses(end+1)=struct('analysisIndex',double(idx),'reason',ME.message); %#ok<AGROW>
                    end
                end
                if numel(retained)<2
                    error('NMResultsViewerCrossAnalysisTools:VisualInsufficientEligible','Visual comparison found fewer than two analyses with an available default aggregate Model Performance context.');
                end
                selected=retained;firstPayload=payloadCache{1};firstSelectors=selectorBundles{1};targets=firstSelectors.targets;modelSources=firstSelectors.modelSources;classifiers=firstSelectors.classifiers;multiClassModes=firstSelectors.multiClassModes;
                resultType=analysisContexts(1).resultType;targetIndex=analysisContexts(1).targetIndex;requestedModelSource=analysisContexts(1).modelSource;classifierIndex=analysisContexts(1).classifierIndex;multiClassModeIndex=analysisContexts(1).multiClassModeIndex;
                for ee=1:numel(excludedAnalyses),warnings{end+1}=sprintf('Analysis %d was excluded from Visual comparison: %s',excludedAnalyses(ee).analysisIndex,excludedAnalyses(ee).reason);end %#ok<AGROW>
            else
                firstIndex=selected(1);
                firstInventory=inventory([inventory.analysisIndex]==firstIndex);
                % nm2-allow: canonical analysis-set inventory must expose exactly one resolved performance identity per selected analysis.
                if numel(firstInventory)~=1||isempty(firstInventory.effectivePerformanceResultType)
                    error('NMResultsViewerCrossAnalysisTools:InvalidAnalysisSetState','Visual comparison Scientific State lacks canonical Model Performance identity for analysis %d.',firstIndex);
                end
                resultType=firstInventory.effectivePerformanceResultType;
                targets=NMResultsViewerTools.targetOptions(NM,firstIndex);targets=targets([targets.enabled]);
                if isempty(targets),error('NMResultsViewerCrossAnalysisTools:VisualNoTarget','The selected analyses expose no enabled Model Performance target.');end
                targetIndex=NMResultsViewerCrossAnalysisTools.specNumeric(spec,{'visualTargetIndex','targetIndex'},double(targets(1).resultIndex));
                if ~any([targets.resultIndex]==targetIndex),error('NMResultsViewerCrossAnalysisTools:VisualInvalidTarget','The requested target is unavailable in the first selected analysis.');end
                baseSpec=struct('resultType',resultType,'analysisIndex',firstIndex,'targetIndex',targetIndex,'source','cv','graphType',1,'subgroupExpression','');
                modelSources=NMResultsViewerTools.modelSourcesForAnalysis(NM,firstIndex,resultType,baseSpec);modelSources=modelSources([modelSources.enabled]);
                if isempty(modelSources),modelSources=struct('id','','label','Primary model source','enabled',true,'reason','','kind','primary','index',NaN);end
                % nm2-allow: visualModelSource/modelSource are absent from partial MATLAB specs (H14); default is the first model source.
                requestedModelSource=NMResultsViewerCrossAnalysisTools.specText(spec,{'visualModelSource','modelSource'},modelSources(1).id);
                if ~any(strcmp({modelSources.id},requestedModelSource)),error('NMResultsViewerCrossAnalysisTools:VisualInvalidModelSource','The requested model source is unavailable in the first selected analysis.');end
                if ~isempty(requestedModelSource),baseSpec.modelSource=requestedModelSource;end
                classifiers=NMResultsViewerTools.classifierOptions(NM,firstIndex,resultType,baseSpec);classifiers=classifiers([classifiers.enabled]);
                if isempty(classifiers),error('NMResultsViewerCrossAnalysisTools:VisualNoClassifier','The selected Model Performance context exposes no enabled classifier/model result.');end
                classifierIndex=NMResultsViewerCrossAnalysisTools.specNumeric(spec,{'visualClassifierIndex','classifierIndex'},double(classifiers(1).index));
                if ~any([classifiers.index]==classifierIndex),error('NMResultsViewerCrossAnalysisTools:VisualInvalidClassifier','The requested classifier/model result is unavailable in the first selected analysis.');end
                baseSpec.classifierIndex=classifierIndex;
                firstPayload=NMResultsViewerTools.getPayload(NM,baseSpec);
                if ~firstPayload.ok,error('NMResultsViewerCrossAnalysisTools:VisualPayloadUnavailable','The first selected Model Performance payload is unavailable: %s',firstPayload.message);end
                payloadKind=firstPayload.kind;
                multiClassModes=repmat(struct('index',1,'id','1','label','','enabled',false,'reason',''),1,0);multiClassModeIndex=NaN;
                if strcmp(payloadKind,'multiclass')
                    multiClassModes=NMResultsViewerTools.multiClassModeOptions(NM,firstIndex,baseSpec);multiClassModes=multiClassModes([multiClassModes.enabled]&[multiClassModes.index]>1);
                    if isempty(multiClassModes),error('NMResultsViewerCrossAnalysisTools:VisualNoClassContrast','Multiclass visual comparison requires an enabled class-vs-REST Model Performance context.');end
                    multiClassModeIndex=NMResultsViewerCrossAnalysisTools.specNumeric(spec,{'visualMultiClassModeIndex','multiClassModeIndex'},double(multiClassModes(1).index));
                    if ~any([multiClassModes.index]==multiClassModeIndex),error('NMResultsViewerCrossAnalysisTools:VisualInvalidClassContrast','The requested class-vs-REST context is unavailable in the first selected analysis.');end
                    resultType='multiclass';
                elseif strcmp(payloadKind,'regression'),resultType='regression';
                elseif strcmp(payloadKind,'classification'),resultType='classification';
                else,error('NMResultsViewerCrossAnalysisTools:VisualUnsupportedTask','Visual comparison requires a classification, multiclass class-vs-REST or regression Model Performance payload.');end
            end

            catalogue=NMPerformanceMetricTools.metricCatalogue(firstPayload.kind,NMPerformanceMetricTools.canonicalRows(firstPayload.performanceTabulationRows));
            values=nan(numel(selected),numel(catalogue));available=true(1,numel(catalogue));
            annotations=repmat(NMResultsViewerScientificAnnotation.template(),1,numel(selected));labels=cell(1,numel(selected));displayLabels=cell(1,numel(selected));
            for aa=1:numel(selected)
                idx=selected(aa); invHit=find([inventory.analysisIndex]==idx,1); labels{aa}=inventory(invHit).label; displayLabels{aa}=aliases{idx};
                if perAnalysisDefault,payload=payloadCache{aa};
                else
                    req=struct('resultType',resultType,'analysisIndex',idx,'targetIndex',targetIndex,'source','cv','graphType',1,'subgroupExpression','','classifierIndex',classifierIndex);
                    if aa==1
                        if ~isempty(requestedModelSource),req.modelSource=requestedModelSource;end
                    else
                        reference=annotations(1).schema;
                        t=NMResultsViewerTools.targetOptions(NM,idx);t=t([t.enabled]);
                        matches=find(strcmp({t.name},reference.target.name));
                        if numel(matches)~=1
                            error('NMResultsViewerCrossAnalysisTools:VisualTargetMismatch', ...
                                'Analysis %d has %d analyzed targets named "%s"; exactly one is required to match analysis %d.', ...
                                idx,numel(matches),reference.target.name,selected(1));
                        end
                        req.targetIndex=t(matches).resultIndex;
                        ms=NMResultsViewerTools.modelSourcesForAnalysis(NM,idx,resultType,req);ms=ms([ms.enabled]);
                        if ~isempty(ms),req.modelSource=ms(1).id;end
                        cc=NMResultsViewerTools.classifierOptions(NM,idx,resultType,req);cc=cc([cc.enabled]);
                        if isempty(cc)
                            error('NMResultsViewerCrossAnalysisTools:VisualNoClassifier', ...
                                'Analysis %d has no enabled %s model result for target "%s".',idx,resultType,reference.target.name);
                        end
                        req.classifierIndex=cc(1).index;
                    end
                    if strcmp(resultType,'multiclass')
                        if aa==1
                            req.multiClassModeIndex=multiClassModeIndex;
                        else
                            modes=NMResultsViewerTools.multiClassModeOptions(NM,idx,req);
                            desiredContrast=sprintf('%s vs REST',reference.target.className);
                            match=find([modes.enabled]&strcmp({modes.label},desiredContrast));
                            if numel(match)~=1
                                error('NMResultsViewerCrossAnalysisTools:VisualClassContrastMismatch', ...
                                    'Analysis %d does not expose the class contrast "%s" selected in analysis %d.',idx,desiredContrast,selected(1));
                            end
                            req.multiClassModeIndex=modes(match).index;
                        end
                    end
                    payload=NMResultsViewerTools.getPayload(NM,req);
                    if ~payload.ok,error('NMResultsViewerCrossAnalysisTools:VisualPayloadUnavailable','Analysis %d Model Performance payload is unavailable: %s',idx,payload.message);end
                end
                annotation=payload.scientificAnnotation;
                if ~perAnalysisDefault&&aa>1
                    reference=annotations(1).schema;actual=annotation.schema;
                    if ~strcmp(actual.target.name,reference.target.name)
                        error('NMResultsViewerCrossAnalysisTools:VisualTargetMismatch', ...
                            'Analysis %d target "%s" differs from analysis %d target "%s".',idx,actual.target.name,selected(1),reference.target.name);
                    end
                    if ~strcmp(actual.target.classContrast,reference.target.classContrast)||~strcmp(actual.target.className,reference.target.className)
                        error('NMResultsViewerCrossAnalysisTools:VisualClassContrastMismatch', ...
                            'Analysis %d class contrast "%s" (%s) differs from analysis %d "%s" (%s).', ...
                            idx,actual.target.classContrast,actual.target.className,selected(1),reference.target.classContrast,reference.target.className);
                    end
                    if ~strcmp(actual.modelResult.type,reference.modelResult.type)
                        error('NMResultsViewerCrossAnalysisTools:VisualResultTypeMismatch', ...
                            'Analysis %d model result type "%s" differs from analysis %d "%s".', ...
                            idx,actual.modelResult.type,selected(1),reference.modelResult.type);
                    end
                    if ~strcmp(actual.source.id,reference.source.id)
                        error('NMResultsViewerCrossAnalysisTools:VisualSourceMismatch', ...
                            'Analysis %d performance source "%s" differs from analysis %d "%s".', ...
                            idx,actual.source.id,selected(1),reference.source.id);
                    end
                end
                metricRows=NMPerformanceMetricTools.canonicalRows(payload.performanceTabulationRows);
                for mm=1:numel(catalogue)
                    [v,found]=NMPerformanceMetricTools.value(metricRows,catalogue(mm).id);
                    values(aa,mm)=v;available(mm)=available(mm)&&found&&isfinite(v);
                end
                annotations(aa)=annotation;
            end
            catalogue=catalogue(available);values=values(:,available);
            if isempty(catalogue),error('NMResultsViewerCrossAnalysisTools:VisualNoCommonMetrics','Selected analyses expose no common finite inherited Visual Comparator performance measure.');end
            selectedMetricIds=NMResultsViewerCrossAnalysisTools.visualSelectedMetricIds(catalogue,spec);
            selectedPositions=find(ismember({catalogue.id},selectedMetricIds));
            selectedMetricIds={catalogue(selectedPositions).id};selectedMetricLabels={catalogue(selectedPositions).label};selectedValues=values(:,selectedPositions);
            separateIds=NMResultsViewerCrossAnalysisTools.visualSeparateAxisMetricIds(selectedMetricIds,spec);metricColors=NMResultsViewerCrossAnalysisTools.visualMetricColors(selectedMetricIds,spec);
            plotMode=lower(NMResultsViewerCrossAnalysisTools.specText(spec,{'visualPlotMode'},'bar'));if ~ismember(plotMode,{'bar','line'}),plotMode='bar';end
            sortAnalyses=NMResultsViewerCrossAnalysisTools.visualBoolean(spec,'visualSort',false);

            longRows=repmat(struct('analysisIndex',0,'analysis','','alias','','metricId','','metric','','value',NaN,'source','model_performance/performanceTabulationRows'),1,numel(selected)*numel(catalogue));kk=0;
            for aa=1:numel(selected),for mm=1:numel(catalogue),kk=kk+1;longRows(kk)=struct('analysisIndex',double(selected(aa)),'analysis',labels{aa},'alias',displayLabels{aa},'metricId',catalogue(mm).id,'metric',catalogue(mm).label,'value',double(values(aa,mm)),'source','model_performance/performanceTabulationRows');end,end
            tableCells=[{'Analysis','Alias'} {catalogue.label}];
            for aa=1:numel(selected),tableCells(end+1,:)=[{labels{aa},displayLabels{aa}} num2cell(values(aa,:))];end %#ok<AGROW>
            selectedTable=[{'Analysis','Alias'} selectedMetricLabels];
            for aa=1:numel(selected),selectedTable(end+1,:)=[{labels{aa},displayLabels{aa}} num2cell(selectedValues(aa,:))];end %#ok<AGROW>
            records=repmat(struct('reference','','scientificAnnotation',NMResultsViewerScientificAnnotation.template()),1,numel(annotations));
            for ii=1:numel(annotations),records(ii)=struct('reference',sprintf('analysis:%d|model_performance|visual_comparison',selected(ii)),'scientificAnnotation',annotations(ii));end
            directory=NMResultsViewerScientificDirectory.build(records);state=NMResultsViewerScientificState.clientView(analysisSetState);state.directory=directory;
            state.derivedArtefacts=struct('id','cross_analysis.visual_comparison','scope','analysis_set','analysisIndices',double(selected(:)'),'materialized',true,'source','cv','metricIds',{selectedMetricIds});
            selectorOptions=struct('targets',targets,'modelSources',modelSources,'classifiers',classifiers,'multiClassModes',multiClassModes,'metrics',catalogue, ...
                'contextMode',contextMode,'analysisContexts',analysisContexts,'selectedTargetIndex',targetIndex,'selectedModelSource',requestedModelSource,'selectedClassifierIndex',classifierIndex,'selectedMultiClassModeIndex',multiClassModeIndex,'selectedMetricIds',{selectedMetricIds});
            plotPayload=struct('type','aggregate_performance','analysisIndices',double(selected(:)'),'analysisLabels',{labels},'displayLabels',{displayLabels}, ...
                'metricIds',{selectedMetricIds},'metricLabels',{selectedMetricLabels},'metricColors',metricColors,'values',selectedValues,'plotMode',plotMode,'sortAnalyses',logical(sortAnalyses),'separateAxisMetricIds',{separateIds},'yLabel','Performance Measure(s)','xLabel','Analyses', ...
                'xPositions',((1:numel(selected))-0.5)/numel(selected), ...
                'bandLower',[],'bandUpper',[]);
            tables=struct('metricValues',{tableCells},'selectedMetricValues',{selectedTable},'long',longRows);
            selectedCvGroups=nan(1,numel(selected));
            for ii=1:numel(selected)
                invHit=find([inventory.analysisIndex]==selected(ii),1);
                if ~isempty(invHit),selectedCvGroups(ii)=double(inventory(invHit).cvGroup);end
            end
            out=struct('ok',true,'kind','cross_analysis.visual_comparison','contractVersion','NM-CROSS-VISUAL-V1','requestedAnalysisIndices',double(requestedAnalysisIndices(:)'),'selectedAnalysisIndices',double(selected(:)'), ...
                'analysisLabels',{labels},'analysisDisplayLabels',{displayLabels},'source','cv','targetIndex',targetIndex,'modelSource',requestedModelSource,'classifierIndex',classifierIndex, ...
                'multiClassModeIndex',multiClassModeIndex,'contextMode',contextMode,'analysisContexts',analysisContexts,'excludedAnalyses',excludedAnalyses,'cvCompatibilityRequired',false,'cvGroups',selectedCvGroups,'metricOptions',catalogue,'selectedMetricIds',{selectedMetricIds}, ...
                'values',values,'plotPayload',plotPayload,'tables',tables,'selectorOptions',selectorOptions,'scientificAnnotations',annotations,'scientificDirectory',directory,'scientificState',state, ...
                'warnings',{warnings},'message',sprintf('Visual comparison materialized %d aggregate OOT performance measure(s) across %d of %d requested analyses without a CV-equivalence restriction.',numel(selectedMetricIds),numel(selected),numel(requestedAnalysisIndices)));
        end

    end

    methods (Static, Access=private)
        function context=visualAnalysisContextTemplate()
            % Purpose: Define the fixed per-analysis Visual Comparison context record used by heterogeneous Report Builder composition.
            % Syntax: context = visualAnalysisContextTemplate().
            % Authority and flow: Values are populated only from established selector outputs and Model Performance Scientific Annotation.
            % Invariants: Analysis identity and every scientific coordinate remain explicit; aliases never enter this record.
            % Materialization and performance: Constant-size metadata only; no files/resources or scientific arrays.
            % Failure semantics: None. Side effects: None. Consumer: visualComparison/visualDefaultPayloadContext.
            context=struct('analysisIndex',0,'resultType','','targetIndex',NaN,'targetNativeIndex',NaN,'targetName','','classContrast','','classIndex',NaN,'className','','modelSource','','classifierIndex',NaN,'multiClassModeIndex',NaN,'fusionMode','');
        end

        function [payload,context,selectors]=visualDefaultPayloadContext(NM,analysisIndex,inventoryRow)
            % Purpose: Resolve one Report Builder aggregate-Performance context for one heterogeneous analysis.
            % Syntax: [payload,context,selectors] = visualDefaultPayloadContext(NM,analysisIndex,inventoryRow).
            % Authority and flow: Scientific State supplies the effective Performance type; targetOptions, modelSourcesForAnalysis, classifierOptions, multiClassModeOptions and getPayload remain the sole selector/materialization authorities.
            % Scientific/state contract: The first enabled choice at each selector is the established Results Viewer default for that analysis; the resulting Scientific Annotation is copied into the structured context record.
            % Invariants: No coordinate is copied from another analysis and no raw NM result container is traversed here.
            % Materialization and performance: One compact Model Performance payload, plus one replacement payload for multiclass class-vs-REST selection; no feature-scale resources.
            % Failure semantics: Missing selectors/payloads fail this analysis explicitly so the caller can record an exclusion. Side effects: None. Consumer: visualComparison per_analysis_default mode.
            resultType=inventoryRow.effectivePerformanceResultType;
            if isempty(resultType),error('NMResultsViewerCrossAnalysisTools:InvalidAnalysisSetState','Visual comparison Scientific State lacks canonical Model Performance identity for analysis %d.',analysisIndex);end
            targets=NMResultsViewerTools.targetOptions(NM,analysisIndex);targets=targets([targets.enabled]);
            if isempty(targets),error('NMResultsViewerCrossAnalysisTools:VisualNoTarget','Analysis %d exposes no enabled Model Performance target.',analysisIndex);end
            target=targets(1);request=struct('resultType',resultType,'analysisIndex',analysisIndex,'targetNativeIndex',double(target.index),'targetIndex',double(target.resultIndex),'source','cv','graphType',1,'subgroupExpression','');
            modelSources=NMResultsViewerTools.modelSourcesForAnalysis(NM,analysisIndex,resultType,request);modelSources=modelSources([modelSources.enabled]);
            if isempty(modelSources),modelSources=struct('id','','label','Primary model source','enabled',true,'reason','','kind','primary','index',NaN);end
            modelSource=modelSources(1).id;if ~isempty(modelSource),request.modelSource=modelSource;end
            classifiers=NMResultsViewerTools.classifierOptions(NM,analysisIndex,resultType,request);classifiers=classifiers([classifiers.enabled]);
            if isempty(classifiers),error('NMResultsViewerCrossAnalysisTools:VisualNoClassifier','Analysis %d default Model Performance context exposes no enabled classifier/model result.',analysisIndex);end
            request.classifierIndex=double(classifiers(1).index);
            payload=NMResultsViewerTools.getPayload(NM,request);
            if ~payload.ok,error('NMResultsViewerCrossAnalysisTools:VisualPayloadUnavailable','Analysis %d default Model Performance payload is unavailable: %s',analysisIndex,payload.message);end
            payloadKind=payload.kind;multiClassModes=repmat(struct('index',1,'id','1','label','','enabled',false,'reason',''),1,0);multiClassModeIndex=NaN;
            if strcmp(payloadKind,'multiclass')
                multiClassModes=NMResultsViewerTools.multiClassModeOptions(NM,analysisIndex,request);multiClassModes=multiClassModes([multiClassModes.enabled]&[multiClassModes.index]>1);
                if isempty(multiClassModes),error('NMResultsViewerCrossAnalysisTools:VisualNoClassContrast','Analysis %d exposes no enabled class-vs-REST Model Performance context.',analysisIndex);end
                multiClassModeIndex=double(multiClassModes(1).index);request.resultType='multiclass';request.multiClassModeIndex=multiClassModeIndex;payload=NMResultsViewerTools.getPayload(NM,request);
                if ~payload.ok,error('NMResultsViewerCrossAnalysisTools:VisualPayloadUnavailable','Analysis %d default class-vs-REST Model Performance payload is unavailable: %s',analysisIndex,payload.message);end
            elseif ~ismember(payloadKind,{'classification','regression'})
                error('NMResultsViewerCrossAnalysisTools:VisualUnsupportedTask','Analysis %d default Model Performance payload is neither classification, multiclass nor regression.',analysisIndex);
            end
            annotation=payload.scientificAnnotation;NMResultsViewerScientificAnnotation.validate(annotation);schema=annotation.schema;
            context=NMResultsViewerCrossAnalysisTools.visualAnalysisContextTemplate();context.analysisIndex=double(analysisIndex);context.resultType=payloadKind;context.targetIndex=double(schema.target.index);context.targetNativeIndex=double(schema.target.nativeIndex);context.targetName=schema.target.name;context.classContrast=schema.target.classContrast;context.classIndex=double(schema.target.classIndex);context.className=schema.target.className;context.modelSource=schema.source.modelSource;context.classifierIndex=double(schema.modelResult.index);context.multiClassModeIndex=multiClassModeIndex;context.fusionMode=schema.fusion.mode;
            selectors=struct('targets',targets,'modelSources',modelSources,'classifiers',classifiers,'multiClassModes',multiClassModes);
        end

        function validateAnalysisSetState(state,selected,consumer)
            % Validate one externally retained Scientific State analysis_set at the consumer boundary.
            if ~ismember(state.scope.type,{'analysis_set','synth_experiment'}) || ...
                    ~isequal(double(state.scope.analysisIndices(:)'),double(selected(:)'))
                error('NMResultsViewerCrossAnalysisTools:StaleAnalysisSetState', ...
                    '%s requires the queried Scientific State for the exact selected analysis set.',consumer);
            end
        end

        function value=specNumeric(spec,names,defaultValue)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Read one explicitly named finite scalar numeric Cross-analysis request coordinate.
            % Syntax: value = NMResultsViewerCrossAnalysisTools.specNumeric(spec,names,defaultValue)
            % Inputs: Request struct, explicit allowed field names, finite scalar default.
            % Outputs: Finite scalar request coordinate or default.
            % Authority and flow: Parses caller state only; it never derives scientific identity.
            % Scientific/state contract: Scientific validity remains checked by the owning selector/materialization authorities.
            % Invariants: Only direct declared fields are considered; no aliases beyond names explicitly supplied by the caller method.
            % Materialization and performance: O(number of names) compact metadata only.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays; safe on explicit Cross-analysis request paths.
            % Failure semantics: Non-finite/non-scalar requested values fail explicitly.
            % Side effects: None.
            % Consumers and dependencies: statisticalComparison and visualComparison request parsing.
            value=double(defaultValue);
            % nm2-allow: public Cross-analysis request boundary validates optional numeric selectors.
            if ~isstruct(spec),return;end
            for ii=1:numel(names)
                name=names{ii};
                % nm2-allow: public Cross-analysis request boundary accepts explicitly declared selector aliases.
                if isfield(spec,name)&&~isempty(spec.(name))
                    raw=spec.(name);
                    % nm2-allow: public Cross-analysis numeric selector validates caller-supplied request type and finiteness.
            if ~(isnumeric(raw)||islogical(raw))||~isscalar(raw)||~isfinite(double(raw))
                        error('NMResultsViewerCrossAnalysisTools:InvalidNumericCoordinate','Cross-analysis request field %s must be one finite numeric scalar.',name);
                    end
                    value=double(raw);return;
                end
            end
        end

        function matrix=rowCellMatrix(value)
            % Restore the fixed JSON-safe row-cell matrix emitted by Model Optimization.
            if isempty(value),matrix=[];return;end
            nRows=numel(value);width=numel(value{1});matrix=zeros(nRows,width);
            for rr=1:nRows
                row=value{rr};
                % nm2-allow: H7 row-cell CV2 matrix rows retain scientific numeric type and fixed-width axis validation.
                if ~(isnumeric(row)||islogical(row)) || numel(row)~=width
                    error('NMResultsViewerCrossAnalysisTools:InvalidCV2Matrix','Model Optimization CV2 row-cell representation is invalid at row %d.',rr);
                end
                matrix(rr,:)=double(row(:)');
            end
        end

        function ids=visualSelectedMetricIds(catalogue,spec)
            % Interactive/retained use: Presentation selector normalization for explicit Visual comparison/report actions.
            % Purpose: Normalize requested visualMetricIds against the common inherited metric catalogue.
            % Syntax: ids = NMResultsViewerCrossAnalysisTools.visualSelectedMetricIds(catalogue,spec)
            % Inputs: Common metric catalogue and request spec.
            % Outputs: Valid ids in catalogue order; defaults to Balanced Accuracy/first available metric.
            % Authority and flow: Presentation selection only; no metric materialization or computation.
            % Scientific/state contract: Metric availability comes from canonical Model Performance rows.
            % Invariants: At least one valid metric is returned.
            % Materialization and performance: O(M) compact metadata.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact Visual Comparator metadata/value projection only.
            % Failure semantics: Explicit request with no available ids fails.
            % Side effects: None.
            % Consumers and dependencies: visualComparison.
            available={catalogue.id};raw=[];
            % nm2-allow: visualMetricIds is written by NMResultsViewerCrossAnalysis.js only after a metric selection; absent selects the default metric.
            if isfield(spec,'visualMetricIds'),raw=spec.visualMetricIds;end
            if isempty(raw),if any(strcmp(available,'BAC')),ids={'BAC'};else,ids=available(1);end;return;end
            % nm2-allow: visual metric ids are caller presentation tokens normalized once at the public request boundary.
            if ischar(raw)||isstring(raw),raw=cellstr(string(raw));elseif ~iscell(raw),raw=cellstr(string(raw));end
            % nm2-allow: visual metric ids are caller presentation tokens normalized once at the public request boundary.
            missing=raw(~ismember(string(raw),string(available)));
            if ~isempty(missing)
                error('NMResultsViewerCrossAnalysisTools:VisualNoMetricSelection', ...
                    'Unavailable Visual Comparator metric(s): %s. Available choices: %s.', ...
                    strjoin(unique(string(missing),'stable'),', '),strjoin(available,', '));
            end
            requested=cellfun(@(x)char(string(x)),raw,'UniformOutput',false);ids=available(ismember(available,requested));if isempty(ids),error('NMResultsViewerCrossAnalysisTools:VisualNoMetricSelection','None of the requested Visual Comparator metrics is available in every selected analysis.');end
        end

        function ids=visualSeparateAxisMetricIds(selectedMetricIds,spec)
            % Interactive/retained use: Presentation-only right-axis selection.
            % Purpose: Normalize inherited Separate Axis metric ids against currently selected visual metrics.
            % Syntax: ids = NMResultsViewerCrossAnalysisTools.visualSeparateAxisMetricIds(selectedMetricIds,spec)
            % Inputs: Selected metric ids and request spec.visualSeparateAxisMetricIds.
            % Outputs: Valid selected subset in selected-metric order.
            % Authority and flow: Presentation state only; no scientific state mutation.
            % Scientific/state contract: Axis assignment cannot change metric values or identity.
            % Invariants: Unselected/unknown ids are dropped.
            % Materialization and performance: O(M) metadata.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact Visual Comparator metadata/value projection only.
            % Failure semantics: Missing field yields empty right-axis set.
            % Side effects: None.
            % Consumers and dependencies: visualComparison/report/browser plotting.
            raw=[];
            % nm2-allow: visualSeparateAxisMetricIds is written by NMResultsViewerCrossAnalysis.js only for visual comparisons; absent means one axis.
            if isfield(spec,'visualSeparateAxisMetricIds'),raw=spec.visualSeparateAxisMetricIds;end
            if isempty(raw),ids={};return;end
            % nm2-allow: right-axis metric ids are caller presentation tokens normalized once at the public request boundary.
            if ischar(raw)||isstring(raw),raw=cellstr(string(raw));elseif ~iscell(raw),raw=cellstr(string(raw));end
            % nm2-allow: right-axis metric ids are caller presentation tokens normalized once at the public request boundary.
            requested=cellfun(@(x)char(string(x)),raw,'UniformOutput',false);ids=selectedMetricIds(ismember(selectedMetricIds,requested));
        end

        function colors=visualMetricColors(selectedMetricIds,spec)
            % Interactive/retained use: Presentation-only colour normalization for Visual Comparator/report output.
            % Purpose: Retain explicit per-metric series colours without placing them in Scientific State.
            % Syntax: colors = NMResultsViewerCrossAnalysisTools.visualMetricColors(selectedMetricIds,spec)
            % Inputs: Selected metric ids and optional spec.visualMetricColors struct rows with metricId/color.
            % Outputs: One metricId/color row per selected metric, using stable presentation defaults when no explicit colour exists.
            % Authority and flow: Presentation request state only; no scientific value or identity is derived from colour.
            % Scientific/state contract: Colours are report/view state and never affect performance values or Scientific Annotation.
            % Invariants: Only six-digit hexadecimal CSS colours are admitted; output order follows selectedMetricIds.
            % Materialization and performance: O(M) compact metadata.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact Visual Comparator metadata/value projection only.
            % Failure semantics: Invalid explicit colours are ignored in favour of stable defaults.
            % Side effects: None.
            % Consumers and dependencies: visualComparison plot payload and static report renderer.
            defaults={'#2563eb','#c2410c','#059669','#7c3aed','#ca8a04','#0891b2','#be123c','#4f46e5'};colors=repmat(struct('metricId','','color',''),1,numel(selectedMetricIds));raw=[];
            % nm2-allow: visualMetricColors is written by NMResultsViewerCrossAnalysis.js only for visual comparisons; absent keeps the default palette.
            if isfield(spec,'visualMetricColors'),raw=spec.visualMetricColors;end
            for ii=1:numel(selectedMetricIds)
                id=selectedMetricIds{ii};color=defaults{mod(ii-1,numel(defaults))+1};
                % nm2-allow: optional visual colour rows are external presentation state validated at the public request boundary.
                if isstruct(raw)
                    for rr=1:numel(raw)
                        rid=raw(rr).metricId;candidate=raw(rr).color;
                        if strcmp(rid,id)&&~isempty(regexp(candidate,'^#[0-9A-Fa-f]{6}$','once')),color=candidate;break;end
                    end
                end
                colors(ii)=struct('metricId',id,'color',color);
            end
        end

        function value=visualBoolean(spec,name,defaultValue)
            % Interactive/retained use: Presentation-only request parsing.
            % Purpose: Read one explicit scalar logical/numeric Visual Comparator presentation flag.
            % Syntax: value = NMResultsViewerCrossAnalysisTools.visualBoolean(spec,name,defaultValue)
            % Inputs: Request struct, exact field name and default logical.
            % Outputs: Logical scalar.
            % Authority and flow: Parses caller presentation state only.
            % Scientific/state contract: Does not alter scientific materialization.
            % Invariants: Only scalar logical/numeric values override the default.
            % Materialization and performance: O(1) metadata.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact Visual Comparator metadata/value projection only.
            % Failure semantics: Invalid/missing field returns default.
            % Side effects: None.
            % Consumers and dependencies: visualComparison.
            value=logical(defaultValue);
            % nm2-allow: visual boolean controls are optional caller presentation state.
            if ~isstruct(spec)||~isfield(spec,name),return;end;raw=spec.(name);if (islogical(raw)||isnumeric(raw))&&isscalar(raw)&&isfinite(double(raw)),value=logical(raw);end
        end

        function options=referenceOptions(indices,labels)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Project selected analyses into the explicit optional-reference selector catalogue.
            % Syntax: options = NMResultsViewerCrossAnalysisTools.referenceOptions(indices,labels)
            % Inputs: Selected analysis ids and their Scientific State labels.
            % Outputs: Fixed-schema none + one entry per selected analysis.
            % Authority and flow: Presentation catalogue only; analysis identity/labels come from queried Scientific State inventory.
            % Scientific/state contract: At most one analysis can be selected as reference; none is represented by index 0.
            % Invariants: Catalogue order follows selected analysis order.
            % Materialization and performance: O(A) metadata allocation only.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact Visual Comparator metadata/value projection only.
            % Failure semantics: None for valid aligned inputs.
            % Side effects: None.
            % Consumers and dependencies: statisticalComparison browser selector metadata.
            tmpl=struct('analysisIndex',0,'label','No reference');options=repmat(tmpl,1,numel(indices)+1);options(1)=tmpl;
            for ii=1:numel(indices),options(ii+1)=struct('analysisIndex',double(indices(ii)),'label',labels{ii});end
        end

        function summary=distributionSummary(values)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Compute backend-owned median/IQR/extent summaries used only to draw statistical-comparison distributions.
            % Syntax: summary = NMResultsViewerCrossAnalysisTools.distributionSummary(values)
            % Inputs: One finite matched-CV2 vector already present in the canonical statistical payload.
            % Outputs: min, q1, mean, median, q3, max and n.
            % Authority and flow: Presentation summary of canonical statistical values; no inferential statistic is introduced.
            % Scientific/state contract: Browser renderers consume these summaries and never recalculate scientific deltas/p-values.
            % Invariants: Input values are preserved elsewhere in the same canonical payload; quantiles use existing nm_nanquantile semantics.
            % Materialization and performance: O(B) scalar summary; no resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact Visual Comparator metadata/value projection only.
            % Failure semantics: Empty vectors return NaN summary values.
            % Side effects: None.
            % Consumers and dependencies: quadePlotPayload.
            v=double(values(:));v=v(isfinite(v));summary=struct('min',NaN,'q1',NaN,'mean',NaN,'median',NaN,'q3',NaN,'max',NaN,'n',numel(v));
            if isempty(v),return;end
            summary.min=min(v);summary.max=max(v);summary.q1=nm_nanquantile(v,0.25);summary.mean=mean(v);summary.median=nm_nanmedian(v);summary.q3=nm_nanquantile(v,0.75);
        end

        function plotPayload=quadePlotPayload(G,indices,labels,oneVsAll,oneVsAllMedian,oneVsOne,oneVsOneMedian,stats,criterion,randomReference)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Build all inherited Quade statistical-comparator plot inputs from the already-matched canonical CV2 matrix/result.
            % Syntax: plotPayload = NMResultsViewerCrossAnalysisTools.quadePlotPayload(G,indices,labels,oneVsAll,oneVsAllMedian,oneVsOne,oneVsOneMedian,stats,criterion,randomReference)
            % Inputs: Canonical matched matrix G, canonical analysis indices, presentation aliases, backend-computed inherited median pairwise deltas, corrected Quade result, authoritative criterion identity/display domain and validated shared classification random reference.
            % Outputs: Four view payloads (performance violins, one-vs-all delta violins, one-vs-one delta boxes, median/IQR) plus the corrected FDR -log10(P) matrix when post-hoc results exist.
            % Authority and flow: Delta inputs come only from nk_ComputeMnMdPairWiseDiff and significance only from quadetest; this helper computes presentation summaries, not alternative scientific values.
            % Scientific/state contract: Every plot is a projection of the same matrix/result used for inference. Browser code must not reconstruct pairwise deltas or corrected p-values.
            % Invariants: Analysis ordering is identical across inference and plots; no post-hoc matrix is fabricated when Quade did not produce one.
            % Materialization and performance: O(B*A^2) compact vector/summary projection; no external resources or feature-scale arrays.
            % Resource declaration: Reads no files/resources and creates no feature-scale arrays; statistical vectors only.
            % Failure semantics: Inconsistent dimensions fail through normal MATLAB indexing rather than silent repair.
            % Side effects: None.
            % Consumers and dependencies: statisticalComparison, browser renderer and Report Builder.
            n=size(G,2);seriesTemplate=struct('analysisIndex',0,'label','','values',[],'density',struct([]),'summary',struct());perf=repmat(seriesTemplate,1,n);ova=perf;mediqr=perf;
            for ii=1:n
                perfSummary=NMResultsViewerCrossAnalysisTools.distributionSummary(G(:,ii));
                perf(ii)=struct('analysisIndex',double(indices(ii)),'label',labels{ii},'values',double(G(:,ii)),'density',NMResultsViewerTools.violinDensity(G(:,ii)),'summary',perfSummary);
                ova(ii)=struct('analysisIndex',double(indices(ii)),'label',labels{ii},'values',double(oneVsAll(:,ii)),'density',NMResultsViewerTools.violinDensity(oneVsAll(:,ii)),'summary',NMResultsViewerCrossAnalysisTools.distributionSummary(oneVsAll(:,ii)));
                iqrSummary=perfSummary;iqrSummary.min=perfSummary.q1;iqrSummary.max=perfSummary.q3;
                mediqr(ii)=struct('analysisIndex',double(indices(ii)),'label',labels{ii},'values',[],'density',struct([]),'summary',iqrSummary);
            end
            pairs=repmat(struct('fromIndex',0,'toIndex',0,'label','','values',[],'summary',struct(),'median',NaN),1,n*(n-1)/2);kk=0;
            for ii=1:n-1
                other=setdiff(1:n,ii,'stable');
                for target=ii+1:n
                    pos=find(other==target,1);kk=kk+1;pairs(kk)=struct('fromIndex',double(indices(ii)),'toIndex',double(indices(target)),'label',sprintf('%s - %s',labels{ii},labels{target}), ...
                        'values',double(oneVsOne(:,pos,ii)),'summary',NMResultsViewerCrossAnalysisTools.distributionSummary(oneVsOne(:,pos,ii)),'median',double(oneVsOneMedian(1,pos,ii)));
                end
            end
            fdrMatrix=[];logFdrMatrix=[];
            if stats.p<stats.alpha
                fdrMatrix=table2array(stats.tbl_p_fdr_posthoc);rawFdr=double(fdrMatrix);logFdrMatrix=NaN(size(rawFdr));finiteFdr=isfinite(rawFdr)&rawFdr>=0;logFdrMatrix(finiteFdr)=-log10(max(rawFdr(finiteFdr),realmin('double')));
            end
            plotPayload=struct('type','quade','criterionLabel',criterion.label,'criterion',criterion,'randomPerformanceReference',randomReference,'performance',perf,'oneVsAll',ova,'oneVsAllMedian',double(oneVsAllMedian), ...
                'oneVsOne',pairs,'medianIqr',mediqr,'fdrMatrix',double(fdrMatrix),'negLog10FdrMatrix',double(logFdrMatrix),'labels',{labels});
        end

        function tables=statisticalTables(indices,labels,G,criterionLabel,testType,referenceIndex,inference,plotPayload)
            % Interactive/retained use: Intended only for the explicit Cross-analysis or report action documented by this function; it introduces no hidden retained scientific rematerialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays beyond compact statistical/table presentation values explicitly described below.
            % Purpose: Project the canonical statistical artefact into numerical tables for Report Builder/CSV/XLSX output.
            % Syntax: tables = NMResultsViewerCrossAnalysisTools.statisticalTables(indices,labels,G,criterionLabel,testType,referenceIndex,inference,plotPayload)
            % Inputs: Selected ids/labels, canonical matched matrix, criterion/test/reference and already-computed inference/plot payload.
            % Outputs: Summary, matchedCV2 and test-specific numerical cell/struct tables plus exact columnCounts for JSON reconstruction; Quade browser summary panels use two-column statistic/value tables, while numerical detail exports retain plot/difference matrices.
            % Authority and flow: Pure reshaping of inference/plot payload; no statistic, FDR correction, delta or confidence interval is recalculated here.
            % Scientific/state contract: Spreadsheet numerical exports and HTML/PDF consume the same statistical artefact used by the browser.
            % Invariants: Matched matrix row order and analysis column order are preserved exactly.
            % Materialization and performance: O(B*A + B*A^2) compact table copies; no files/resources or feature-scale arrays.
            % Resource declaration: Reads no files/resources and creates no feature-scale arrays; compact statistical tables only.
            % Failure semantics: Unsupported testType fails explicitly.
            % Side effects: None.
            % Consumers and dependencies: statisticalComparison and Report Builder.
            summary={'Field','Value';'Test type',testType;'Optimization criterion',criterionLabel;'Analysis count',numel(indices);'Matched CV2 cells',size(G,1);'Reference analysis index',referenceIndex};
            matched=cell(size(G,1)+1,size(G,2)+1);matched(1,:)=[{'Matched CV2 cell'} labels];for rr=1:size(G,1),matched{rr+1,1}=rr;for cc=1:size(G,2),matched{rr+1,cc+1}=G(rr,cc);end,end
            tables=struct('summary',{summary},'matchedCV2',{matched},'testSummary',{{}},'postHoc',{{}},'plotSummary',{{}},'oneVsAllSummary',{{}},'oneVsOneSummary',{{}},'fdrMatrix',{{}},'pairedDifferences',{{}},'referenceDifferences',{{}});
            switch testType
                case 'paired_wilcoxon'
                    st=inference.stats;tables.testSummary={'Comparison','Method','W','z','p','p_FDR';st.comparison,st.method,st.W,st.z,inference.p,inference.pFdr};pd=cell(numel(inference.difference)+1,2);pd(1,:)={'Matched CV2 cell','Difference (analysis 2 - analysis 1)'};for rr=1:numel(inference.difference),pd(rr+1,:)={rr,inference.difference(rr)};end;tables.pairedDifferences=pd;
                case 'reference_wilcoxon'
                    bars=plotPayload.bars;ts=cell(numel(bars)+1,7);ts(1,:)={'Analysis index','Analysis','Median difference','CI low offset','CI high offset','p','p_FDR'};
                    for ii=1:numel(bars),ts(ii+1,:)={bars(ii).analysisIndex,bars(ii).label,bars(ii).median,bars(ii).ciLowOffset,bars(ii).ciHighOffset,bars(ii).p,bars(ii).pFdr};end
                    tables.testSummary=ts;d=inference.differences;other=inference.otherAnalysisIndices;rd=cell(size(d,1)+1,size(d,2)+1);rd(1,:)=[{'Matched CV2 cell'} arrayfun(@(x)sprintf('Analysis %d difference from reference',x),other,'UniformOutput',false)];for rr=1:size(d,1),rd{rr+1,1}=rr;for cc=1:size(d,2),rd{rr+1,cc+1}=d(rr,cc);end,end;tables.referenceDifferences=rd;
                case 'quade'
                    tables.testSummary={'Statistic','Value';'Quade W',inference.omnibusW;'Omnibus p',inference.omnibusP;'Alpha',inference.alpha};
                    st=inference.stats;if st.p<st.alpha,raw=table2array(st.tbl_p_posthoc);fdr=table2array(st.tbl_p_fdr_posthoc);nPairs=numel(labels)*(numel(labels)-1)/2;ph=cell(1+2*nPairs,2);ph(1,:)={'Statistic','Value'};kk=1;for ii=1:numel(labels),for jj=ii+1:numel(labels),comparison=sprintf('%s vs %s',labels{ii},labels{jj});kk=kk+1;ph(kk,:)={[comparison ' · p'],raw(ii,jj)};kk=kk+1;ph(kk,:)={[comparison ' · p_FDR'],fdr(ii,jj)};end,end;tables.postHoc=ph(1:kk,:);end
                    ps=cell(numel(labels)+1,7);ps(1,:)={'Analysis','Min','Q1','Median','Q3','Max','N'};for ii=1:numel(labels),q=plotPayload.performance(ii).summary;ps(ii+1,:)={labels{ii},q.min,q.q1,q.median,q.q3,q.max,q.n};end;tables.plotSummary=ps;ova=plotPayload.oneVsAll;os=cell(numel(ova)+1,7);os(1,:)={'Analysis','Min delta','Q1 delta','Median delta','Q3 delta','Max delta','N'};for ii=1:numel(ova),q=ova(ii).summary;os(ii+1,:)={ova(ii).label,q.min,q.q1,q.median,q.q3,q.max,q.n};end;tables.oneVsAllSummary=os;ovo=plotPayload.oneVsOne;bs=cell(numel(ovo)+1,9);bs(1,:)={'From index','To index','Comparison','Min delta','Q1 delta','Median delta','Q3 delta','Max delta','N'};for ii=1:numel(ovo),q=ovo(ii).summary;bs(ii+1,:)={ovo(ii).fromIndex,ovo(ii).toIndex,ovo(ii).label,q.min,q.q1,q.median,q.q3,q.max,q.n};end;tables.oneVsOneSummary=bs;if ~isempty(plotPayload.fdrMatrix),fm=cell(size(plotPayload.fdrMatrix,1)+1,size(plotPayload.fdrMatrix,2)+1);fm(1,:)=[{'Analysis'} labels];for ii=1:size(plotPayload.fdrMatrix,1),fm{ii+1,1}=labels{ii};for jj=1:size(plotPayload.fdrMatrix,2),fm{ii+1,jj+1}=plotPayload.fdrMatrix(ii,jj);end,end;tables.fdrMatrix=fm;end;
                otherwise
                    error('NMResultsViewerCrossAnalysisTools:UnknownStatisticalTest','Unknown statistical comparison test type %s.',testType);
            end
            tableNames=fieldnames(tables);columnCounts=struct();
            for tt=1:numel(tableNames),name=tableNames{tt};columnCounts.(name)=size(tables.(name),2);end
            tables.columnCounts=columnCounts;
        end

        function selected=selectedAnalysisIndices(completedIndices,spec)
            % Purpose: Normalize requested cross-analysis analysis indices against the completed-analysis set.
            % Syntax: selected = NMResultsViewerCrossAnalysisTools.selectedAnalysisIndices(completedIndices,spec)
            % Inputs: completedIndices is the authoritative completed-analysis id vector; spec may contain analysisIndices/AnalysisIndices.
            % Outputs: Unique requested ids in canonical completed-analysis catalogue order.
            % Authority and flow: Filters explicit caller selection only; completion identity comes from the supplied Results Viewer catalogue.
            % Scientific/state contract: Does not inspect NM or infer analysis equivalence.
            % Invariants: Every returned id is completed, occurs once, and follows the canonical completed-analysis catalogue order.
            % Materialization and performance: O(A) numeric normalization; no files/resources or scientific payload materialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Missing selection returns completedIndices by established workspace default; non-integer or unavailable requested ids fail explicitly rather than being discarded.
            % Side effects: None.
            % Consumers and dependencies: workspacePayload/performanceTable.
            selected=[];
            if isempty(completedIndices),return;end
            raw=[];
            % nm2-allow: public Cross-analysis analysis-set selector validates external request container/type.
            if isstruct(spec)
                % nm2-allow: analysisIndices is written by NMResultsViewerCrossAnalysis.js; specs without it select all completed analyses.
                if isfield(spec,'analysisIndices'),raw=spec.analysisIndices;end
            end
            if isempty(raw)
                selected=double(completedIndices(:)');
                return;
            end
            % nm2-allow: public Cross-analysis analysis-set selector normalizes caller-provided cell/numeric ids at the request boundary.
            if iscell(raw),raw=cellfun(@double,raw);end
            raw=double(raw(:)');
            % nm2-allow: public analysis-index request values are validated for finite unique positive-integer identity.
            if any(~isfinite(raw))||any(raw<1)||any(abs(raw-round(raw))>eps(max(1,abs(raw))))||numel(unique(raw))~=numel(raw)
                error('NMResultsViewerCrossAnalysisTools:InvalidAnalysisSelection', ...
                    'Cross-analysis analysisIndices must contain unique positive integer completed-analysis ids.');
            end
            raw=round(raw);
            completed=double(completedIndices(:)');
            if any(~ismember(raw,completed))
                error('NMResultsViewerCrossAnalysisTools:InvalidAnalysisSelection', ...
                    'Cross-analysis analysisIndices contains an analysis that is not completed or available.');
            end
            selected=completed(ismember(completed,raw));
        end

        function catalogue=sourceOptionsByAnalysis(NM,indices,analyses)
            % Purpose: Build per-analysis CV/OOCV source catalogues for Cross-analysis selection.
            % Syntax: catalogue = NMResultsViewerCrossAnalysisTools.sourceOptionsByAnalysis(NM,indices,analyses)
            % Inputs: NM is read-only; indices are analysis ids; analyses is the shared Results Viewer analysis catalogue.
            % Outputs: One analysisIndex/options record per requested analysis.
            % Authority and flow: resultTypesForAnalysis/defaultPerformanceResultType owns the canonical Model Performance family; source availability delegates to NMResultsViewerTools.sourcesForAnalysis.
            % Scientific/state contract: Cross-analysis does not inspect OOCV containers itself.
            % Invariants: Source ids/enablement are preserved exactly from the shared selector authority.
            % Materialization and performance: O(A*S) compact metadata; no files/XML/atlas/annotation/mesh loads or feature-scale arrays.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Missing catalogue row yields an empty/default source set for that id.
            % Side effects: None.
            % Consumers and dependencies: workspacePayload/commonSourceOptions.
            tmpl=struct('analysisIndex',NaN,'options',repmat(struct('id','','label','','enabled',false,'reason',''),1,0));
            catalogue=repmat(tmpl,1,numel(indices));
            for ii=1:numel(indices)
                types=NMResultsViewerTools.resultTypesForAnalysis(NM,indices(ii),struct('analysisIndex',indices(ii)),analyses);
                rt=NMResultsViewerTools.defaultPerformanceResultType(NM,indices(ii),types);
                catalogue(ii).analysisIndex=double(indices(ii));
                catalogue(ii).options=NMResultsViewerTools.sourcesForAnalysis(NM,indices(ii),rt);
            end
        end

        function options=commonSourceOptions(NM,indices,analyses)
            % Purpose: Resolve source options shared by selected analyses from the authoritative per-analysis source catalogues.
            % Syntax: options = NMResultsViewerCrossAnalysisTools.commonSourceOptions(NM,indices,analyses)
            % Inputs: NM, selected ids and shared analysis catalogue.
            % Outputs: Intersection source catalogue.
            % Authority and flow: Composes sourceOptionsByAnalysis then commonSourceOptionsFromCatalogue; no direct source discovery.
            % Scientific/state contract: Only sources enabled for every selected analysis are common.
            % Invariants: Source ids/labels originate from NMResultsViewerTools.
            % Materialization and performance: O(A*S) compact metadata; no files/resources or scientific payloads.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Empty indices/catalgoue returns no common sources.
            % Side effects: None.
            % Consumers and dependencies: performanceTable.
            catalogue=NMResultsViewerCrossAnalysisTools.sourceOptionsByAnalysis(NM,indices,analyses);
            options=NMResultsViewerCrossAnalysisTools.commonSourceOptionsFromCatalogue(catalogue,indices);
        end

        function options=commonSourceOptionsFromCatalogue(catalogue,indices)
            % Purpose: Intersect enabled source ids across an existing per-analysis source catalogue.
            % Syntax: options = NMResultsViewerCrossAnalysisTools.commonSourceOptionsFromCatalogue(catalogue,indices)
            % Inputs: catalogue is sourceOptionsByAnalysis output; indices is selected analysis set.
            % Outputs: Enabled source options present for every selected analysis.
            % Authority and flow: Pure set intersection over backend-provided options; does not inspect NM.
            % Scientific/state contract: Availability cannot be promoted by the cross-analysis layer.
            % Invariants: Returned options are a subset of the first selected analysis' enabled options and exist enabled in all others.
            % Materialization and performance: O(A*S^2) over small source lists; no files/resources or scientific arrays.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Missing selection/options returns an empty fixed-schema catalogue.
            % Side effects: None.
            % Consumers and dependencies: workspacePayload/commonSourceOptions.
            tmpl=struct('id','cv','label','Cross-validation','enabled',true,'reason','');
            if isempty(indices),options=tmpl([]);return;end
            sourceLists=cell(1,numel(indices));
            for ii=1:numel(indices)
                hit=find([catalogue.analysisIndex]==indices(ii),1,'first');
                if isempty(hit),sourceLists{ii}=tmpl([]);else,sourceLists{ii}=catalogue(hit).options;end
            end
            first=sourceLists{1}; options=repmat(tmpl,1,0);
            for jj=1:numel(first)
                if ~logical(first(jj).enabled),continue;end
                id=first(jj).id; common=true;
                for ii=2:numel(sourceLists)
                    rows=sourceLists{ii}; hit=false;
                    for kk=1:numel(rows)
                        if strcmp(rows(kk).id,id)&&logical(rows(kk).enabled),hit=true;break;end
                    end
                    if ~hit,common=false;break;end
                end
                if common
                    options(end+1)=struct('id',id,'label',first(jj).label,'enabled',true,'reason',''); %#ok<AGROW>
                end
            end
            if isempty(options),options=tmpl;options.enabled=false;options.reason='Selected analyses have no common performance result source.';end
        end

        function source=selectedSource(options,spec)
            % Purpose: Normalize the requested cross-analysis source to the common enabled source catalogue.
            % Syntax: source = NMResultsViewerCrossAnalysisTools.selectedSource(options,spec)
            % Inputs: common source options and request spec.
            % Outputs: Requested enabled source id, otherwise first enabled source or empty string.
            % Authority and flow: Selection only; source availability is already resolved upstream.
            % Scientific/state contract: Does not create aliases or make disabled sources available.
            % Invariants: Non-empty output is one enabled common source.
            % Materialization and performance: O(S) small metadata lookup; no files/resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: No enabled source returns ''.
            % Side effects: None.
            % Consumers and dependencies: workspacePayload/performanceTable.
            source='cv'; requested=NMResultsViewerCrossAnalysisTools.specText(spec,{'crossAnalysisSource','source'},'cv');
            for ii=1:numel(options)
                if strcmp(options(ii).id,requested)&&logical(options(ii).enabled),source=requested;return;end
            end
            for ii=1:numel(options)
                if logical(options(ii).enabled),source=options(ii).id;return;end
            end
            source='';
        end

        function row=analysisRow(analyses,index)
            % Purpose: Return one analysis catalogue record by canonical analysis index.
            % Syntax: row = NMResultsViewerCrossAnalysisTools.analysisRow(analyses,index)
            % Inputs: analyses is NMResultsViewerTools.listAnalyses output; index is requested analysis id.
            % Outputs: Matching scalar catalogue row or empty.
            % Authority and flow: Lookup only; no NM traversal.
            % Scientific/state contract: Preserves the shared catalogue as analysis identity authority.
            % Invariants: Exact numeric index matching.
            % Materialization and performance: O(A) metadata lookup; no files/resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: No match returns [].
            % Side effects: None.
            % Consumers and dependencies: performanceTable/sourceOptionsByAnalysis.
            row=[];
            if isempty(analyses),return;end
            hit=find([analyses.index]==index,1,'first');if ~isempty(hit),row=analyses(hit);end
        end

        function aliases=analysisAliasMap(spec,analyses)
            % Purpose: Normalize user-provided display aliases for completed analyses.
            % Syntax: aliases = NMResultsViewerCrossAnalysisTools.analysisAliasMap(spec,analyses)
            % Inputs: spec.analysisAliases may contain analysisIndex/alias rows; analyses is shared catalogue.
            % Outputs: Cell array indexed by analysis id, defaulting to canonical analysis title.
            % Authority and flow: Aliases are presentation/report metadata only; scientific analysis identity remains numeric analysis index/annotation.
            % Scientific/state contract: Alias text never replaces Scientific Annotation analysis identity.
            % Invariants: Unknown alias ids are ignored; missing aliases retain canonical titles.
            % Materialization and performance: O(A) compact string metadata; no files/resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Malformed/absent aliases use defaults.
            % Side effects: None.
            % Consumers and dependencies: performanceTable.
            maxIndex=max([analyses.index 0]);aliases=repmat({''},1,maxIndex);
            for ii=1:numel(analyses),aliases{analyses(ii).index}=analyses(ii).title;end
            raw=[];
            % nm2-allow: analysisAliases rows are written by NMResultsViewerCrossAnalysis.js::aliasRows; absent keeps the analysis titles.
            if isfield(spec,'analysisAliases'),raw=spec.analysisAliases;end
            % nm2-allow: analysis alias rows are external presentation state validated at the public request boundary.
            if ~isstruct(raw),return;end
            for ii=1:numel(raw)
                idx=double(raw(ii).analysisIndex);
                alias=raw(ii).alias;
                % nm2-allow: analysis alias rows are bounded external presentation state; invalid rows leave canonical titles unchanged.
                if isfinite(idx)&&idx>=1&&idx<=numel(aliases)&&~isempty(strtrim(alias)),aliases{round(idx)}=strtrim(alias);end
            end
        end


        function [payloads,records,rows,materializedCount]=appendPerformancePayload(payloads,records,rows,materializedCount,payload,analysisIndex,analysisTitle,alias,resultType,source,targetLabel,modelSourceLabel,classifierLabel)
            % Purpose: Append one validated Model Performance context to cross-analysis scientific records and long-form rows.
            % Syntax: [payloads,records,rows,materializedCount] = ...appendPerformancePayload(...)
            % Inputs: Existing accumulators, one successful model-performance payload and explicit presentation labels for analysis/source/model/classifier.
            % Outputs: Updated payload list, Scientific Directory record list, long-form metric rows and context count.
            % Authority and flow: Requires payload.scientificAnnotation and payloadMetricRows; scientific identity is copied from the payload, while analysis/alias labels only decorate tabular rows.
            % Scientific/state contract: Every counted context has one authoritative Scientific Annotation and one opaque directory reference; no annotation is synthesized here.
            % Invariants: Context count increments only for payloads exposing non-empty canonical tabulation rows and valid annotation.
            % Materialization and performance: O(number of metric rows) compact struct append/copy; no files/XML/atlas/annotation/mesh loads, feature-scale scans or scientific recomputation.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Missing annotation/metric rows raises/returns according to payloadMetricRows/annotation validation; no substitution with display-oriented summary projections.
            % Side effects: Mutates only local accumulator values returned to caller.
            % Consumers and dependencies: performanceTable.
            NMResultsViewerScientificAnnotation.validate(payload.scientificAnnotation);
            materializedCount=materializedCount+1;
            payloads{end+1}=payload; %#ok<AGROW>
            records(end+1)=struct('reference',sprintf('performance_context_%d',materializedCount), ...
                'scientificAnnotation',payload.scientificAnnotation); %#ok<AGROW>
            metricRows=NMPerformanceMetricTools.canonicalRows(payload.performanceTabulationRows);
            for rr=1:numel(metricRows)
                rows(end+1)=NMResultsViewerCrossAnalysisTools.makeRow( ... %#ok<AGROW>
                    analysisIndex,analysisTitle,alias,resultType,source,targetLabel,modelSourceLabel,classifierLabel,metricRows(rr));
            end
        end

        function row=makeRow(analysisIndex,analysisTitle,alias,resultType,source,target,modelSource,classifier,metricRow)
            % Purpose: Combine one canonical metric row with explicit cross-analysis context columns.
            % Syntax: row = NMResultsViewerCrossAnalysisTools.makeRow(...,metricRow)
            % Inputs: Analysis/alias/task/source/target/model/classifier labels plus one canonical metric row.
            % Outputs: One fixed-schema long-form cross-analysis table row including deterministic metricId.
            % Authority and flow: Scientific metric value/source is copied from metricRow; context text comes from already-resolved selectors/catalogue.
            % Scientific/state contract: This row is a table projection, not Scientific Annotation; canonical scientific identity remains in the parallel annotation/state records.
            % Invariants: Metric value is not formatted/recomputed.
            % Materialization and performance: O(1) compact struct creation; no files/resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Caller is responsible for validated metricRow.
            % Side effects: None.
            % Consumers and dependencies: appendPerformancePayload.
            numericValue=double(metricRow.value);
            if ~isscalar(numericValue),numericValue=NaN;end
            row=NMResultsViewerCrossAnalysisTools.rowTemplate();
            row.analysisIndex=double(analysisIndex);row.analysis=analysisTitle;row.alias=alias;
            row.task=resultType;row.source=source;row.target=target;
            row.modelSource=modelSource;row.classifier=classifier;
            row.metricId=NMResultsViewerCrossAnalysisTools.metricId(metricRow.metric);row.metric=metricRow.metric;
            row.value=double(numericValue);row.numericValue=double(numericValue);row.metricSource=metricRow.source;
        end

        function options=metricOptions(rows)
            % Purpose: Build stable selectable metric options from long-form table rows.
            % Syntax: options = NMResultsViewerCrossAnalysisTools.metricOptions(rows)
            % Inputs: Long-form cross-analysis rows.
            % Outputs: Unique id/label/enabled options in first-occurrence order.
            % Authority and flow: Presentation selector derives only from metric ids/labels already present in canonical rows.
            % Scientific/state contract: Does not create or rename scientific metric values.
            % Invariants: One option per metricId.
            % Materialization and performance: O(number of rows) compact metadata; no resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Empty rows return empty options.
            % Side effects: None.
            % Consumers and dependencies: performanceTable/browser metric controls.
            tmpl=struct('id','','label','','enabled',true);options=tmpl([]);seen={};
            for ii=1:numel(rows)
                id=rows(ii).metricId;if any(strcmp(seen,id)),continue;end
                seen{end+1}=id; %#ok<AGROW>
                label=rows(ii).metric;
                if strcmp(label,'ECE'),label='Legacy ECE (model scores; equal-count bins)';end
                options(end+1)=struct('id',id,'label',label,'enabled',true); %#ok<AGROW>
            end
        end

        function ids=selectedMetricIds(options,spec)
            % Purpose: Normalize requested metric selection against available metric options.
            % Syntax: ids = NMResultsViewerCrossAnalysisTools.selectedMetricIds(options,spec)
            % Inputs: Available metric options and optional spec.metricIds/MetricIds.
            % Outputs: Valid selected metric id cell array; defaults to all available metrics.
            % Authority and flow: Selection only over materialized metric catalogue.
            % Scientific/state contract: Unavailable metric ids cannot become scientific values.
            % Invariants: Output order follows requested valid ids or catalogue order for default-all.
            % Materialization and performance: O(number of metrics); no resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Invalid requested ids are omitted; empty valid selection may produce an empty displayed/exported metric subset.
            % Side effects: None.
            % Consumers and dependencies: performanceTable.
            ids={options.id};raw=[];
            % nm2-allow: metricIds is written by NMResultsViewerCrossAnalysis.js only after a metric selection; absent keeps all metrics.
            if isfield(spec,'metricIds'),raw=spec.metricIds;end
            if isempty(raw),return;end
            % nm2-allow: performance metric ids are caller presentation tokens normalized once at the public request boundary.
            if ischar(raw)||isstring(raw),raw=cellstr(string(raw));elseif ~iscell(raw),raw=cellstr(string(raw));end
            % nm2-allow: performance metric ids are caller presentation tokens normalized once at the public request boundary.
            missing=raw(~ismember(string(raw),string(ids)));
            if ~isempty(missing)
                error('NMResultsViewerCrossAnalysisTools:NoMetricSelection', ...
                    'Unavailable Cross-analysis metric(s): %s. Available choices: %s.', ...
                    strjoin(unique(string(missing),'stable'),', '),strjoin(ids,', '));
            end
            requested=cellfun(@(x)char(string(x)),raw,'UniformOutput',false);
            ids=ids(ismember(ids,requested));
            if isempty(ids),error('NMResultsViewerCrossAnalysisTools:NoMetricSelection','None of the requested performance metrics is available.');end
        end

        function rows=filterMetricRows(rows,ids)
            % Purpose: Filter long-form cross-analysis rows by selected metric ids.
            % Syntax: rows = NMResultsViewerCrossAnalysisTools.filterMetricRows(rows,ids)
            % Inputs: Canonical long-form rows and selected metric ids.
            % Outputs: Subset retaining original row order.
            % Authority and flow: Presentation/export selection only; values are unchanged.
            % Scientific/state contract: Scientific contexts/annotations are not filtered/redefined by this helper.
            % Invariants: No row content mutation.
            % Materialization and performance: O(number of rows); compact logical filtering only.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Empty ids returns empty row set.
            % Side effects: None.
            % Consumers and dependencies: performanceTable.
            if isempty(rows)||isempty(ids),return;end
            keep=ismember({rows.metricId},ids);rows=rows(keep);
        end

        function cells=pivotTable(rows,options,ids)
            % Purpose: Convert selected long-form metric rows into a spreadsheet/report-friendly pivot table.
            % Syntax: cells = NMResultsViewerCrossAnalysisTools.pivotTable(rows,options,ids)
            % Inputs: Filtered rows, metric option catalogue and selected metric ids.
            % Outputs: Cell matrix with context columns followed by one column per selected metric.
            % Authority and flow: Pure reshaping of canonical rows; no metric calculation or Scientific State discovery.
            % Scientific/state contract: Context labels are presentation metadata; scientific annotation remains parallel in the payload.
            % Invariants: Cell values correspond to the same long-form row metric/context; selected metric order is preserved.
            % Materialization and performance: O(R+G×M) compact cell allocation for R rows, G contexts, M selected metrics; no files/resources or feature-scale arrays.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Empty rows/ids returns a header-only or empty table according to established implementation.
            % Side effects: None.
            % Consumers and dependencies: performanceTable and Report Builder spreadsheet/HTML rendering.
            labels=cell(1,numel(ids));for ii=1:numel(ids),hit=find(strcmp({options.id},ids{ii}),1);labels{ii}=options(hit).label;end
            header=[{'Analysis','Alias','Task','Source','Target','Model source','Classifier'} labels];
            cells=header;if isempty(rows),return;end
            contextKeys=cell(1,numel(rows));
            for ii=1:numel(rows)
                contextKeys{ii}=sprintf('%d|%s|%s|%s|%s|%s|%s',rows(ii).analysisIndex,rows(ii).analysis,rows(ii).alias,rows(ii).task,rows(ii).source,rows(ii).target,[rows(ii).modelSource '|' rows(ii).classifier]);
            end
            [~,firstIdx,groupIdx]=unique(contextKeys,'stable');
            nContexts=numel(firstIdx);cells=cell(nContexts+1,numel(header));cells(1,:)=header;
            for gg=1:nContexts
                pos=find(groupIdx==gg);r=rows(pos(1));cells(gg+1,1:7)={r.analysis,r.alias,r.task,r.source,r.target,r.modelSource,r.classifier};
                for mm=1:numel(ids)
                    localHit=find(strcmp({rows(pos).metricId},ids{mm}),1,'first');
                    if ~isempty(localHit),cells{gg+1,7+mm}=rows(pos(localHit)).numericValue;else,cells{gg+1,7+mm}='';end
                end
            end
            if any(cellfun(@isempty,{rows.target})),cells(:,5)=[];end
        end

        function id=metricId(label)
            % Purpose: Produce a deterministic selector-safe id from a metric label.
            % Syntax: id = NMResultsViewerCrossAnalysisTools.metricId(label)
            % Inputs: Metric label text from canonical tabulation rows.
            % Outputs: Normalized lowercase identifier.
            % Authority and flow: Identifier normalization only; scientific metric label remains stored separately.
            % Scientific/state contract: id is a UI/request key, not a metric definition.
            % Invariants: Same label maps deterministically to same id.
            % Materialization and performance: O(length(label)) string normalization; no resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Empty/nonalphanumeric label follows implementation normalization result.
            % Side effects: None.
            % Consumers and dependencies: makeRow/metricOptions.
            % nm2-allow: metricId is an explicit presentation-key normalization boundary.
            id=lower(regexprep(char(string(label)),'[^a-zA-Z0-9]+','_'));id=regexprep(id,'^_+|_+$','');
            if isempty(id),id='metric';end
        end


        function txt=specText(spec,names,defaultValue)
            % Purpose: Read the first non-empty text request field from a spec using an explicit name list.
            % Syntax: txt = NMResultsViewerCrossAnalysisTools.specText(spec,names,defaultValue)
            % Inputs: Request struct, allowed field names and default text.
            % Outputs: Normalized char text.
            % Authority and flow: Explicit request parsing only; no field-name search beyond supplied names.
            % Scientific/state contract: Does not infer scientific aliases.
            % Invariants: Only caller-declared field names are considered.
            % Materialization and performance: O(number of supplied names), metadata only.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: Missing/invalid fields return defaultValue.
            % Side effects: None.
            % Consumers and dependencies: workspace/performance request parsing.
            txt=defaultValue;
            % nm2-allow: public Cross-analysis request boundary normalizes explicitly declared text selectors only.
            if ~isstruct(spec),return;end
            for ii=1:numel(names),name=names{ii};
                % nm2-allow: public Cross-analysis request boundary accepts only aliases named by its caller.
                if isfield(spec,name)&&~isempty(spec.(name)),txt=char(string(spec.(name)));return;end
            end
        end


        function row=rowTemplate()
            % Purpose: Return the fixed schema for long-form cross-analysis performance rows.
            % Syntax: row = NMResultsViewerCrossAnalysisTools.rowTemplate()
            % Inputs: None.
            % Outputs: Fixed analysis/alias/task/source/target/modelSource/classifier/metricId/metric/value/valueText/metricSource schema.
            % Authority and flow: Schema helper only; values are populated from Model Performance payloads.
            % Scientific/state contract: Row schema is tabular projection and does not replace parallel Scientific Annotation/State.
            % Invariants: Field names remain stable for browser and Report Builder consumers.
            % Materialization and performance: Constant-size metadata allocation; no resources.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact metadata/table work only and safe on the documented Cross-analysis interactive path.
            % Failure semantics: None.
            % Side effects: None.
            % Consumers and dependencies: workspacePayload/performanceTable and row builders.
            row=struct('analysisIndex',NaN,'analysis','','alias','','task','','source','','target','', ...
                'modelSource','','classifier','','metricId','','metric','','value',NaN,'numericValue',NaN,'metricSource','');
        end
    end
end

classdef NMResultsViewerFeatureGraphTools
% NMResultsViewerFeatureGraphTools  Build deterministic feature-relation graphs and robustness diagnostics.
%
% Purpose:
%   This class is the authoritative, read-only backend for graph-based Model
%   Feature Inspection. It converts one normalized feature-relation matrix and
%   one stable feature subset into a fixed-schema graph contract consumed by the
%   browser, report generator, export layer, tests, and the planned RAG-guided
%   NM assistant. No method mutates NM, VIS results, matrix payloads, or caller
%   request structs.
%
% Scientific pipeline:
%   1. Validate the requested physical relation layer and stable feature IDs.
%   2. Apply one explicit graph-pruning rule: legacy strongest-edge union,
%      deterministic fixed density, or absolute threshold on the selected layer.
%   3. Attach aligned correlation, mean -log10(P), and mean -log10(q) evidence
%      to every retained edge without changing the edge universe.
%   4. Compute connected components, deterministic layout coordinates, and
%      toolbox-independent graph statistics. Weighted paths use
%      1/(abs(correlation)+1e-12); centralities therefore describe graph topology
%      and are not predictive feature-importance measures.
%   5. When enabled, derive hierarchical link communities from the final pruned
%      edge set. Pattern IDs are local to that exact graph identity; they are not
%      stable across edge-selection changes. Empty or sub-minimum communities are
%      never exposed as selectable relation patterns.
%   6. Optionally assess sparsification robustness across a deterministic density
%      grid. The analysis holds the matrix, feature universe, secondary filter,
%      and statistic definitions fixed; it selects the sparsest graph in the
%      longest eligible stability plateau and never forces a solution.
%
% Public contracts:
%   graphRequestTemplate, graphTemplate, nodeTemplate, edgeTemplate, and the
%   robustness templates define normalized fixed-schema payloads. buildGraphContract
%   and identifyRobustStructure are the main API-facing computations.
%
% Invariants and mutability boundaries:
%   - Feature identities are stable source indices/IDs, never display positions.
%   - Invalid, diagonal, non-finite, and zero-valued relation cells never become edges.
%   - Feature-level filtering is upstream and is never replaced by edge filtering.
%   - Relation patterns are recomputed after every graph edge-universe change.
%   - Correlation evidence is required for weighted graph statistics; no selected-
%     layer fallback silently substitutes for missing correlation.
%   - All ordering, tie resolution, layouts, cluster numbering, and cache identities
%     are deterministic for identical inputs.
%
% Errors and diagnostics:
%   Public builders return explicit availability/disabledReason fields and
%   structured diagnostics. Caught exceptions retain the MATLAB identifier,
%   message, and up to three stack frames; failures are not silently ignored.
%
% Dependencies:
%   Base MATLAB only. Statistics and Machine Learning Toolbox graph/clustering
%   functions are intentionally not required.
%
% RAG extraction notes:
%   Method-level blocks use the normalized sections Syntax, Inputs, Outputs,
%   Scientific contract, Invariants and mutability, Errors and diagnostics, and
%   Side effects so documentation extractors can index each callable operation.

    methods (Static)
        function request = graphRequestTemplate()
            % graphRequestTemplate  Create the normalized graph-construction request schema.
            %
            % Syntax:
            %   request = NMResultsViewerFeatureGraphTools.graphRequestTemplate()
            %
            % Outputs:
            %   request  Scalar struct containing sourceLayerId, edgeSelectionMode,
            %            pruning parameters, and relation-pattern parameters.
            %
            % Scientific contract:
            %   Defaults reproduce the accepted strongest-edge-union graph and automatic
            %   hierarchical link-community extraction.
            %
            % Invariants and mutability:
            %   Returns a new value; no caller state is read or mutated.
            %
            % Errors and diagnostics:
            %   None. Public relation-view state is normalized upstream before this schema is populated.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'schemaVersion',1, ...
                'graphContractVersion','C17g.1', ...
                'sourceLayerId','feature_correlation', ...
                'edgeSelectionMode','legacy_topk_union', ...
                'kPerNode',5, ...
                'maxGlobal',250, ...
                'targetDensity',0.10, ...
                'absoluteThreshold',0.30, ...
                'relationPatternEnabled',true, ...
                'relationPatternMethod','hierarchical_link_communities', ...
                'relationPatternCutMode','max_partition_density', ...
                'relationPatternSimilarityThreshold',0.5, ...
                'relationPatternMinEdges',2);
            request=tmpl;
        end

        function node = nodeTemplate()
            % nodeTemplate  Create one fixed-schema feature-graph node row.
            %
            % Syntax:
            %   node = NMResultsViewerFeatureGraphTools.nodeTemplate()
            %
            % Outputs:
            %   node  Scalar struct containing stable identity, topology, weighted
            %         statistics, ranks, component membership, layout, and pattern membership.
            %
            % Invariants and mutability:
            %   The template contains no inferred values and never mutates graph state.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'nodeId','', ...
                'featureId','', ...
                'featureIndex',0, ...
                'label','', ...
                'degree',0, ...
                'degreeRank',0, ...
                'absoluteStrength',NaN, ...
                'positiveStrength',NaN, ...
                'negativeStrength',NaN, ...
                'absoluteStrengthRank',0, ...
                'betweennessCentrality',NaN, ...
                'betweennessRank',0, ...
                'harmonicCloseness',NaN, ...
                'harmonicClosenessRank',0, ...
                'eigenvectorCentrality',NaN, ...
                'eigenvectorRank',0, ...
                'connectedComponentId',0, ...
                'componentSize',0, ...
                'layoutX',NaN, ...
                'layoutY',NaN, ...
                'relationClusterIds',[]);
            node=tmpl;
        end

        function edge = edgeTemplate()
            % edgeTemplate  Create one fixed-schema undirected graph-edge row.
            %
            % Syntax:
            %   edge = NMResultsViewerFeatureGraphTools.edgeTemplate()
            %
            % Outputs:
            %   edge  Scalar struct containing stable endpoint identities, selected-
            %         layer weight, aligned evidence values, pruning provenance, and pattern ID.
            %
            % Invariants and mutability:
            %   Endpoint ordering is materialized later from stable feature indices.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'edgeId','', ...
                'sourceNodeId','', ...
                'targetNodeId','', ...
                'sourceFeatureId','', ...
                'targetFeatureId','', ...
                'sourceFeatureIndex',0, ...
                'targetFeatureIndex',0, ...
                'sourceLocalIndex',0, ...
                'targetLocalIndex',0, ...
                'weight',NaN, ...
                'magnitude',NaN, ...
                'sign',0, ...
                'correlation',NaN, ...
                'meanLog10P',NaN, ...
                'meanLog10FdrQ',NaN, ...
                'selectedByPerNode',false, ...
                'selectedByGlobal',false, ...
                'selectedByDensity',false, ...
                'selectedByThreshold',false, ...
                'relationClusterId',0);
            edge=tmpl;
        end

        function summary = relationClusterSummaryTemplate()
            % relationClusterSummaryTemplate  Create one fixed-schema relation-pattern summary row.
            %
            % Syntax:
            %   summary = NMResultsViewerFeatureGraphTools.relationClusterSummaryTemplate()
            %
            % Outputs:
            %   summary  Scalar struct describing one retained edge community.
            %
            % Invariants and mutability:
            %   A materialized summary refers only to edges present in the final pruned graph.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'relationClusterId',0, ...
                'edgeCount',0, ...
                'nodeCount',0, ...
                'singletonEdge',false, ...
                'featureIndices',[], ...
                'featureIds',{{}}, ...
                'labels',{{}}, ...
                'positiveEdgeCount',0, ...
                'negativeEdgeCount',0, ...
                'meanAbsoluteWeight',NaN, ...
                'totalAbsoluteWeight',NaN);
            summary=tmpl;
        end

        function graph = graphTemplate()
            % graphTemplate  Create the canonical fixed-schema feature-graph payload.
            %
            % Syntax:
            %   graph = NMResultsViewerFeatureGraphTools.graphTemplate()
            %
            % Outputs:
            %   graph  Scalar struct containing graph identity, pruning metadata,
            %          nodes, edges, statistics, relation patterns, availability, and diagnostics.
            %
            % Invariants and mutability:
            %   The schema separates requested settings, realized graph properties, scientific
            %   identity, and presentation-independent data.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'schemaVersion',1, ...
                'graphContractVersion','C17g.1', ...
                'graphId','', ...
                'contextId','', ...
                'matrixId','', ...
                'componentApplicability','invariant', ...
                'componentSelectionAffectsContent',false, ...
                'sourceLayerId','feature_correlation', ...
                'sourceLayerLabel','Feature correlation', ...
                'sourceField','CorrMat_CV2', ...
                'valuePolarity','signed', ...
                'selectedFeatureIndices',[], ...
                'featureIds',{{}}, ...
                'labels',{{}}, ...
                'edgeSelectionMode','legacy_topk_union', ...
                'kPerNode',5, ...
                'maxGlobal',250, ...
                'targetDensity',NaN, ...
                'absoluteThreshold',NaN, ...
                'requestedEdgeCount',NaN, ...
                'candidateEdgeCount',0, ...
                'candidateDensity',NaN, ...
                'realizedEdgeCount',0, ...
                'realizedDensity',NaN, ...
                'selectionClamped',false, ...
                'selectionSummary','', ...
                'nodeRows',repmat(NMResultsViewerFeatureGraphTools.nodeTemplate(),1,0), ...
                'edgeRows',repmat(NMResultsViewerFeatureGraphTools.edgeTemplate(),1,0), ...
                'nodeCount',0, ...
                'edgeCount',0, ...
                'possibleEdgeCount',0, ...
                'graphDensity',NaN, ...
                'connectedComponentCount',0, ...
                'isolatedNodeCount',0, ...
                'graphStatisticsVersion','C17g.1', ...
                'graphStatisticsAvailable',false, ...
                'graphStatisticsDisabledReason','', ...
                'graphStatisticsAffinity','absolute_correlation', ...
                'graphStatisticsPathLengthTransform','1/(abs(correlation)+epsilon)', ...
                'graphStatisticsPathLengthEpsilon',1e-12, ...
                'graphStatisticsNormalization','betweenness global [0,1]; harmonic closeness divided by n-1; eigenvector L2 norm 1', ...
                'layoutAlgorithm','deterministic_fr_backend', ...
                'layoutCoordinateSystem','normalized_0_1', ...
                'layoutDeterministic',true, ...
                'relationPatternRequested',false, ...
                'relationPatternApplied',false, ...
                'relationPatternMethod','hierarchical_link_communities', ...
                'relationPatternCutMode','max_partition_density', ...
                'relationPatternSimilarityThresholdRequested',NaN, ...
                'relationPatternSimilarityThresholdResolved',NaN, ...
                'relationPatternPartitionDensity',NaN, ...
                'relationPatternClusterCount',0, ...
                'relationPatternUnclusteredEdgeCount',0, ...
                'relationPatternMinEdges',2, ...
                'relationPatternDisabledReason','', ...
                'relationClusterMatrix',[], ...
                'relationClusterSummaries',repmat(NMResultsViewerFeatureGraphTools.relationClusterSummaryTemplate(),1,0), ...
                'scientificStateIdentity','', ...
                'cacheIdentity','', ...
                'availabilityCode','not_evaluated', ...
                'available',false, ...
                'enabled',false, ...
                'disabledReason','');
            graph=tmpl;
        end

        function row = robustnessSettingTemplate()
            % robustnessSettingTemplate  Create one density-sensitivity result row.
            %
            % Syntax:
            %   row = NMResultsViewerFeatureGraphTools.robustnessSettingTemplate()
            %
            % Outputs:
            %   row  Scalar struct containing requested/realized density, connectivity,
            %        adjacent-setting concordance, eligibility, plateau, and selection flags.
            %
            % Invariants and mutability:
            %   Each row describes one distinct realizable fixed-density edge count.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'settingIndex',0, ...
                'requestedDensity',NaN, ...
                'targetEdgeCount',0, ...
                'realizedDensity',NaN, ...
                'edgeCount',0, ...
                'nodeCount',0, ...
                'connectedNodeCount',0, ...
                'connectedNodeFraction',NaN, ...
                'largestComponentSize',0, ...
                'largestComponentFraction',NaN, ...
                'componentCount',0, ...
                'isolatedNodeCount',0, ...
                'centralityConcordance',NaN, ...
                'topologySimilarity',NaN, ...
                'stabilityScore',NaN, ...
                'selectionClamped',false, ...
                'eligible',false, ...
                'stablePlateau',false, ...
                'selected',false, ...
                'available',false, ...
                'disabledReason','');
            row=tmpl;
        end

        function result = robustnessTemplate()
            % robustnessTemplate  Create the fixed-schema graph-sparsification robustness result.
            %
            % Syntax:
            %   result = NMResultsViewerFeatureGraphTools.robustnessTemplate()
            %
            % Outputs:
            %   result  Scalar struct containing the density grid, per-setting rows,
            %           explicit thresholds, plateau bounds, chosen setting, interpretation,
            %           and cache identity.
            %
            % Scientific contract:
            %   The default composite score is 0.75 centrality-rank concordance plus 0.25
            %   connected-topology similarity. Eligibility additionally requires adequate
            %   connected-node and largest-component fractions.
            %
            % Invariants and mutability:
            %   The template does not claim sampling reliability or statistical significance.
            %
            % Side effects:
            %   None.
            tmpl = struct( ...
                'schemaVersion',1, ...
                'robustnessContractVersion','C17h.1', ...
                'available',false, ...
                'enabled',false, ...
                'disabledReason','', ...
                'matrixId','', ...
                'contextId','', ...
                'sourceLayerId','feature_correlation', ...
                'sourceLayerLabel','Feature correlation', ...
                'selectedFeatureIndices',[], ...
                'densityGrid',[], ...
                'evaluatedSettingCount',0, ...
                'settingRows',repmat(NMResultsViewerFeatureGraphTools.robustnessSettingTemplate(),1,0), ...
                'stabilityThreshold',0.82, ...
                'minimumPlateauLength',3, ...
                'minimumConnectedNodeFraction',0.80, ...
                'minimumLargestComponentFraction',0.75, ...
                'stablePlateauStartDensity',NaN, ...
                'stablePlateauEndDensity',NaN, ...
                'selectedSettingIndex',0, ...
                'selectedDensity',NaN, ...
                'selectedRealizedDensity',NaN, ...
                'selectedEdgeCount',0, ...
                'selectedConnectedNodeFraction',NaN, ...
                'selectedLargestComponentFraction',NaN, ...
                'selectedComponentCount',0, ...
                'selectedStabilityScore',NaN, ...
                'selectionRule','Sparsest fixed-density graph within the longest stable plateau satisfying connectivity constraints', ...
                'compositeDefinition','0.75 centrality-rank concordance + 0.25 topology similarity across adjacent densities', ...
                'scientificInterpretation','Sensitivity to graph sparsification only; not sampling reliability, statistical significance, causality, or predictive feature importance', ...
                'cacheIdentity','');
            result=tmpl;
        end

        function [result,diagnostics] = identifyRobustStructure(matrix,selectedFeatureIndices,baseRequest,densityGrid)
            % identifyRobustStructure  Identify the sparsest graph in a reproducible density plateau.
            %
            % Syntax:
            %   [result,diagnostics] = NMResultsViewerFeatureGraphTools.identifyRobustStructure( ...
            %       matrix, selectedFeatureIndices, baseRequest, densityGrid)
            %
            % Inputs:
            %   matrix                  Normalized relation-matrix contract with full layer values.
            %   selectedFeatureIndices Stable one-based source feature indices after all upstream
            %                          feature-level filtering.
            %   baseRequest             Complete canonical graph request supplying the selected physical relation layer
            %                          and invariant graph-statistics contract. Current pruning and
            %                          relation-pattern settings do not determine the sensitivity grid.
            %   densityGrid             Optional vector in (0,1). Default:
            %                          [0.05 0.075 0.10 0.125 0.15 0.20 0.25 0.30].
            %
            % Outputs:
            %   result       Robustness contract. result.enabled is true only when a valid plateau
            %                is found; selectedDensity is the sparsest setting in that plateau.
            %   diagnostics  Structured diagnostics accumulated from graph construction.
            %
            % Scientific contract:
            %   The method holds the matrix, physical relation layer, feature universe, invalid-
            %   cell handling, and centrality definitions fixed. It rebuilds relation-pattern-free
            %   fixed-density graphs, compares each setting with its immediate neighbours using
            %   tie-aware concordance of degree, absolute strength, betweenness, harmonic
            %   closeness, and eigenvector centrality, and combines this with connected-topology
            %   similarity. Consecutive eligible settings form plateaus. The longest plateau wins;
            %   ties use mean stability then lower starting density. The selected representative
            %   is the sparsest setting in the winning plateau.
            %
            % Invariants and mutability:
            %   No graph control, matrix, or feature state is mutated. No setting is selected when
            %   fewer than three distinct edge counts are evaluable or no plateau meets all criteria.
            %
            % Errors and diagnostics:
            %   The request and matrix are canonical internal contracts. Graph-construction
            %   diagnostics are returned explicitly; malformed internal contracts fail directly.
            %
            % Side effects:
            %   None.
            result=NMResultsViewerFeatureGraphTools.robustnessTemplate();
            diagnostics=repmat(NMResultsViewerFeatureGraphTools.diagnosticTemplate(),1,0);
            if isempty(densityGrid)
                densityGrid=[0.05 0.075 0.10 0.125 0.15 0.20 0.25 0.30];
            end
            request=baseRequest;
            selected=double(selectedFeatureIndices(:)');
            selected=sort(unique(selected(isfinite(selected) & selected>=1 & selected==floor(selected))));
            result.matrixId=matrix.matrixId;
            result.contextId=matrix.contextId;
            result.sourceLayerId=request.sourceLayerId;
            result.selectedFeatureIndices=selected;
            n=numel(selected);
            possible=n*(n-1)/2;
            if n<5 || possible<10
                result.disabledReason='At least five admissible features and ten possible edges are required for graph-structure robustness analysis.';
                return;
            end
            grid=double(densityGrid(:)');
            grid=sort(unique(grid(isfinite(grid) & grid>0 & grid<1)));
            if isempty(grid)
                result.disabledReason='The graph-structure robustness density grid contains no valid values in (0,1).';
                return;
            end
            targetCounts=round(grid*possible);
            keep=false(size(grid)); seen=zeros(1,0);
            for ii=1:numel(grid)
                if targetCounts(ii)<1 || any(seen==targetCounts(ii)), continue; end
                keep(ii)=true; seen(end+1)=targetCounts(ii); %#ok<AGROW>
            end
            grid=grid(keep); targetCounts=targetCounts(keep);
            if numel(grid)<result.minimumPlateauLength
                result.disabledReason='The selected feature count yields fewer than three distinct fixed-density graph structures on the default sensitivity grid.';
                return;
            end
            result.densityGrid=grid;
            result.evaluatedSettingCount=numel(grid);
            rows=repmat(NMResultsViewerFeatureGraphTools.robustnessSettingTemplate(),1,numel(grid));
            graphs=cell(1,numel(grid));
            request.edgeSelectionMode='fixed_density';
            request.relationPatternEnabled=false;
            for ii=1:numel(grid)
                request.targetDensity=grid(ii);
                [graphs{ii},graphDiagnostics]=NMResultsViewerFeatureGraphTools.buildGraphContract(matrix,selected,request);
                diagnostics=[diagnostics graphDiagnostics]; %#ok<AGROW>
                graph=graphs{ii};
                if ii==1, result.sourceLayerLabel=graph.sourceLayerLabel; end
                row=NMResultsViewerFeatureGraphTools.robustnessSettingTemplate();
                row.settingIndex=ii;
                row.requestedDensity=grid(ii);
                row.targetEdgeCount=targetCounts(ii);
                row.realizedDensity=graph.realizedDensity;
                row.edgeCount=graph.edgeCount;
                row.nodeCount=graph.nodeCount;
                row.componentCount=graph.connectedComponentCount;
                row.isolatedNodeCount=graph.isolatedNodeCount;
                row.connectedNodeCount=max(0,n-graph.isolatedNodeCount);
                row.connectedNodeFraction=row.connectedNodeCount/max(1,n);
                componentSizes=[graph.nodeRows.componentSize];
                if isempty(componentSizes), row.largestComponentSize=0; else, row.largestComponentSize=max(componentSizes); end
                row.largestComponentFraction=row.largestComponentSize/max(1,n);
                row.selectionClamped=logical(graph.selectionClamped);
                row.available=logical(graph.available && graph.graphStatisticsAvailable);
                if ~row.available
                    if ~graph.available, row.disabledReason=graph.disabledReason;
                    else, row.disabledReason=graph.graphStatisticsDisabledReason; end
                end
                rows(ii)=row;
            end
            pairCentrality=nan(1,max(0,numel(grid)-1));
            pairTopology=nan(1,max(0,numel(grid)-1));
            for ii=1:numel(pairCentrality)
                if rows(ii).available && rows(ii+1).available
                    pairCentrality(ii)=NMResultsViewerFeatureGraphTools.graphCentralityConcordance(graphs{ii},graphs{ii+1});
                    pairTopology(ii)=NMResultsViewerFeatureGraphTools.graphTopologySimilarity(rows(ii),rows(ii+1),n);
                end
            end
            for ii=1:numel(rows)
                neighbourCentrality=[]; neighbourTopology=[];
                if ii>1
                    neighbourCentrality(end+1)=pairCentrality(ii-1); %#ok<AGROW>
                    neighbourTopology(end+1)=pairTopology(ii-1); %#ok<AGROW>
                end
                if ii<numel(rows)
                    neighbourCentrality(end+1)=pairCentrality(ii); %#ok<AGROW>
                    neighbourTopology(end+1)=pairTopology(ii); %#ok<AGROW>
                end
                rows(ii).centralityConcordance=NMResultsViewerFeatureGraphTools.finiteMean(neighbourCentrality);
                rows(ii).topologySimilarity=NMResultsViewerFeatureGraphTools.finiteMean(neighbourTopology);
                if isfinite(rows(ii).centralityConcordance) && isfinite(rows(ii).topologySimilarity)
                    rows(ii).stabilityScore=0.75*rows(ii).centralityConcordance+0.25*rows(ii).topologySimilarity;
                end
                rows(ii).eligible=rows(ii).available && ~rows(ii).selectionClamped && ...
                    rows(ii).stabilityScore>=result.stabilityThreshold && ...
                    rows(ii).connectedNodeFraction>=result.minimumConnectedNodeFraction && ...
                    rows(ii).largestComponentFraction>=result.minimumLargestComponentFraction;
            end
            [runStarts,runEnds]=NMResultsViewerFeatureGraphTools.trueRuns([rows.eligible]);
            validRuns=find((runEnds-runStarts+1)>=result.minimumPlateauLength);
            if isempty(validRuns)
                result.available=true;
                result.settingRows=rows;
                result.disabledReason='No stable graph-density plateau satisfied the centrality and connectivity criteria.';
                result.cacheIdentity=NMResultsViewerFeatureGraphTools.robustnessIdentity(result,request);
                return;
            end
            bestRun=validRuns(1); bestLength=-inf; bestScore=-inf; bestDensity=inf;
            for rr=validRuns(:)'
                idx=runStarts(rr):runEnds(rr);
                runLength=numel(idx);
                runScore=NMResultsViewerFeatureGraphTools.finiteMean([rows(idx).stabilityScore]);
                runDensity=rows(idx(1)).requestedDensity;
                if runLength>bestLength || (runLength==bestLength && runScore>bestScore+1e-12) || ...
                        (runLength==bestLength && abs(runScore-bestScore)<=1e-12 && runDensity<bestDensity)
                    bestRun=rr; bestLength=runLength; bestScore=runScore; bestDensity=runDensity;
                end
            end
            plateau=runStarts(bestRun):runEnds(bestRun);
            selectedIndex=plateau(1);
            for ii=plateau, rows(ii).stablePlateau=true; end
            rows(selectedIndex).selected=true;
            result.available=true;
            result.enabled=true;
            result.settingRows=rows;
            result.stablePlateauStartDensity=rows(plateau(1)).requestedDensity;
            result.stablePlateauEndDensity=rows(plateau(end)).requestedDensity;
            result.selectedSettingIndex=selectedIndex;
            result.selectedDensity=rows(selectedIndex).requestedDensity;
            result.selectedRealizedDensity=rows(selectedIndex).realizedDensity;
            result.selectedEdgeCount=rows(selectedIndex).edgeCount;
            result.selectedConnectedNodeFraction=rows(selectedIndex).connectedNodeFraction;
            result.selectedLargestComponentFraction=rows(selectedIndex).largestComponentFraction;
            result.selectedComponentCount=rows(selectedIndex).componentCount;
            result.selectedStabilityScore=rows(selectedIndex).stabilityScore;
            result.cacheIdentity=NMResultsViewerFeatureGraphTools.robustnessIdentity(result,request);
        end

        function score = graphCentralityConcordance(graphA,graphB)
            % graphCentralityConcordance  Average tie-aware rank concordance across canonical node metrics.
            %
            % Syntax:
            %   score = NMResultsViewerFeatureGraphTools.graphCentralityConcordance(graphA,graphB)
            %
            % Inputs:
            %   graphA, graphB  Graphs with identically ordered nodeRows.
            %
            % Outputs:
            %   score  Finite mean Spearman concordance across degree, absolute strength,
            %          betweenness, harmonic closeness, and eigenvector centrality.
            %
            % Invariants and mutability:
            %   Node identity/order must be identical; inputs are not mutated.
            %
            % Side effects:
            %   None.
            fields={'degree','absoluteStrength','betweennessCentrality','harmonicCloseness','eigenvectorCentrality'};
            values=nan(1,numel(fields));
            for ff=1:numel(fields)
                a=double([graphA.nodeRows.(fields{ff})]');
                b=double([graphB.nodeRows.(fields{ff})]');
                values(ff)=NMResultsViewerFeatureGraphTools.spearmanConcordance(a,b);
            end
            score=NMResultsViewerFeatureGraphTools.finiteMean(values);
        end

        function score = graphTopologySimilarity(rowA,rowB,n)
            % graphTopologySimilarity  Compare adjacent graph connectivity summaries on a [0,1] scale.
            %
            % Syntax:
            %   score = NMResultsViewerFeatureGraphTools.graphTopologySimilarity(rowA,rowB,n)
            %
            % Inputs:
            %   rowA, rowB  Robustness-setting rows.
            %   n           Fixed node count.
            %
            % Outputs:
            %   score  Mean similarity of connected-node fraction, largest-component fraction,
            %          and component count, clamped to [0,1].
            %
            % Side effects:
            %   None.
            connected=1-abs(rowA.connectedNodeFraction-rowB.connectedNodeFraction);
            largest=1-abs(rowA.largestComponentFraction-rowB.largestComponentFraction);
            components=1-abs(rowA.componentCount-rowB.componentCount)/max(1,n-1);
            score=max(0,min(1,mean([connected largest components])));
        end

        function score = spearmanConcordance(a,b)
            % spearmanConcordance  Compute toolbox-independent tie-aware Spearman concordance.
            %
            % Syntax:
            %   score = NMResultsViewerFeatureGraphTools.spearmanConcordance(a,b)
            %
            % Inputs:
            %   a, b  Numeric vectors; only pairwise finite entries are used.
            %
            % Outputs:
            %   score  Correlation in [-1,1], NaN for fewer than three finite pairs, 1 for
            %          equal constant vectors, and 0 when only one vector is constant.
            %
            % Invariants and mutability:
            %   Ties receive average ranks; inputs are not mutated.
            %
            % Side effects:
            %   None.
            a=double(a(:)); b=double(b(:)); mask=isfinite(a)&isfinite(b);
            a=a(mask); b=b(mask);
            if numel(a)<3, score=NaN; return; end
            ra=NMResultsViewerFeatureGraphTools.averageTiedRanks(a);
            rb=NMResultsViewerFeatureGraphTools.averageTiedRanks(b);
            da=ra-mean(ra); db=rb-mean(rb);
            sa=sqrt(sum(da.^2)); sb=sqrt(sum(db.^2));
            if sa<=1e-14 && sb<=1e-14
                scale=max(1,max(abs([a;b])));
                if max(abs(a-b))<=1e-12*scale, score=1; else, score=0; end
                return;
            end
            if sa<=1e-14 || sb<=1e-14, score=0; return; end
            score=max(-1,min(1,sum(da.*db)/(sa*sb)));
        end

        function ranks = averageTiedRanks(values)
            % averageTiedRanks  Assign deterministic average ascending ranks.
            %
            % Syntax:
            %   ranks = NMResultsViewerFeatureGraphTools.averageTiedRanks(values)
            %
            % Inputs:
            %   values  Finite numeric vector.
            %
            % Outputs:
            %   ranks   Column vector of average ranks; values within a scale-relative 1e-12
            %           tolerance are treated as tied.
            %
            % Side effects:
            %   None.
            values=double(values(:)); n=numel(values); ranks=nan(n,1);
            [sorted,order]=sort(values,'ascend');
            scale=max(1,max(abs(sorted))); tolerance=1e-12*scale;
            first=1;
            while first<=n
                last=first;
                while last<n && abs(sorted(last+1)-sorted(first))<=tolerance, last=last+1; end
                ranks(order(first:last))=(first+last)/2;
                first=last+1;
            end
        end

        function value = finiteMean(values)
            % finiteMean  Return the arithmetic mean of finite values only.
            %
            % Syntax:
            %   value = NMResultsViewerFeatureGraphTools.finiteMean(values)
            %
            % Outputs:
            %   value  Scalar mean, or NaN when no finite value exists.
            %
            % Side effects:
            %   None.
            values=double(values(:)); values=values(isfinite(values));
            if isempty(values), value=NaN; else, value=sum(values)/numel(values); end
        end

        function [starts,ends] = trueRuns(mask)
            % trueRuns  Locate inclusive contiguous runs of true values.
            %
            % Syntax:
            %   [starts,ends] = NMResultsViewerFeatureGraphTools.trueRuns(mask)
            %
            % Outputs:
            %   starts, ends  Row vectors of one-based inclusive run boundaries.
            %
            % Side effects:
            %   None.
            mask=logical(mask(:)'); padded=[false mask false]; delta=diff(double(padded));
            starts=find(delta==1); ends=find(delta==-1)-1;
        end

        function identity = robustnessIdentity(result,request)
            % robustnessIdentity  Build the deterministic cache identity for one sensitivity problem.
            %
            % Syntax:
            %   identity = NMResultsViewerFeatureGraphTools.robustnessIdentity(result,request)
            %
            % Scientific contract:
            %   The token includes matrix ID, selected relation layer, stable feature IDs,
            %   density grid, and all selection thresholds; presentation state is excluded.
            %
            % Outputs:
            %   identity  Stable feature_graph_robustness_* text key.
            %
            % Side effects:
            %   None.
            selected=sprintf('%d,',result.selectedFeatureIndices);
            grid=sprintf('%.8g,',result.densityGrid);
            token=sprintf('C17h.1|%s|%s|%s|%s|%.4g|%d|%.4g|%.4g', ...
                result.matrixId,request.sourceLayerId,selected,grid,result.stabilityThreshold, ...
                result.minimumPlateauLength,result.minimumConnectedNodeFraction,result.minimumLargestComponentFraction);
            identity=sprintf('feature_graph_robustness_%08x',NMResultsViewerFeatureGraphTools.textChecksum(token));
        end

        function [graph,diagnostics] = buildGraphContract(matrix,selectedFeatureIndices,request)
            % buildGraphContract  Build the canonical pruned graph, statistics, and relation patterns.
            %
            % Syntax:
            %   [graph,diagnostics] = NMResultsViewerFeatureGraphTools.buildGraphContract( ...
            %       matrix, selectedFeatureIndices, request)
            %
            % Inputs:
            %   matrix                  Full normalized feature-relation matrix contract.
            %   selectedFeatureIndices Stable one-based feature subset after upstream filtering.
            %   request                 Complete canonical graphRequestTemplate-derived request.
            %
            % Outputs:
            %   graph        Canonical graph payload with explicit availability and realized-
            %                selection metadata.
            %   diagnostics  Structured error/warning diagnostics.
            %
            % Scientific contract:
            %   Edge selection is performed on request.sourceLayerId. Every retained edge then
            %   receives aligned correlation, P-evidence, and q-evidence values. Components and
            %   statistics are computed from those retained edges. When enabled, relation patterns
            %   are hierarchical link communities of this same final pruned edge set; there is no
            %   independent or stale pattern graph. Pattern summaries and node memberships therefore
            %   cannot refer to absent edges or nodes.
            %
            % Invariants and mutability:
            %   Stable source feature IDs determine node/edge identity. The matrix, request, and
            %   selected-feature vector are not mutated. Empty graphs remain explicit contracts.
            %
            % Errors and diagnostics:
            %   Unavailable layers and dimension mismatches produce explicit disabledReason/diagnostics.
            %   Malformed canonical requests fail directly. Pattern failure is diagnosed without
            %   changing the graph edge universe.
            %
            % Side effects:
            %   None.
            graph=NMResultsViewerFeatureGraphTools.graphTemplate();
            diagnostics=repmat(NMResultsViewerFeatureGraphTools.diagnosticTemplate(),1,0);
            graph=NMResultsViewerFeatureGraphTools.populateIdentity(graph,matrix,request);
            if ~matrix.available
                graph.availabilityCode='base_relation_unavailable';
                graph.disabledReason=matrix.disabledReason;
                return;
            end
            selected=double(selectedFeatureIndices(:)');
            selected=sort(unique(selected(isfinite(selected) & selected>=1 & selected==floor(selected))));
            nAll=matrix.nRows;
            if isempty(selected)
                graph.availabilityCode='empty_feature_subset';
                graph.available=true;
                graph.disabledReason='No admissible features are available for graph construction.';
                return;
            end
            if any(selected>nAll)
                graph.availabilityCode='feature_index_out_of_range';
                graph.disabledReason=sprintf('Graph feature indices exceed the %d-feature relation context.',nAll);
                diagnostics=NMResultsViewerFeatureGraphTools.diagnostic('error','feature_graph_index_range', ...
                    graph.disabledReason,graph.sourceField,graph.contextId,'buildGraphContract','','');
                return;
            end
            layerIndex=find(strcmp({matrix.layers.layerId},request.sourceLayerId),1,'first');
            if isempty(layerIndex) || ~matrix.layers(layerIndex).available
                graph.availabilityCode='graph_source_layer_unavailable';
                graph.disabledReason=sprintf('Graph construction requires the authoritative relation layer "%s".',request.sourceLayerId);
                return;
            end
            sourceLayer=matrix.layers(layerIndex);
            graph.sourceLayerId=sourceLayer.layerId;
            graph.sourceLayerLabel=sourceLayer.label;
            graph.sourceField=sourceLayer.sourceField;
            graph.valuePolarity=sourceLayer.valuePolarity;
            values=NMResultsViewerFeatureGraphTools.matrixFromRows(sourceLayer.values);
            validity=NMResultsViewerFeatureGraphTools.logicalMatrixFromRows(sourceLayer.validityMask);
            if size(values,1)<max(selected) || size(values,2)<max(selected)
                graph.availabilityCode='graph_source_dimension_mismatch';
                graph.disabledReason=sprintf('The authoritative %s layer does not cover all selected stable feature indices.',graph.sourceLayerLabel);
                diagnostics=NMResultsViewerFeatureGraphTools.diagnostic('error','feature_graph_dimension_mismatch', ...
                    graph.disabledReason,graph.sourceField,graph.contextId,'buildGraphContract','','');
                return;
            end
            subValues=double(values(selected,selected));
            subValidity=logical(validity(selected,selected)) & isfinite(subValues);
            n=numel(selected);
            graph.selectedFeatureIndices=selected;
            graph.featureIds=matrix.featureIds(selected);
            graph.labels=matrix.labels(selected);
            graph.nodeCount=n;
            graph.possibleEdgeCount=n*(n-1)/2;
            [edges,keepMatrix,selectionInfo]=NMResultsViewerFeatureGraphTools.selectGraphEdges( ...
                subValues,subValidity,selected,graph.featureIds,request);
            graph.edgeRows=NMResultsViewerFeatureGraphTools.attachPairwiseEvidence(matrix,selected,edges);
            graph.edgeCount=numel(graph.edgeRows);
            graph.requestedEdgeCount=selectionInfo.requestedEdgeCount;
            graph.candidateEdgeCount=selectionInfo.candidateEdgeCount;
            graph.candidateDensity=selectionInfo.candidateDensity;
            graph.realizedEdgeCount=graph.edgeCount;
            graph.realizedDensity=selectionInfo.realizedDensity;
            graph.selectionClamped=selectionInfo.selectionClamped;
            graph.selectionSummary=selectionInfo.summary;
            graph.graphDensity=graph.realizedDensity;
            [componentIds,componentCount]=NMResultsViewerFeatureGraphTools.connectedComponents(n,graph.edgeRows);
            graph.connectedComponentCount=componentCount;
            graph.nodeRows=NMResultsViewerFeatureGraphTools.buildNodeRows( ...
                selected,graph.featureIds,graph.labels,graph.edgeRows,componentIds);
            graph.isolatedNodeCount=nnz([graph.nodeRows.degree]==0);
            graph.available=true;
            if isempty(edges)
                [graph.nodeRows,statisticsInfo]=NMResultsViewerFeatureGraphTools.computeGraphStatistics( ...
                    graph.nodeRows,graph.edgeRows,graph.graphStatisticsPathLengthEpsilon);
                graph.graphStatisticsAvailable=statisticsInfo.available;
                graph.graphStatisticsDisabledReason=statisticsInfo.disabledReason;
                graph.nodeRows=NMResultsViewerFeatureGraphTools.assignNodeRanksAndLayout(graph.nodeRows,graph.edgeRows);
                graph.availabilityCode='empty_graph';
                graph.enabled=false;
                graph.disabledReason=sprintf('No valid non-zero edges from %s satisfy the %s graph-construction rule.',graph.sourceLayerLabel,strrep(graph.edgeSelectionMode,'_',' '));
                graph.relationClusterMatrix=NMResultsViewerFeatureGraphTools.numericMatrixRows(zeros(n));
                graph=NMResultsViewerFeatureGraphTools.assignIdentity(graph,request);
                return;
            end
            graph.availabilityCode='available';
            graph.enabled=true;
            graph.disabledReason='';
            graph.relationPatternRequested=request.relationPatternEnabled;
            graph.relationPatternSimilarityThresholdRequested=request.relationPatternSimilarityThreshold;
            graph.relationPatternMinEdges=request.relationPatternMinEdges;
            if request.relationPatternEnabled
                try
                    [edgeClusterIds,clusterInfo]=NMResultsViewerFeatureGraphTools.linkCommunities( ...
                        n,edges,request.relationPatternCutMode,request.relationPatternSimilarityThreshold, ...
                        request.relationPatternMinEdges);
                    graph.relationPatternApplied=clusterInfo.applied;
                    graph.relationPatternSimilarityThresholdResolved=clusterInfo.threshold;
                    graph.relationPatternPartitionDensity=clusterInfo.partitionDensity;
                    graph.relationPatternClusterCount=clusterInfo.clusterCount;
                    graph.relationPatternUnclusteredEdgeCount=clusterInfo.unclusteredEdgeCount;
                    graph.relationClusterMatrix=NMResultsViewerFeatureGraphTools.numericMatrixRows( ...
                        NMResultsViewerFeatureGraphTools.edgeClusterMatrix(n,edges,edgeClusterIds));
                    if ~isempty(edges)
                        for ee=1:numel(edges), graph.edgeRows(ee).relationClusterId=edgeClusterIds(ee); end
                    end
                    graph.relationClusterSummaries=NMResultsViewerFeatureGraphTools.clusterSummaries( ...
                        graph.edgeRows,selected,graph.featureIds,graph.labels);
                    graph.nodeRows=NMResultsViewerFeatureGraphTools.assignNodeRelationClusters( ...
                        graph.nodeRows,graph.edgeRows);
                    if ~clusterInfo.applied
                        graph.relationPatternDisabledReason=clusterInfo.disabledReason;
                    end
                catch ME
                    graph.relationPatternApplied=false;
                    graph.relationClusterMatrix=NMResultsViewerFeatureGraphTools.numericMatrixRows(zeros(n));
                    graph.relationPatternDisabledReason=sprintf('%s: %s',ME.identifier,ME.message);
                    diagnostics=NMResultsViewerFeatureGraphTools.diagnosticFromException( ...
                        'feature_relation_pattern_clustering',ME,graph.contextId);
                end
            else
                graph.relationClusterMatrix=NMResultsViewerFeatureGraphTools.numericMatrixRows(zeros(n));
            end
            [graph.nodeRows,statisticsInfo]=NMResultsViewerFeatureGraphTools.computeGraphStatistics( ...
                graph.nodeRows,graph.edgeRows,graph.graphStatisticsPathLengthEpsilon);
            graph.graphStatisticsAvailable=statisticsInfo.available;
            graph.graphStatisticsDisabledReason=statisticsInfo.disabledReason;
            graph.nodeRows=NMResultsViewerFeatureGraphTools.assignNodeRanksAndLayout(graph.nodeRows,graph.edgeRows);
            %#ok<NASGU> keepMatrix retained locally to make the selection semantics explicit.
            graph=NMResultsViewerFeatureGraphTools.assignIdentity(graph,request);
        end

        function slice = displayRelationClusterSlice(graph,displayFeatureIndices)
            % displayRelationClusterSlice  Project canonical relation patterns onto one displayed page.
            %
            % Syntax:
            %   slice = NMResultsViewerFeatureGraphTools.displayRelationClusterSlice(graph,displayFeatureIndices)
            %
            % Inputs:
            %   graph                  Canonical graph whose patterns derive from its retained edges.
            %   displayFeatureIndices Stable feature indices shown on the current matrix page.
            %
            % Outputs:
            %   slice  Cluster-ID matrix, retained-edge mask, partial-pattern IDs, availability,
            %          and disabledReason.
            %
            % Invariants and mutability:
            %   Projection never invents edges and requires exact stable-index mapping.
            %
            % Side effects:
            %   None.
            slice=struct('clusterIds',[],'selectedEdgeMask',[],'partialClusterIds',[], ...
                'available',false,'disabledReason','');
            if ~graph.available
                slice.disabledReason='The canonical graph contract is unavailable.';
                return;
            end
            display=double(displayFeatureIndices(:)');
            selected=double(graph.selectedFeatureIndices(:)');
            [tf,loc]=ismember(display,selected);
            if ~all(tf)
                slice.disabledReason='Displayed features do not map exactly to the canonical graph feature identities.';
                return;
            end
            clusterMatrix=NMResultsViewerFeatureGraphTools.matrixFromRows(graph.relationClusterMatrix);
            if isempty(clusterMatrix), clusterMatrix=zeros(numel(selected)); end
            slice.clusterIds=NMResultsViewerFeatureGraphTools.numericMatrixRows(clusterMatrix(loc,loc));
            edgeMask=false(numel(display));
            for ee=1:numel(graph.edgeRows)
                r=find(display==graph.edgeRows(ee).sourceFeatureIndex,1,'first');
                c=find(display==graph.edgeRows(ee).targetFeatureIndex,1,'first');
                if isempty(r) || isempty(c), continue; end
                edgeMask(r,c)=true; edgeMask(c,r)=true;
            end
            slice.selectedEdgeMask=NMResultsViewerFeatureGraphTools.logicalMatrixRows(edgeMask);
            visibleClusterIds=unique(clusterMatrix(loc,loc));
            visibleClusterIds=double(visibleClusterIds(visibleClusterIds>0));
            partial=zeros(1,0);
            for cc=1:numel(visibleClusterIds)
                clusterId=visibleClusterIds(cc);
                globalCount=nnz([graph.edgeRows.relationClusterId]==clusterId);
                visibleCount=0;
                for ee=1:numel(graph.edgeRows)
                    if graph.edgeRows(ee).relationClusterId~=clusterId, continue; end
                    if any(display==graph.edgeRows(ee).sourceFeatureIndex) && ...
                            any(display==graph.edgeRows(ee).targetFeatureIndex)
                        visibleCount=visibleCount+1;
                    end
                end
                if visibleCount<globalCount, partial(end+1)=clusterId; end %#ok<AGROW>
            end
            slice.partialClusterIds=partial;
            slice.available=true;
        end

        function [edges,keepMatrix,info] = selectGraphEdges(values,validity,featureIndices,featureIds,request)
            % selectGraphEdges  Apply one explicit pruning rule to an admissible relation submatrix.
            %
            % Syntax:
            %   [edges,keepMatrix,info] = NMResultsViewerFeatureGraphTools.selectGraphEdges( ...
            %       values,validity,featureIndices,featureIds,request)
            %
            % Inputs:
            %   values, validity      Equally sized square selected-layer matrices.
            %   featureIndices/Ids    Stable one-to-one row identities.
            %   request               Complete canonical graphRequestTemplate-derived request.
            %
            % Outputs:
            %   edges       Stable canonical edge rows.
            %   keepMatrix  Symmetric logical retained-edge mask.
            %   info        Requested/realized edge counts, density, clamping, and summary.
            %
            % Scientific contract:
            %   Supports legacy_topk_union, fixed_density, and absolute_threshold only. Feature-
            %   level filtering is not performed here.
            %
            % Errors and diagnostics:
            %   Shape and identity mismatches raise explicit NMResultsViewerFeatureGraphTools errors.
            %
            % Side effects:
            %   None.
            values=double(values);
            validity=logical(validity);
            n=size(values,1);
            if size(values,2)~=n || ~isequal(size(validity),[n n])
                error('NMResultsViewerFeatureGraphTools:graphMatrixShape', ...
                    'Graph values and validity masks must be equally sized square matrices.');
            end
            featureIndices=double(featureIndices(:)');
            if numel(featureIndices)~=n || numel(featureIds)~=n
                error('NMResultsViewerFeatureGraphTools:graphFeatureIdentityShape', ...
                    'Graph feature identities must align one-to-one with the matrix rows.');
            end
            candidateMask=triu(validity & isfinite(values) & values~=0,1);
            possible=n*(n-1)/2;
            candidateCount=nnz(candidateMask);
            info=struct('mode',request.edgeSelectionMode,'requestedEdgeCount',NaN, ...
                'candidateEdgeCount',candidateCount,'candidateDensity',NaN, ...
                'realizedEdgeCount',0,'realizedDensity',NaN,'selectionClamped',false, ...
                'summary','');
            if possible>0, info.candidateDensity=candidateCount/possible; end
            switch request.edgeSelectionMode
                case 'legacy_topk_union'
                    [edges,keepMatrix]=NMResultsViewerFeatureGraphTools.legacyTopKUnion( ...
                        values,validity,featureIndices,featureIds,request.kPerNode,request.maxGlobal,request.sourceLayerId);
                    info.summary=sprintf('Legacy union: %d strongest incident edge(s) per feature plus %d strongest edge(s) globally.', ...
                        request.kPerNode,request.maxGlobal);
                case 'fixed_density'
                    requestedCount=round(request.targetDensity*possible);
                    info.requestedEdgeCount=requestedCount;
                    keepCount=min(candidateCount,max(0,requestedCount));
                    info.selectionClamped=keepCount~=requestedCount;
                    [edges,keepMatrix]=NMResultsViewerFeatureGraphTools.selectRankedCandidateEdges( ...
                        values,candidateMask,featureIndices,featureIds,keepCount,request.sourceLayerId,'density');
                    info.summary=sprintf('Fixed density %.4g requested %d edge(s); %d candidate edge(s) were available.', ...
                        request.targetDensity,requestedCount,candidateCount);
                case 'absolute_threshold'
                    thresholdMask=candidateMask & abs(values)>=request.absoluteThreshold;
                    [edges,keepMatrix]=NMResultsViewerFeatureGraphTools.selectMaskedEdges( ...
                        values,thresholdMask,featureIndices,featureIds,request.sourceLayerId,'threshold');
                    info.summary=sprintf('Absolute primary-metric threshold |value| >= %.4g selected from %d candidate edge(s).', ...
                        request.absoluteThreshold,candidateCount);
                otherwise
                    error('NMResultsViewerFeatureGraphTools:edgeSelectionModeInvalid', ...
                        'Unsupported graph edge-selection mode: %s.',request.edgeSelectionMode);
            end
            info.realizedEdgeCount=numel(edges);
            if possible>0, info.realizedDensity=info.realizedEdgeCount/possible; end
        end

        function token = edgeSelectionIdentity(request)
            % edgeSelectionIdentity  Serialize pruning settings into a deterministic identity token.
            %
            % Syntax:
            %   token = NMResultsViewerFeatureGraphTools.edgeSelectionIdentity(request)
            %
            % Outputs:
            %   token  Mode-specific text used in scientific/cache identities.
            %
            % Side effects:
            %   None.
            switch request.edgeSelectionMode
                case 'legacy_topk_union'
                    token=sprintf('legacy_topk_union:k=%d:g=%d',request.kPerNode,request.maxGlobal);
                case 'fixed_density'
                    token=sprintf('fixed_density:d=%.17g',request.targetDensity);
                case 'absolute_threshold'
                    token=sprintf('absolute_threshold:t=%.17g',request.absoluteThreshold);
                otherwise
                    error('NMResultsViewerFeatureGraphTools:edgeSelectionModeInvalid', ...
                        'Unsupported graph edge-selection mode: %s.',request.edgeSelectionMode);
            end
        end

        function [edges,keepMatrix] = legacyTopKUnion(values,validity,featureIndices,featureIds,kPerNode,maxGlobal,sourceLayerId)
            % legacyTopKUnion  Reproduce the accepted strongest-edge-union pruning rule.
            %
            % Syntax:
            %   [edges,keepMatrix] = NMResultsViewerFeatureGraphTools.legacyTopKUnion( ...
            %       values,validity,featureIndices,featureIds,kPerNode,maxGlobal,sourceLayerId)
            %
            % Scientific contract:
            %   Retains the union of each node's strongest admissible edges and the globally
            %   strongest admissible edges, with deterministic stable-index tie breaking.
            %
            % Invariants and mutability:
            %   Invalid, diagonal, non-finite, and zero cells are excluded.
            %
            % Side effects:
            %   None.
            values=double(values);
            validity=logical(validity);
            n=size(values,1);
            if size(values,2)~=n || ~isequal(size(validity),[n n])
                error('NMResultsViewerFeatureGraphTools:graphMatrixShape', ...
                    'Graph values and validity masks must be equally sized square matrices.');
            end
            featureIndices=double(featureIndices(:)');
            if numel(featureIndices)~=n || numel(featureIds)~=n
                error('NMResultsViewerFeatureGraphTools:graphFeatureIdentityShape', ...
                    'Graph feature identities must align one-to-one with the matrix rows.');
            end
            candidateMask=triu(validity & isfinite(values) & values~=0,1);
            [ii,jj]=find(candidateMask);
            if isempty(ii)
                edges=repmat(NMResultsViewerFeatureGraphTools.edgeTemplate(),1,0);
                keepMatrix=false(n);
                return;
            end
            vv=values(sub2ind([n n],ii,jj));
            magnitudes=abs(vv);
            sourceStable=featureIndices(ii); sourceStable=sourceStable(:);
            targetStable=featureIndices(jj); targetStable=targetStable(:);
            stableTable=[-magnitudes(:) sourceStable targetStable];
            [~,globalOrder]=sortrows(stableTable,[1 2 3]);
            selectedPerNode=false(numel(vv),1);
            if isfinite(kPerNode) && kPerNode>0
                k=max(0,floor(kPerNode));
                for node=1:n
                    incident=find(ii==node | jj==node);
                    if isempty(incident), continue; end
                    localSource=featureIndices(ii(incident)); localSource=localSource(:);
                    localTarget=featureIndices(jj(incident)); localTarget=localTarget(:);
                    localTable=[-magnitudes(incident(:)) localSource localTarget];
                    [~,order]=sortrows(localTable,[1 2 3]);
                    take=incident(order(1:min(k,numel(order))));
                    selectedPerNode(take)=true;
                end
            end
            selectedGlobal=false(numel(vv),1);
            if isfinite(maxGlobal) && maxGlobal>0
                g=max(0,floor(maxGlobal));
                selectedGlobal(globalOrder(1:min(g,numel(globalOrder))))=true;
            end
            keep=selectedPerNode | selectedGlobal;
            kept=find(keep);
            candidateMask(sub2ind([n n],ii,jj))=keep;
            % All graph-pruning modes use the same canonical edge writer.
            [edges,keepMatrix,order]=NMResultsViewerFeatureGraphTools.selectMaskedEdges( ...
                values,candidateMask,featureIndices,featureIds,sourceLayerId,'legacy');
            if ~isempty(edges)
                % Reuse the writer's stable edge order for Top-K provenance.
                chosen=kept(order);
                for kk=1:numel(edges)
                    edges(kk).selectedByPerNode=selectedPerNode(chosen(kk));
                    edges(kk).selectedByGlobal=selectedGlobal(chosen(kk));
                end
            end
        end

        function [edgeClusterIds,info] = linkCommunities(nNodes,edges,cutMode,manualThreshold,minEdges)
            % linkCommunities  Cluster retained graph edges by hierarchical link similarity.
            %
            % Syntax:
            %   [edgeClusterIds,info] = NMResultsViewerFeatureGraphTools.linkCommunities( ...
            %       nNodes,edges,cutMode,manualThreshold,minEdges)
            %
            % Inputs:
            %   nNodes           Number of graph nodes.
            %   edges            Final retained canonical edges only.
            %   cutMode          max_partition_density or manual_similarity.
            %   manualThreshold  Jaccard-link-similarity threshold for manual mode.
            %   minEdges         Minimum retained edges required for a selectable community.
            %
            % Outputs:
            %   edgeClusterIds  One local pattern ID per retained edge; 0 denotes unclustered.
            %   info            Applied flag, resolved threshold, partition density, pattern count,
            %                   unclustered count, and disabledReason.
            %
            % Scientific contract:
            %   Similarity is Jaccard overlap of inclusive endpoint neighbourhoods for adjacent
            %   edges. Automatic mode selects the cut maximizing partition density. Communities
            %   below minEdges are mapped to 0; IDs are deterministic but local to this graph.
            %
            % Invariants and mutability:
            %   No community can reference an edge outside the supplied pruned graph.
            %
            % Errors and diagnostics:
            %   Invalid cut settings raise explicit errors; insufficient edges return an explicit
            %   disabled result rather than a fabricated partition.
            %
            % Side effects:
            %   None.
            m=numel(edges);
            edgeClusterIds=zeros(1,m);
            info=struct('applied',false,'threshold',NaN,'partitionDensity',NaN, ...
                'clusterCount',0,'unclusteredEdgeCount',m,'disabledReason','');
            if m<2
                info.disabledReason='At least two selected graph edges are required for relation-pattern clustering.';
                return;
            end
            adjacency=false(nNodes);
            endpoints=zeros(m,2);
            for ee=1:m
                endpoints(ee,:)=[edges(ee).sourceLocalIndex edges(ee).targetLocalIndex];
                adjacency(endpoints(ee,1),endpoints(ee,2))=true;
                adjacency(endpoints(ee,2),endpoints(ee,1))=true;
            end
            inclusive=adjacency | logical(eye(nNodes));
            stableEndpoints=sort([[edges.sourceFeatureIndex]' [edges.targetFeatureIndex]'],2);
            degrees=sum(adjacency,2);
            pairCapacity=sum(degrees.*max(0,degrees-1)/2);
            pairs=zeros(pairCapacity,3);
            pairCursor=0;
            for shared=1:nNodes
                incident=find(endpoints(:,1)==shared | endpoints(:,2)==shared);
                if numel(incident)<2, continue; end
                for aa=1:numel(incident)-1
                    e1=incident(aa);
                    other1=endpoints(e1,1); if other1==shared, other1=endpoints(e1,2); end
                    for bb=aa+1:numel(incident)
                        e2=incident(bb);
                        other2=endpoints(e2,1); if other2==shared, other2=endpoints(e2,2); end
                        intersection=nnz(inclusive(other1,:) & inclusive(other2,:));
                        unionCount=nnz(inclusive(other1,:) | inclusive(other2,:));
                        similarity=intersection/max(1,unionCount);
                        pairCursor=pairCursor+1;
                        pairs(pairCursor,:)=[e1 e2 similarity];
                    end
                end
            end
            pairs=pairs(1:pairCursor,:);
            if isempty(pairs)
                info.disabledReason='Selected graph edges do not share endpoints; no link-similarity hierarchy can be constructed.';
                return;
            end
            pairs=sortrows(pairs,[-3 1 2]);
            similarities=unique(pairs(:,3),'stable');
            if strcmp(cutMode,'manual_similarity')
                threshold=max(0,min(1,double(manualThreshold)));
                parent=1:m;
                use=find(pairs(:,3)>=threshold);
                for pp=use(:)', parent=NMResultsViewerFeatureGraphTools.unionParents(parent,pairs(pp,1),pairs(pp,2)); end
                [rawIds,~]=NMResultsViewerFeatureGraphTools.normalizedRoots(parent,stableEndpoints);
                density=NMResultsViewerFeatureGraphTools.partitionDensity(rawIds,endpoints);
            else
                parent=1:m;
                bestIds=1:m;
                bestDensity=0;
                threshold=1;
                cursor=1;
                for ss=1:numel(similarities)
                    similarity=similarities(ss);
                    while cursor<=size(pairs,1) && abs(pairs(cursor,3)-similarity)<=1e-12
                        parent=NMResultsViewerFeatureGraphTools.unionParents(parent,pairs(cursor,1),pairs(cursor,2));
                        cursor=cursor+1;
                    end
                    [candidateIds,~]=NMResultsViewerFeatureGraphTools.normalizedRoots(parent,stableEndpoints);
                    candidateDensity=NMResultsViewerFeatureGraphTools.partitionDensity(candidateIds,endpoints);
                    if candidateDensity>bestDensity+1e-12
                        bestDensity=candidateDensity;
                        bestIds=candidateIds;
                        threshold=similarity;
                    end
                end
                rawIds=bestIds;
                density=bestDensity;
            end
            rawIds=double(rawIds(:)');
            clusterIds=unique(rawIds,'stable');
            edgeClusterIds=zeros(1,m);
            nextId=0;
            for cc=1:numel(clusterIds)
                members=find(rawIds==clusterIds(cc));
                if numel(members)<minEdges, continue; end
                nextId=nextId+1;
                edgeClusterIds(members)=nextId;
            end
            info.applied=nextId>0;
            info.threshold=threshold;
            info.partitionDensity=density;
            info.clusterCount=nextId;
            info.unclusteredEdgeCount=nnz(edgeClusterIds==0);
            if ~info.applied
                info.disabledReason=sprintf('No relation cluster contains at least %d selected edges at the resolved link-similarity cut.',minEdges);
            end
        end
    end

    methods (Static, Access=private)
        function [edges,keepMatrix] = selectRankedCandidateEdges(values,candidateMask,featureIndices,featureIds,keepCount,sourceLayerId,provenance)
            % selectRankedCandidateEdges  Retain an exact count of strongest admissible edges.
            %
            % Syntax:
            %   [edges,keepMatrix] = NMResultsViewerFeatureGraphTools.selectRankedCandidateEdges( ...
            %       values,candidateMask,featureIndices,featureIds,keepCount,sourceLayerId,provenance)
            %
            % Invariants and mutability:
            %   Ranking is by descending absolute selected-layer value, then stable endpoints.
            %
            % Side effects:
            %   None.
            [ii,jj]=find(candidateMask);
            if isempty(ii) || keepCount<=0
                edges=repmat(NMResultsViewerFeatureGraphTools.edgeTemplate(),1,0);
                keepMatrix=false(size(values));
                return;
            end
            magnitudes=abs(values(sub2ind(size(values),ii,jj)));
            % Construct columns explicitly because featureIndices indexing returns rows.
            sourceStable=reshape(featureIndices(ii),[],1);
            targetStable=reshape(featureIndices(jj),[],1);
            stable=[-magnitudes(:) min(sourceStable,targetStable) max(sourceStable,targetStable)];
            [~,order]=sortrows(stable,[1 2 3]);
            selected=false(size(candidateMask));
            chosen=order(1:min(keepCount,numel(order)));
            selected(sub2ind(size(selected),ii(chosen),jj(chosen)))=true;
            [edges,keepMatrix]=NMResultsViewerFeatureGraphTools.selectMaskedEdges( ...
                values,selected,featureIndices,featureIds,sourceLayerId,provenance);
        end

        function [edges,keepMatrix,order] = selectMaskedEdges(values,mask,featureIndices,featureIds,sourceLayerId,provenance)
            % selectMaskedEdges  Materialize canonical edges from an upper-triangle mask.
            %
            % Syntax:
            %   [edges,keepMatrix] = NMResultsViewerFeatureGraphTools.selectMaskedEdges( ...
            %       values,mask,featureIndices,featureIds,sourceLayerId,provenance)
            %
            % Outputs:
            %   edges       Stable endpoint-ordered edge rows.
            %   keepMatrix  Symmetric logical mask.
            %
            % Errors and diagnostics:
            %   Feature-identity shape mismatch raises graphFeatureIdentityShape.
            %
            % Side effects:
            %   None.
            n=size(values,1);
            featureIndices=double(featureIndices(:)');
            if numel(featureIndices)~=n || numel(featureIds)~=n
                error('NMResultsViewerFeatureGraphTools:graphFeatureIdentityShape', ...
                    'Graph feature identities must align one-to-one with the matrix rows.');
            end
            [ii,jj]=find(triu(logical(mask),1));
            if isempty(ii)
                edges=repmat(NMResultsViewerFeatureGraphTools.edgeTemplate(),1,0);
                keepMatrix=false(n);
                order=zeros(0,1);
                return;
            end
            sourceStable=reshape(featureIndices(ii),[],1);
            targetStable=reshape(featureIndices(jj),[],1);
            stable=[min(sourceStable,targetStable) max(sourceStable,targetStable)];
            [~,order]=sortrows(stable,[1 2]);
            ii=ii(order); jj=jj(order);
            edges=repmat(NMResultsViewerFeatureGraphTools.edgeTemplate(),1,numel(ii));
            keepMatrix=false(n);
            for kk=1:numel(ii)
                a=ii(kk); b=jj(kk);
                keepMatrix(a,b)=true; keepMatrix(b,a)=true;
                if featureIndices(a)>featureIndices(b), tmp=a; a=b; b=tmp; end
                sourceId=featureIds{a}; targetId=featureIds{b};
                edges(kk).edgeId=sprintf('edge:%s:%s--%s',sourceLayerId,sourceId,targetId);
                edges(kk).sourceNodeId=sprintf('node:%s',sourceId);
                edges(kk).targetNodeId=sprintf('node:%s',targetId);
                edges(kk).sourceFeatureId=sourceId;
                edges(kk).targetFeatureId=targetId;
                edges(kk).sourceFeatureIndex=featureIndices(a);
                edges(kk).targetFeatureIndex=featureIndices(b);
                edges(kk).sourceLocalIndex=a;
                edges(kk).targetLocalIndex=b;
                edges(kk).weight=values(a,b);
                edges(kk).magnitude=abs(values(a,b));
                edges(kk).sign=sign(values(a,b));
                edges(kk).selectedByDensity=strcmp(provenance,'density');
                edges(kk).selectedByThreshold=strcmp(provenance,'threshold');
            end
        end

        function graph = populateIdentity(graph,matrix,request)
            % populateIdentity  Copy source/request identity fields into a new graph contract.
            %
            % Syntax:
            %   graph = NMResultsViewerFeatureGraphTools.populateIdentity(graph,matrix,request)
            %
            % Invariants and mutability:
            %   Only the supplied graph value is returned modified; matrix/request remain unchanged.
            %
            % Side effects:
            %   None.
            graph.contextId=matrix.contextId;
            graph.matrixId=matrix.matrixId;
            graph.graphId=sprintf('%s_graph',graph.matrixId);
            graph.componentApplicability='invariant';
            graph.componentSelectionAffectsContent=false;
            graph.sourceLayerId=request.sourceLayerId;
            graph.edgeSelectionMode=request.edgeSelectionMode;
            graph.kPerNode=request.kPerNode;
            graph.maxGlobal=request.maxGlobal;
            graph.targetDensity=request.targetDensity;
            graph.absoluteThreshold=request.absoluteThreshold;
            graph.relationPatternRequested=request.relationPatternEnabled;
            graph.relationPatternMethod=request.relationPatternMethod;
            graph.relationPatternCutMode=request.relationPatternCutMode;
            graph.relationPatternSimilarityThresholdRequested=request.relationPatternSimilarityThreshold;
            graph.relationPatternMinEdges=request.relationPatternMinEdges;
        end

        function graph = assignIdentity(graph,request)
            % assignIdentity  Finalize graph scientific, cache, and graph IDs.
            %
            % Syntax:
            %   graph = NMResultsViewerFeatureGraphTools.assignIdentity(graph,request)
            %
            % Scientific contract:
            %   Identity includes stable features, physical layer, pruning rule, and pattern settings.
            %   Pattern IDs are therefore invalidated whenever the edge universe changes.
            %
            % Side effects:
            %   None.
            selectedToken=sprintf('%d,',graph.selectedFeatureIndices);
            selectionToken=NMResultsViewerFeatureGraphTools.edgeSelectionIdentity(request);
            state=sprintf('C17h1.1|%s|selected=%s|layer=%s|edge=%s|pattern=%d:%s:%s:%.17g:%d', ...
                graph.matrixId,selectedToken,request.sourceLayerId,selectionToken, ...
                double(request.relationPatternEnabled),request.relationPatternMethod,request.relationPatternCutMode, ...
                request.relationPatternSimilarityThreshold,request.relationPatternMinEdges);
            graph.scientificStateIdentity=state;
            graph.cacheIdentity=sprintf('feature_graph_%08x',NMResultsViewerFeatureGraphTools.textChecksum(state));
            graph.graphId=sprintf('%s_%08x',graph.graphId,NMResultsViewerFeatureGraphTools.textChecksum(state));
        end

        function nodes = buildNodeRows(featureIndices,featureIds,labels,edges,componentIds)
            % buildNodeRows  Create stable node rows and unweighted topology.
            %
            % Syntax:
            %   nodes = NMResultsViewerFeatureGraphTools.buildNodeRows( ...
            %       featureIndices,featureIds,labels,edges,componentIds)
            %
            % Outputs:
            %   nodes  Node rows with identity, degree, component ID, and component size.
            %
            % Invariants and mutability:
            %   Weighted statistics are deferred until correlation evidence is attached.
            %
            % Side effects:
            %   None.
            n=numel(featureIndices);
            nodes=repmat(NMResultsViewerFeatureGraphTools.nodeTemplate(),1,n);
            componentIds=double(componentIds(:)');
            if numel(componentIds)~=n
                error('NMResultsViewerFeatureGraphTools:graphComponentIdentityShape', ...
                    'Graph component IDs must align one-to-one with the node axis.');
            end
            componentSizes=zeros(1,n);
            for ii=1:n
                if componentIds(ii)>0
                    componentSizes(ii)=nnz(componentIds==componentIds(ii));
                end
            end
            for ii=1:n
                nodes(ii).nodeId=sprintf('node:%s',featureIds{ii});
                nodes(ii).featureId=featureIds{ii};
                nodes(ii).featureIndex=featureIndices(ii);
                nodes(ii).label=labels{ii};
                nodes(ii).connectedComponentId=componentIds(ii);
                nodes(ii).componentSize=componentSizes(ii);
            end
            for ee=1:numel(edges)
                a=edges(ee).sourceLocalIndex; b=edges(ee).targetLocalIndex;
                nodes(a).degree=nodes(a).degree+1;
                nodes(b).degree=nodes(b).degree+1;
            end
        end

        function edges = attachPairwiseEvidence(matrix,selectedFeatureIndices,edges)
            % attachPairwiseEvidence  Attach aligned correlation, P, and q evidence to retained edges.
            %
            % Syntax:
            %   edges = NMResultsViewerFeatureGraphTools.attachPairwiseEvidence( ...
            %       matrix,selectedFeatureIndices,edges)
            %
            % Scientific contract:
            %   Evidence attachment never adds, removes, or reorders graph edges.
            %
            % Side effects:
            %   None.
            if isempty(edges), return; end
            layerIds={'feature_correlation','mean_log10_p','mean_log10_fdr_q'};
            layerValues=cell(1,numel(layerIds));
            layerValid=cell(1,numel(layerIds));
            for ll=1:numel(layerIds)
                idx=find(strcmp({matrix.layers.layerId},layerIds{ll}),1,'first');
                if isempty(idx)
                    error('NMResultsViewerFeatureGraphTools:canonicalLayerMissing', ...
                        'Canonical Feature Relation matrix is missing required layer %s.',layerIds{ll});
                end
                if ~matrix.layers(idx).available
                    layerValues{ll}=[]; layerValid{ll}=false(0); continue;
                end
                layerValues{ll}=NMResultsViewerFeatureGraphTools.matrixFromRows(matrix.layers(idx).values);
                layerValid{ll}=NMResultsViewerFeatureGraphTools.logicalMatrixFromRows(matrix.layers(idx).validityMask);
            end
            selectedFeatureIndices=double(selectedFeatureIndices(:)');
            for ee=1:numel(edges)
                a=selectedFeatureIndices(edges(ee).sourceLocalIndex);
                b=selectedFeatureIndices(edges(ee).targetLocalIndex);
                pairValues=NaN(1,3);
                for ll=1:3
                    if isempty(layerValues{ll}), continue; end
                    if layerValid{ll}(a,b) && isfinite(layerValues{ll}(a,b)), pairValues(ll)=layerValues{ll}(a,b); end
                end
                edges(ee).correlation=pairValues(1);
                edges(ee).meanLog10P=pairValues(2);
                edges(ee).meanLog10FdrQ=pairValues(3);
            end
        end

        function nodes = assignNodeRanksAndLayout(nodes,edges)
            % assignNodeRanksAndLayout  Add deterministic ranks and normalized layout coordinates.
            %
            % Syntax:
            %   nodes = NMResultsViewerFeatureGraphTools.assignNodeRanksAndLayout(nodes,edges)
            %
            % Invariants and mutability:
            %   Descending-rank ties use stable feature indices; layout is deterministic.
            %
            % Side effects:
            %   None.
            if isempty(nodes), return; end
            featureIndices=[nodes.featureIndex]';
            degreeRanks=NMResultsViewerFeatureGraphTools.descendingRanks([nodes.degree]',featureIndices);
            strengthRanks=NMResultsViewerFeatureGraphTools.descendingRanks([nodes.absoluteStrength]',featureIndices);
            betweennessRanks=NMResultsViewerFeatureGraphTools.descendingRanks([nodes.betweennessCentrality]',featureIndices);
            closenessRanks=NMResultsViewerFeatureGraphTools.descendingRanks([nodes.harmonicCloseness]',featureIndices);
            eigenvectorRanks=NMResultsViewerFeatureGraphTools.descendingRanks([nodes.eigenvectorCentrality]',featureIndices);
            [x,y]=NMResultsViewerFeatureGraphTools.deterministicForceLayout(numel(nodes),edges,featureIndices);
            for ii=1:numel(nodes)
                nodes(ii).degreeRank=degreeRanks(ii);
                nodes(ii).absoluteStrengthRank=strengthRanks(ii);
                nodes(ii).betweennessRank=betweennessRanks(ii);
                nodes(ii).harmonicClosenessRank=closenessRanks(ii);
                nodes(ii).eigenvectorRank=eigenvectorRanks(ii);
                nodes(ii).layoutX=x(ii);
                nodes(ii).layoutY=y(ii);
            end
        end

        function [nodes,info] = computeGraphStatistics(nodes,edges,pathLengthEpsilon)
            % computeGraphStatistics  Compute canonical weighted and signed node statistics.
            %
            % Syntax:
            %   [nodes,info] = NMResultsViewerFeatureGraphTools.computeGraphStatistics( ...
            %       nodes,edges,pathLengthEpsilon)
            %
            % Outputs:
            %   nodes  Updated degree/strength, betweenness, harmonic-closeness, and
            %          eigenvector-centrality fields.
            %   info   Availability and disabledReason.
            %
            % Scientific contract:
            %   Strength separates absolute, positive, and negative correlation contributions.
            %   Weighted paths use 1/(abs(correlation)+epsilon). Eigenvector centrality uses the
            %   absolute-correlation affinity matrix. Missing correlation disables weighted
            %   statistics explicitly; selected-layer values are not substituted.
            %
            % Invariants and mutability:
            %   Centrality describes the pruned graph and not predictive feature importance.
            %
            % Side effects:
            %   None.
            info=struct('available',false,'disabledReason','');
            n=numel(nodes);
            if n<1
                info.available=true;
                return;
            end
            epsilon=double(pathLengthEpsilon);
            if ~isfinite(epsilon) || epsilon<=0
                error('NMResultsViewerFeatureGraphTools:pathLengthEpsilonInvalid', ...
                    'Graph-statistics path-length epsilon must be finite and positive.');
            end
            affinity=zeros(n);
            signed=zeros(n);
            for ee=1:numel(edges)
                a=double(edges(ee).sourceLocalIndex); b=double(edges(ee).targetLocalIndex);
                r=double(edges(ee).correlation);
                if ~isfinite(a) || ~isfinite(b) || a<1 || b<1 || a>n || b>n || a==b
                    info.disabledReason='A retained graph edge has invalid canonical node indices.';
                    return;
                end
                if ~isfinite(r)
                    info.disabledReason=sprintf('Correlation evidence is unavailable for retained edge %s; weighted graph statistics were not computed.',edges(ee).edgeId);
                    return;
                end
                affinity(a,b)=abs(r); affinity(b,a)=abs(r);
                signed(a,b)=r; signed(b,a)=r;
            end
            absoluteStrength=sum(affinity,2);
            positiveStrength=sum(max(signed,0),2);
            negativeStrength=sum(abs(min(signed,0)),2);
            lengths=inf(n);
            lengths(1:n+1:end)=0;
            mask=false(n);
            for ee=1:numel(edges)
                a=double(edges(ee).sourceLocalIndex); b=double(edges(ee).targetLocalIndex);
                lengths(a,b)=1/(affinity(a,b)+epsilon);
                lengths(b,a)=lengths(a,b);
                mask(a,b)=true; mask(b,a)=true;
            end
            [betweenness,harmonic]=NMResultsViewerFeatureGraphTools.weightedBetweennessAndHarmonic(lengths,mask);
            eigenvector=NMResultsViewerFeatureGraphTools.absoluteEigenvectorCentrality(affinity);
            for ii=1:n
                nodes(ii).absoluteStrength=absoluteStrength(ii);
                nodes(ii).positiveStrength=positiveStrength(ii);
                nodes(ii).negativeStrength=negativeStrength(ii);
                nodes(ii).betweennessCentrality=betweenness(ii);
                nodes(ii).harmonicCloseness=harmonic(ii);
                nodes(ii).eigenvectorCentrality=eigenvector(ii);
            end
            info.available=true;
            info.disabledReason='';
        end

        function [betweenness,harmonic] = weightedBetweennessAndHarmonic(lengths,edgeMask)
            % weightedBetweennessAndHarmonic  Compute weighted shortest-path centralities without toolboxes.
            %
            % Syntax:
            %   [betweenness,harmonic] = NMResultsViewerFeatureGraphTools.weightedBetweennessAndHarmonic(lengths,edgeMask)
            %
            % Inputs:
            %   lengths   Symmetric positive edge-length matrix.
            %   edgeMask  Symmetric logical adjacency mask.
            %
            % Outputs:
            %   betweenness  Global [0,1]-normalized weighted betweenness.
            %   harmonic     Harmonic closeness divided by n-1.
            %
            % Side effects:
            %   None.
            n=size(lengths,1);
            betweenness=zeros(n,1);
            harmonic=zeros(n,1);
            if n<=1, return; end
            tolerance=1e-12;
            for source=1:n
                predecessors=cell(n,1);
                sigma=zeros(n,1); sigma(source)=1;
                distance=inf(n,1); distance(source)=0;
                settled=false(n,1);
                stack=zeros(1,n); stackCount=0;
                while true
                    candidates=find(~settled);
                    if isempty(candidates), break; end
                    candidateDistance=distance(candidates);
                    [minimum,which]=min(candidateDistance);
                    if ~isfinite(minimum), break; end
                    vertex=candidates(which);
                    settled(vertex)=true;
                    stackCount=stackCount+1; stack(stackCount)=vertex;
                    neighbours=find(edgeMask(vertex,:));
                    for jj=1:numel(neighbours)
                        neighbour=neighbours(jj);
                        alternative=distance(vertex)+lengths(vertex,neighbour);
                        if ~isfinite(distance(neighbour))
                            distance(neighbour)=alternative;
                            sigma(neighbour)=sigma(vertex);
                            predecessors{neighbour}=vertex;
                            continue;
                        end
                        scale=max(1,max(abs([alternative distance(neighbour)])));
                        if alternative<distance(neighbour)-tolerance*scale
                            distance(neighbour)=alternative;
                            sigma(neighbour)=sigma(vertex);
                            predecessors{neighbour}=vertex;
                        elseif abs(alternative-distance(neighbour))<=tolerance*scale
                            sigma(neighbour)=sigma(neighbour)+sigma(vertex);
                            predecessors{neighbour}(end+1)=vertex; %#ok<AGROW>
                        end
                    end
                end
                reachable=isfinite(distance) & (1:n)'~=source;
                harmonic(source)=sum(1./distance(reachable))/max(1,n-1);
                dependency=zeros(n,1);
                for kk=stackCount:-1:1
                    w=stack(kk);
                    preds=predecessors{w};
                    for pp=1:numel(preds)
                        v=preds(pp);
                        if sigma(w)>0
                            dependency(v)=dependency(v)+(sigma(v)/sigma(w))*(1+dependency(w));
                        end
                    end
                    if w~=source, betweenness(w)=betweenness(w)+dependency(w); end
                end
            end
            betweenness=betweenness/2;
            if n>2, betweenness=betweenness*(2/((n-1)*(n-2))); else, betweenness(:)=0; end
            betweenness=max(0,min(1,betweenness));
        end

        function centrality = absoluteEigenvectorCentrality(affinity)
            % absoluteEigenvectorCentrality  Compute L2-normalized centrality from absolute affinities.
            %
            % Syntax:
            %   centrality = NMResultsViewerFeatureGraphTools.absoluteEigenvectorCentrality(affinity)
            %
            % Invariants and mutability:
            %   Uses deterministic power iteration and returns zeros for edgeless affinity.
            %
            % Side effects:
            %   None.
            n=size(affinity,1);
            centrality=zeros(n,1);
            if n<1 || ~any(affinity(:)>0), return; end
            vector=ones(n,1)/sqrt(n);
            tolerance=1e-12;
            shift=max(1,max(sum(affinity,2)));
            operator=affinity+shift*eye(n);
            for iteration=1:1000
                next=operator*vector;
                normValue=norm(next,2);
                if normValue<=eps, centrality=zeros(n,1); return; end
                next=next/normValue;
                if norm(next-vector,2)<=tolerance || norm(next+vector,2)<=tolerance
                    vector=next; break;
                end
                vector=next;
            end
            centrality=abs(vector);
            centrality(centrality<1e-14)=0;
            normValue=norm(centrality,2);
            if normValue>0, centrality=centrality/normValue; end
        end

        function ranks = descendingRanks(values,featureIndices)
            % descendingRanks  Assign deterministic competition ranks in descending metric order.
            %
            % Syntax:
            %   ranks = NMResultsViewerFeatureGraphTools.descendingRanks(values,featureIndices)
            %
            % Invariants and mutability:
            %   Stable feature index resolves equal finite values; non-finite values rank last.
            %
            % Side effects:
            %   None.
            values=double(values(:)); featureIndices=double(featureIndices(:));
            n=numel(values); ranks=zeros(n,1);
            finiteMask=isfinite(values);
            positions=find(finiteMask);
            if isempty(positions), return; end
            keys=[-values(positions) featureIndices(positions) positions];
            [~,order]=sortrows(keys,[1 2 3]);
            ranks(positions(order))=(1:numel(order))';
        end

        function [x,y] = deterministicForceLayout(n,edges,featureIndices)
            % deterministicForceLayout  Compute reproducible normalized force-layout coordinates.
            %
            % Syntax:
            %   [x,y] = NMResultsViewerFeatureGraphTools.deterministicForceLayout(n,edges,featureIndices)
            %
            % Scientific contract:
            %   Initialization, iteration count, tie handling, and normalization are deterministic.
            %
            % Side effects:
            %   None.
            if n<1, x=zeros(0,1); y=zeros(0,1); return; end
            if n==1, x=.5; y=.5; return; end
            featureIndices=double(featureIndices(:));
            [~,stableOrder]=sortrows([featureIndices (1:n)'],[1 2]);
            theta=zeros(n,1);
            for rank=1:n, theta(stableOrder(rank))=-pi/2+2*pi*(rank-1)/n; end
            pos=[.5+.38*cos(theta) .5+.38*sin(theta)];
            ideal=.72/sqrt(max(2,n));
            temperature=.12;
            iterations=100;
            if n>120, iterations=60; elseif n>70, iterations=75; end
            edgeMagnitude=[edges.magnitude];
            maxMagnitude=max([1e-12 edgeMagnitude]);
            for iter=1:iterations
                dispVec=zeros(n,2);
                for aa=1:n-1
                    for bb=aa+1:n
                        delta=pos(aa,:)-pos(bb,:);
                        dist=max(1e-6,sqrt(sum(delta.^2)));
                        force=(ideal^2)/dist;
                        unit=delta/dist;
                        dispVec(aa,:)=dispVec(aa,:)+unit*force;
                        dispVec(bb,:)=dispVec(bb,:)-unit*force;
                    end
                end
                for ee=1:numel(edges)
                    aa=edges(ee).sourceLocalIndex; bb=edges(ee).targetLocalIndex;
                    delta=pos(aa,:)-pos(bb,:);
                    dist=max(1e-6,sqrt(sum(delta.^2)));
                    strength=.70+.60*(edges(ee).magnitude/maxMagnitude);
                    force=strength*(dist^2)/max(ideal,1e-6);
                    unit=delta/dist;
                    dispVec(aa,:)=dispVec(aa,:)-unit*force;
                    dispVec(bb,:)=dispVec(bb,:)+unit*force;
                end
                dispVec=dispVec+(.5-pos)*.035;
                norms=sqrt(sum(dispVec.^2,2));
                scale=min(temperature,norms)./max(norms,1e-12);
                pos=pos+dispVec.*scale;
                pos=max(.03,min(.97,pos));
                temperature=temperature*.94;
            end
            lo=min(pos,[],1); hi=max(pos,[],1); span=max(hi-lo,1e-9);
            pos=.07+.86*(pos-lo)./span;
            x=pos(:,1); y=pos(:,2);
        end

        function nodes = assignNodeRelationClusters(nodes,edges)
            % assignNodeRelationClusters  Attach local relation-pattern memberships to node rows.
            %
            % Syntax:
            %   nodes = NMResultsViewerFeatureGraphTools.assignNodeRelationClusters(nodes,edges)
            %
            % Invariants and mutability:
            %   Membership derives only from positive pattern IDs on retained incident edges.
            %
            % Side effects:
            %   None.
            for ii=1:numel(nodes)
                ids=zeros(1,0);
                for ee=1:numel(edges)
                    if edges(ee).relationClusterId<=0, continue; end
                    if edges(ee).sourceLocalIndex==ii || edges(ee).targetLocalIndex==ii
                        ids(end+1)=edges(ee).relationClusterId; %#ok<AGROW>
                    end
                end
                nodes(ii).relationClusterIds=unique(ids,'stable');
            end
        end

        function [componentIds,count] = connectedComponents(n,edges)
            % connectedComponents  Compute deterministic component IDs for an undirected graph.
            %
            % Syntax:
            %   [componentIds,count] = NMResultsViewerFeatureGraphTools.connectedComponents(n,edges)
            %
            % Outputs:
            %   componentIds  One-based ID per node, including singleton components.
            %   count         Number of components.
            %
            % Side effects:
            %   None.
            adjacency=cell(n,1);
            for ee=1:numel(edges)
                a=edges(ee).sourceLocalIndex; b=edges(ee).targetLocalIndex;
                adjacency{a}(end+1)=b; adjacency{b}(end+1)=a; %#ok<AGROW>
            end
            componentIds=zeros(1,n); count=0;
            for start=1:n
                if componentIds(start)>0, continue; end
                count=count+1; queue=start; componentIds(start)=count; head=1;
                while head<=numel(queue)
                    u=queue(head); head=head+1;
                    neighbours=adjacency{u};
                    for vv=1:numel(neighbours)
                        v=neighbours(vv);
                        if componentIds(v)==0
                            componentIds(v)=count; queue(end+1)=v; %#ok<AGROW>
                        end
                    end
                end
            end
        end

        function matrix = edgeClusterMatrix(n,edges,clusterIds)
            % edgeClusterMatrix  Project edge-pattern IDs into a symmetric node-pair matrix.
            %
            % Syntax:
            %   matrix = NMResultsViewerFeatureGraphTools.edgeClusterMatrix(n,edges,clusterIds)
            %
            % Invariants and mutability:
            %   Non-retained pairs and unclustered edges remain zero.
            %
            % Side effects:
            %   None.
            matrix=zeros(n);
            for ee=1:numel(edges)
                id=clusterIds(ee);
                if id<=0, continue; end
                a=edges(ee).sourceLocalIndex; b=edges(ee).targetLocalIndex;
                matrix(a,b)=id; matrix(b,a)=id;
            end
        end

        function summaries = clusterSummaries(edges,featureIndices,featureIds,labels)
            % clusterSummaries  Summarize every retained nonzero relation pattern.
            %
            % Syntax:
            %   summaries = NMResultsViewerFeatureGraphTools.clusterSummaries( ...
            %       edges,featureIndices,featureIds,labels)
            %
            % Outputs:
            %   summaries  Deterministically ID-ordered pattern summaries containing only final
            %              retained edges and participating nodes.
            %
            % Side effects:
            %   None.
            ids=unique([edges.relationClusterId]); ids=ids(ids>0);
            summaries=repmat(NMResultsViewerFeatureGraphTools.relationClusterSummaryTemplate(),1,0);
            if isempty(ids), return; end
            summaries=repmat(NMResultsViewerFeatureGraphTools.relationClusterSummaryTemplate(),1,numel(ids));
            for cc=1:numel(ids)
                id=ids(cc); members=find([edges.relationClusterId]==id);
                localNodes=unique([[edges(members).sourceLocalIndex] [edges(members).targetLocalIndex]],'stable');
                weights=[edges(members).weight];
                summaries(cc).relationClusterId=id;
                summaries(cc).edgeCount=numel(members);
                summaries(cc).nodeCount=numel(localNodes);
                summaries(cc).singletonEdge=numel(members)==1;
                summaries(cc).featureIndices=featureIndices(localNodes);
                summaries(cc).featureIds=featureIds(localNodes);
                summaries(cc).labels=labels(localNodes);
                summaries(cc).positiveEdgeCount=nnz(weights>0);
                summaries(cc).negativeEdgeCount=nnz(weights<0);
                summaries(cc).meanAbsoluteWeight=mean(abs(weights));
                summaries(cc).totalAbsoluteWeight=sum(abs(weights));
            end
        end

        function parent = unionParents(parent,a,b)
            % unionParents  Union two disjoint-set roots using deterministic lower-root ownership.
            %
            % Side effects:
            %   None.
            ra=NMResultsViewerFeatureGraphTools.findRoot(parent,a);
            rb=NMResultsViewerFeatureGraphTools.findRoot(parent,b);
            if ra==rb, return; end
            if ra<rb, parent(rb)=ra; else, parent(ra)=rb; end
        end

        function root = findRoot(parent,node)
            % findRoot  Resolve one disjoint-set root without mutating the parent vector.
            %
            % Side effects:
            %   None.
            root=node;
            while parent(root)~=root, root=parent(root); end
        end

        function [ids,roots] = normalizedRoots(parent,endpoints)
            % normalizedRoots  Convert disjoint-set roots into deterministic consecutive cluster IDs.
            %
            % Outputs:
            %   ids    One cluster ID per endpoint row.
            %   roots  Stable root IDs corresponding to ids.
            %
            % Side effects:
            %   None.
            m=numel(parent); roots=zeros(1,m);
            for ii=1:m, roots(ii)=NMResultsViewerFeatureGraphTools.findRoot(parent,ii); end
            uniqueRoots=unique(roots);
            keys=zeros(numel(uniqueRoots),3);
            for rr=1:numel(uniqueRoots)
                members=find(roots==uniqueRoots(rr));
                stablePairs=sortrows(endpoints(members,:),[1 2]);
                keys(rr,:)=[stablePairs(1,:) uniqueRoots(rr)];
            end
            [~,order]=sortrows(keys,[1 2 3]);
            ids=zeros(1,m);
            for rank=1:numel(order), ids(roots==uniqueRoots(order(rank)))=rank; end
        end

        function density = partitionDensity(clusterIds,endpoints)
            % partitionDensity  Compute link-community partition density for one edge partition.
            %
            % Scientific contract:
            %   Communities with fewer than two edges or insufficient nodes contribute zero.
            %
            % Side effects:
            %   None.
            m=size(endpoints,1);
            if m<1, density=0; return; end
            total=0;
            ids=unique(clusterIds,'stable');
            for cc=1:numel(ids)
                members=find(clusterIds==ids(cc));
                mc=numel(members);
                nc=numel(unique(endpoints(members,:)));
                if nc<=2, continue; end
                total=total + mc * (2*(mc-nc+1)/((nc-2)*(nc-1)));
            end
            density=total/m;
        end

        function rows = numericMatrixRows(matrix)
            % numericMatrixRows  Serialize a numeric matrix as a fixed row-struct array.
            %
            % Side effects:
            %   None.
            if isempty(matrix), rows=[]; return; end
            rows=cell(size(matrix,1),1);
            for rr=1:size(matrix,1), rows{rr}=double(matrix(rr,:)); end
        end

        function rows = logicalMatrixRows(matrix)
            % logicalMatrixRows  Serialize a logical matrix as a fixed row-struct array.
            %
            % Side effects:
            %   None.
            if isempty(matrix), rows=[]; return; end
            rows=cell(size(matrix,1),1);
            for rr=1:size(matrix,1), rows{rr}=logical(matrix(rr,:)); end
        end

        function matrix = matrixFromRows(rows)
            % matrixFromRows  Reconstruct the canonical numeric row-cell matrix.
            %
            % Side effects:
            %   None.
            if isempty(rows), matrix=[]; return; end
            matrix=double(vertcat(rows{:}));
        end

        function matrix = logicalMatrixFromRows(rows)
            % logicalMatrixFromRows  Reconstruct the canonical logical row-cell matrix.
            %
            % Side effects:
            %   None.
            if isempty(rows), matrix=false(0); return; end
            matrix=logical(vertcat(rows{:}));
        end

        function checksum = textChecksum(txt)
            % textChecksum  Compute the deterministic 32-bit text checksum used in graph IDs.
            %
            % Side effects:
            %   None.
            bytes=double(char(txt)); checksum=uint32(2166136261);
            for ii=1:numel(bytes), checksum=bitxor(checksum,uint32(bytes(ii))); checksum=uint32(mod(uint64(checksum)*16777619,2^32)); end
            checksum=double(checksum);
        end

        function d = diagnosticTemplate()
            % diagnosticTemplate  Create the fixed-schema graph diagnostic row.
            %
            % Side effects:
            %   None.
            tmpl=struct('severity','','source','','message','','legacyField','', ...
                'contextId','','stackFunction1','','stackFunction2','','stackFunction3','');
            d=tmpl;
        end

        function d = diagnostic(severity,source,message,legacyField,contextId,stack1,stack2,stack3)
            % diagnostic  Create one normalized graph diagnostic with explicit stack slots.
            %
            % Side effects:
            %   None.
            d=NMResultsViewerFeatureGraphTools.diagnosticTemplate();
            d.severity=severity; d.source=source; d.message=message;
            d.legacyField=legacyField; d.contextId=contextId;
            d.stackFunction1=stack1; d.stackFunction2=stack2; d.stackFunction3=stack3;
        end

        function d = diagnosticFromException(source,ME,contextId)
            % diagnosticFromException  Preserve an exception identifier, message, and stack context.
            %
            % Outputs:
            %   d  Error diagnostic containing source, message, context ID, and up to three
            %      function/file/line stack descriptions.
            %
            % Side effects:
            %   None.
            stack={'','',''};
            for ii=1:min(3,numel(ME.stack)), stack{ii}=sprintf('%s, line %d',ME.stack(ii).name,ME.stack(ii).line); end
            d=NMResultsViewerFeatureGraphTools.diagnostic('error',source, ...
                sprintf('%s: %s',ME.identifier,ME.message),'',contextId,stack{1},stack{2},stack{3});
        end
    end
end

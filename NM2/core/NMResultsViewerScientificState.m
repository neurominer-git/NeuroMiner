classdef NMResultsViewerScientificState
% NMResultsViewerScientificState
% -------------------------------------------------------------------------
% Runtime scientific-space authority for the NM 2.0 Results Viewer.
%
% The State starts from already materialized authoritative payloads, asks the
% central scientific-function registry what each function needs/provides, and
% resolves derivable artefacts/visualizations to a deterministic fixed point.
% It stores semantic schemas and opaque source identities only; numerical
% payload arrays remain owned by their existing Results Viewer authorities.
%
% Contract: NM-SCIENTIFIC-STATE-V1
% -------------------------------------------------------------------------

    methods (Static)
        function version=contractVersion()
            version='NM-SCIENTIFIC-STATE-V1';
        end

        function state=fromPayloads(payloads,spec,functions)
            % nm2-allow: NMResultsViewerScientificCapability.registeredFunctions owns the canonical registry; production callers intentionally omit only this registry argument, while focused tests inject ordering/subsets.
            if nargin<3, functions=NMResultsViewerScientificCapability.registeredFunctions(); end
            contracts=NMResultsViewerScientificCapability.interrogate(functions);
            artefactTemplate=NMResultsViewerScientificState.artefactTemplate();
            visualizationTemplate=NMResultsViewerScientificState.visualizationTemplate();
            artefacts=artefactTemplate([]);
            visualizations=visualizationTemplate([]);
            roots=struct('key',{},'payload',{},'schema',{});
            for ii=1:numel(payloads)
                q=payloads{ii};
                if isempty(q.scientificAnnotation.domain), continue; end
                root=struct('key',NMResultsViewerScientificState.contextKey(q,ii), ...
                    'payload',q,'schema',q.scientificAnnotation.schema);
                roots(end+1)=root; %#ok<AGROW>
                for cc=1:numel(contracts)
                    if ~isempty(contracts(cc).needs), continue; end
                    current=NMResultsViewerScientificCapability.available(contracts(cc), ...
                        struct('payload',q,'spec',spec));
                    [artefacts,visualizations]=NMResultsViewerScientificState.addProvides( ...
                        artefacts,visualizations,current.provides,root.key,root.schema, ...
                        current.id,{},true,q);
                end
            end

            changed=true;
            while changed
                changed=false;
                for rr=1:numel(roots)
                    key=roots(rr).key;
                    for cc=1:numel(contracts)
                        if isempty(contracts(cc).needs), continue; end
                        [needsMet,sourceIds,sourceSchema]=NMResultsViewerScientificState.resolveSources( ...
                            artefacts,key,contracts(cc).needs,roots(rr).schema);
                        if ~needsMet, continue; end
                        current=NMResultsViewerScientificCapability.available(contracts(cc), ...
                            struct('payload',roots(rr).payload,'spec',spec,'sourceArtifactIds',{sourceIds}));
                        before=numel(artefacts)+numel(visualizations);
                        [artefacts,visualizations]=NMResultsViewerScientificState.addProvides( ...
                            artefacts,visualizations,current.provides,key,sourceSchema, ...
                            current.id,sourceIds,false,roots(rr).payload);
                        entryCount=numel(artefacts)+numel(visualizations);
                        changed=changed||(entryCount>before);
                    end
                end
            end
            state=struct('contractVersion',NMResultsViewerScientificState.contractVersion(), ...
                'capabilityContractVersion',NMResultsViewerScientificCapability.contractVersion(), ...
                'capabilities',contracts,'artefacts',artefacts,'visualizations',visualizations, ...
                'featureNamespace',NMResultsViewerScientificState.featureNamespaceTemplate());
        end

        function out=clientView(state)
            % clientView  Project queryable State only; executable registry stays server-side.
            out=rmfield(state,'capabilities');
        end

        function tf=hasArtefact(state,id,criteria)
            % nm2-allow: Scientific State query API boundary; production callers intentionally omit criteria for the canonical unfiltered id query.
            if nargin<3, criteria=[]; end
            tf=NMResultsViewerScientificState.hasEntry(state,'artefacts',id,criteria);
        end

        function tf=hasVisualization(state,id,criteria)
            % nm2-allow: Scientific State query API boundary; production callers intentionally omit criteria for the canonical unfiltered id query.
            if nargin<3, criteria=[]; end
            tf=NMResultsViewerScientificState.hasEntry(state,'visualizations',id,criteria);
        end

        function namespace=featureNamespaceTemplate()
            % Purpose: Define the compact analysis-level feature namespace exposed by Scientific State.
            % Syntax: namespace = NMResultsViewerScientificState.featureNamespaceTemplate()
            % Inputs: None.
            % Outputs: Fixed-schema namespace metadata; names is populated only when the analysis itself owns a compact derived namespace (currently stacking).
            % Authority and flow: Scientific Annotation owns ordinary/fusion topology and exposes physical VIS members separately from the virtual projected modality; Scientific State adds the stacker exception because stacker features are analysis-derived rather than DataIO-native.
            % Scientific/state contract: resolvedFeatureCount describes the selected physical member or combined feature axis; projectionFeatureCount describes the complete virtual early-fusion axis. physicalVarinds/physicalFeatureCounts preserve the selected exact VIS members; modalityVarinds identifies the virtual projected DataIO namespace, which is the first FUSION.M member for early/intermediate fusion and remains empty for stackers. selectedContextIsCombined distinguishes the combined 704-feature projection from an individual member such as a 117-feature first modality.
            % Invariants: Downstream consumers read this State record and do not reopen FUSION/featnames/VIS structures to rediscover analysis namespace identity.
            % Materialization and performance: Compact metadata only. No feature-scale names are copied for ordinary or imaging modalities; stacker names are retained because they are the analysis-level feature axis itself.
            % Failure semantics: Namespace mismatches in a declared stacker are explicit errors.
            % Side effects: None.
            namespace=struct('available',false,'kind','unavailable','fusionMode','none', ...
                'resolvedFeatureCount',0,'projectionFeatureCount',0, ...
                'physicalVarinds',[],'physicalFeatureCounts',[], ...
                'modalityVarinds',[],'selectedContextIsCombined',false, ...
                'namesAvailable',false,'nameSource','none','names',{{}});
        end

        function namespace=featureNamespaceForAnalysis(NM,analysisIndex,featurePayload)
            % Purpose: Project one already-resolved Feature Inspection annotation into analysis-level Scientific State namespace metadata.
            % Syntax: namespace = NMResultsViewerScientificState.featureNamespaceForAnalysis(NM,analysisIndex,featurePayload)
            % Inputs: NM is read-only; analysisIndex identifies the owning analysis; featurePayload is the already-built metadata payload/annotation.
            % Outputs: Compact namespace immediately consumable by Tabulator/Report/other downstream Scientific State clients.
            % Authority and flow: Non-stacking modality/fusion topology is consumed from Scientific Annotation material. Stacker identity is also consumed from Annotation; only its compact analysis-local names are materialized from visdata.params.features because that feature axis is not a DataIO namespace.
            % Scientific/state contract: No consumer-side FUSION.M, STACKING.flag, or NM.featnames reconstruction is performed here; early/intermediate fusion consumes the Annotation-owned first-member projection namespace without inventing post-preprocessing blocks.
            % Invariants: Stacker feature names are one-to-one with resolvedFeatureCount. A count mismatch is a state integrity error.
            % Materialization and performance: O(number of Annotation modality records) metadata plus O(number of stacker child features) only for stackers; no raw feature arrays/files/resources are loaded.
            % Failure semantics: Invalid annotation or stacker namespace shapes fail explicitly.
            % Side effects: None.
            namespace=NMResultsViewerScientificState.featureNamespaceTemplate();
            annotation=featurePayload.scientificAnnotation;
            if ~strcmp(annotation.domain,'feature_inspection'), return; end
            material=annotation.material;
            namespace.available=true;
            namespace.fusionMode=material.fusionMode;
            namespace.resolvedFeatureCount=sum(double(material.physicalFeatureCounts));
            namespace.projectionFeatureCount=namespace.resolvedFeatureCount;
            namespace.physicalVarinds=double(material.physicalVarinds(:)');
            namespace.physicalFeatureCounts=double(material.physicalFeatureCounts(:)');
            namespace.modalityVarinds=double(material.modalityVarinds(:)');
            namespace.selectedContextIsCombined=logical(material.selectedContextIsCombined);
            if strcmp(namespace.fusionMode,'early')
                contexts=featurePayload.featureContexts;
                enabled=logical([contexts.enabled]);
                combined=contexts(enabled & logical([contexts.isCombined]));
                if numel(combined)>1
                    error('NMResultsViewerScientificState:InvalidFusionNamespace', ...
                        'Early-fusion Scientific State resolved more than one virtual combined feature context.');
                elseif numel(combined)==1
                    namespace.projectionFeatureCount=double(combined.nFeatures);
                else
                    physical=contexts(enabled & ~logical([contexts.isCombined]));
                    namespace.projectionFeatureCount=sum(double([physical.nFeatures]));
                end
                if ~isscalar(namespace.projectionFeatureCount) || ~isfinite(namespace.projectionFeatureCount) || ...
                        namespace.projectionFeatureCount<1 || namespace.projectionFeatureCount~=round(namespace.projectionFeatureCount) || ...
                        (namespace.selectedContextIsCombined && namespace.projectionFeatureCount~=namespace.resolvedFeatureCount)
                    error('NMResultsViewerScientificState:InvalidFusionNamespace', ...
                        'Early-fusion Scientific State has inconsistent selected and virtual projection feature counts.');
                end
            end
            namespace.namesAvailable=material.featureNamesAvailable;
            namespace.nameSource=material.featureNameSource;
            isStacking=strcmp(namespace.nameSource,'analysis.visdata.params.features');
            if isStacking
                A=NM.analysis{analysisIndex};
                namespace.kind='stacking';
                namespace.modalityVarinds=[];
                rows=double(material.physicalVisRowIndices(:)');
                if numel(rows)~=1
                    error('NMResultsViewerScientificState:InvalidStackingNamespace','Stacking Scientific State requires exactly one resolved VIS namespace row.');
                end
                target=round(double(material.resultTargetIndex));
                row=round(rows(1));
                names=A.visdata{row,target}.params.features(:);
                if numel(names)~=namespace.resolvedFeatureCount
                    error('NMResultsViewerScientificState:InvalidStackingNamespace', ...
                        'Stacking namespace contains %d names but the resolved feature space contains %d features.',numel(names),namespace.resolvedFeatureCount);
                end
                namespace.namesAvailable=true;
                namespace.nameSource='analysis.visdata.params.features';
                namespace.names=names';
                return;
            end
            switch namespace.fusionMode
                case 'early', namespace.kind='early_fusion';
                case 'intermediate', namespace.kind='intermediate_fusion';
                case 'late', namespace.kind='late_fusion';
                otherwise, namespace.kind='modality';
            end
        end


        function state=forAnalysisSet(NM,analysisIndices,spec)
            % Purpose: Build a compact multi-analysis Scientific State inventory for an explicit set of completed analyses.
            % Syntax: state = NMResultsViewerScientificState.forAnalysisSet(NM,analysisIndices,spec)
            % Inputs: NM is read-only; analysisIndices is the explicit requested analysis set; spec carries ordinary Results Viewer selector coordinates.
            % Outputs: Scientific State with scope.type=analysis_set, per-analysis capability/result-type inventory, established effective default Performance type, Model Optimization criterion identity, and CV-equivalence groups.
            % Authority and flow: Analysis identity/completion comes from NMResultsViewerTools.listAnalyses; per-analysis capabilities come from the compact inventory mode of the same NMResultsViewerTools.resultTypesForAnalysis authority used by the normal Result Type selector; optimization-criterion identity comes from NMResultsViewerTools.modelOptimizationCriterionIdentity; CV equality remains exclusively delegated to nk_GetAnalysisStatus.
            % Scientific/state contract: analysis_set is an availability inventory, not N copies of fully materialized single-analysis State. Detailed Scientific Annotation, artefacts, visualizations and featureNamespace remain owned by the single-analysis State and are materialized only when a consumer enters that analysis/result context.
            % Invariants: Only explicitly requested completed analyses are admitted; set order follows the canonical Results Viewer catalogue and is duplicate-free; capability/result-type semantics remain owned by resultTypesForAnalysis; one cvGroup means analyses are equal according to nk_GetAnalysisStatus.betweenequal_cv.
            % Materialization and performance: O(A) compact availability inspection plus the existing delegated CV-equivalence grouping. It does not construct Performance, Optimization or Feature Inspection payloads for every selected analysis and does not build/discard N single-analysis Scientific State objects.
            % Interactive/retained use: Safe for the retained shared Analysis Set selector because it stores compact capability, criterion-identity and CV-group metadata only.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays. Detailed per-analysis state remains lazy.
            % Failure semantics: Invalid/incomplete analysis ids and missing canonical CV authority remain explicit errors; no alternate scientific-state interpretation is introduced.
            % Side effects: None; NM is not mutated.
            % Consumers and dependencies: Shared Analysis Set selector, Cross-analysis consumers and multi-analysis Report Builder; NMResultsViewerTools.listAnalyses/resultTypesForAnalysis and nk_GetAnalysisStatus.
            catalogue=NMResultsViewerTools.listAnalyses(NM);
            indices=NMResultsViewerTools.canonicalCompletedAnalysisSet(catalogue,analysisIndices);
            groups=NMResultsViewerScientificState.cvEquivalenceGroups(NM,indices);
            criterionTemplate=struct('key','','code',NaN,'label','','shortLabel','','metricId','', ...
                'scale',struct('mode','data','minimum',NaN,'maximum',NaN,'referenceValue',NaN,'referenceLabel',''));
            itemTemplate=struct('analysisIndex',0,'analysisId','','label','','mode','', ...
                'capabilities',struct('modelPerformance',false,'modelOptimization',false,'featureInspection',false,'interpretation',false), ...
                'resultTypes',struct([]),'effectivePerformanceResultType','','optimizationCriterion',criterionTemplate, ...
                'featureNamespace',NMResultsViewerScientificState.featureNamespaceTemplate(), ...
                'targetState',NMResultsViewerScientificState.targetStateTemplate(),'cvGroup',0);
            inventory=repmat(itemTemplate,1,numel(indices));
            aggregate=NMResultsViewerScientificState.fromPayloads({},spec);
            records=repmat(struct('reference',[],'scientificAnnotation',NMResultsViewerScientificAnnotation.template()),1,0);
            for ii=1:numel(indices)
                idx=indices(ii);row=catalogue([catalogue.index]==idx);row=row(1);
                localSpec=spec;localSpec.analysisIndex=idx;localSpec.AnalysisIndex=idx;
                types=NMResultsViewerTools.resultTypesForAnalysis(NM,idx,localSpec,catalogue);
                inventory(ii).analysisIndex=idx;inventory(ii).analysisId=row.id;inventory(ii).label=row.title;inventory(ii).mode=row.mode;inventory(ii).resultTypes=types;inventory(ii).effectivePerformanceResultType=NMResultsViewerTools.defaultPerformanceResultType(NM,idx,types);inventory(ii).optimizationCriterion=NMResultsViewerTools.modelOptimizationCriterionIdentity(NM,idx);inventory(ii).cvGroup=groups(ii);inventory(ii).targetState=NMResultsViewerScientificState.targetStateForAnalysis(NM,idx);
                inventory(ii).capabilities.modelPerformance=any([types(1:min(2,numel(types))).enabled]);
                if numel(types)>=3,inventory(ii).capabilities.modelOptimization=logical(types(3).enabled);end
                if numel(types)>=4,inventory(ii).capabilities.featureInspection=logical(types(4).enabled);end
                if numel(types)>=5,inventory(ii).capabilities.interpretation=logical(types(5).enabled);end
            end
            fields={'modelPerformance','modelOptimization','featureInspection','interpretation'};
            shared=struct();available=struct();
            for ff=1:numel(fields)
                values=arrayfun(@(x)logical(x.capabilities.(fields{ff})),inventory);
                shared.(fields{ff})=all(values);available.(fields{ff})=sum(values);
            end
            aggregate.scope=struct('type','analysis_set','analysisIndices',indices,'identity',sprintf('analysis_set:%s',strjoin(arrayfun(@num2str,indices,'UniformOutput',false),',')));
            aggregate.inventory=inventory;
            criterionKeys=arrayfun(@(x)x.optimizationCriterion.key,inventory,'UniformOutput',false);
            aggregate.inventorySummary=struct('analysisCount',numel(indices),'sharedCapabilities',shared,'availableCounts',available,'cvGroupCount',numel(unique(groups)),'optimizationCriterionCount',numel(unique(criterionKeys)));
            aggregate.directory=NMResultsViewerScientificDirectory.build(records);
            state=aggregate;
        end
    end

    methods (Static)
        function targetState=targetStateForAnalysis(NM,idx)
            % targetStateForAnalysis  Effective native-target cardinality for one analysis.
            % Scientific State owns target cardinality independently of task type.
            opts=NMResultsViewerTools.targetOptions(NM,idx);
            enabled=false(1,numel(opts));
            for tt=1:numel(opts)
                enabled(tt)=logical(opts(tt).enabled);
            end
            active=opts(enabled);
            targetState=NMResultsViewerScientificState.targetStateTemplate();
            targetState.cardinality=numel(active);
            targetState.isMultiTarget=targetState.cardinality>1;
            if ~isempty(active)
                targetState.nativeIndices=reshape([active.nativeIndex],1,[]);
                targetState.resultIndices=reshape([active.resultIndex],1,[]);
            end
            if targetState.cardinality==1
                targetState.soleNativeIndex=targetState.nativeIndices(1);
                targetState.soleResultIndex=targetState.resultIndices(1);
            end
        end

        function targetState=targetStateTemplate()
            targetState=struct('cardinality',0,'isMultiTarget',false, ...
                'nativeIndices',[],'resultIndices',[], ...
                'soleNativeIndex',[],'soleResultIndex',[]);
        end

    end

    methods (Static, Access=private)
        function [artefacts,visualizations]=addProvides(artefacts,visualizations,provides,key,baseSchema,providerId,sourceIds,materialized,payload)
            for pp=1:numel(provides)
                p=provides(pp); schema=baseSchema;
                if strcmp(p.kind,'scientific_artefact')
                    schema.payload.family=p.family; schema.payload.type=p.type;
                    if any(strcmp(p.id,{'voxel_feature_map','surface_feature_map','connectivity_feature_map','roi_feature_map'}))
                        kinds=struct('voxel_feature_map','voxel','surface_feature_map','surface_vertex', ...
                            'connectivity_feature_map','connectivity_edge','roi_feature_map','roi');
                        schema.featureSpace.kind=kinds.(p.id);
                    end
                    if ~NMResultsViewerScientificState.entryExists(artefacts,key,p.id)
                        a=NMResultsViewerScientificState.artefactTemplate(); a.id=p.id; a.contextKey=key;
                        isMaterialized=logical(materialized)&&NMResultsViewerScientificState.provideMaterialized(payload,p);
                        a.status='DERIVABLE'; if isMaterialized,a.status='EXISTS';end
                        a.materialized=isMaterialized; a.schema=schema; a.providerId=providerId; a.sourceIds=sourceIds;
                        artefacts(end+1)=a; %#ok<AGROW>
                    end
                elseif ~NMResultsViewerScientificState.entryExists(visualizations,key,p.id)
                    v=NMResultsViewerScientificState.visualizationTemplate(); v.id=p.id; v.contextKey=key;
                    v.status='VISUALIZABLE'; v.schema=schema; v.providerId=providerId; v.sourceIds=sourceIds;
                    visualizations(end+1)=v; %#ok<AGROW>
                end
            end
        end

        function tf=provideMaterialized(payload,provide)
            tf=true;
            kind=payload.kind;
            if strcmp(kind,'mli')
                tf=ismember(provide.id,{'mli_payload','mli_subject_relevance'});
                return;
            end
            if ~strcmp(kind,'model_feature_inspection'), return; end
            if ~strcmp(payload.payloadScope,'metadata'), return; end
            tf=strcmp(provide.id,'feature_fractionated_decision') || ...
                ismember(provide.id,{'feature_inspection_payload','feature_modality_contribution','feature_component_summary','feature_component_modality'});
        end

        function [tf,ids,schema]=resolveSources(artefacts,key,needs,schema)
            tf=true; ids={}; inherited=false;
            contextMask=strcmp({artefacts.contextKey},key);
            for nn=1:numel(needs)
                hit=[]; id='';
                for jj=1:numel(needs{nn})
                    id=needs{nn}{jj};
                    hit=find(contextMask&strcmp({artefacts.id},id),1);
                    if ~isempty(hit), break; end
                end
                if isempty(hit), tf=false; ids={}; return; end
                ids{end+1}=id; %#ok<AGROW>
                if ~inherited,schema=artefacts(hit).schema;inherited=true;end
            end
        end

        function tf=entryExists(entries,key,id)
            tf=any(strcmp({entries.contextKey},key)&strcmp({entries.id},id));
        end

        function tf=hasEntry(state,field,id,criteria)
            entries=state.(field); tf=false;
            if isempty(criteria)
                for ii=1:numel(entries)
                    if strcmp(entries(ii).id,id),tf=true;return;end
                end
                return;
            end
            for ii=1:numel(entries)
                if strcmp(entries(ii).id,id)&&NMResultsViewerScientificDirectory.matchesSchema(entries(ii).schema,criteria)
                    tf=true;return;
                end
            end
        end

        function key=contextKey(payload,position)
            % Purpose: Build a deterministic runtime identity for one materialized scientific payload context.
            % Syntax: key = NMResultsViewerScientificState.contextKey(payload,position)
            % Inputs: payload is an already-materialized Results Viewer payload; position is its deterministic position in the supplied payload sequence.
            % Outputs: key is a compact string identity covering result family, analysis/target/model/source/subgroup and multi-class contrast coordinates from Scientific Annotation.
            % Authority and flow: Reads scientific classContrast/classIndex/source coordinates only from payload.scientificAnnotation.schema; it does not infer them from UI or alternate payload fields.
            % Scientific/state contract: Aggregate multi-class and each class-vs-REST artefact receive distinct context identities even when other selectors are identical.
            % Invariants: Context identity is derived from the fixed Results Viewer payload and Scientific Annotation contracts; no raw NM/result-container traversal or schema rediscovery is permitted here.
            % Materialization and performance: O(1) metadata serialization; no files, XML, atlas/annotation/mesh resources, feature-scale scans, hashes, or large allocations.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact scientific metadata only and safe on interactive state/annotation paths.
            % Failure semantics: Invalid payload/annotation contracts fail at their owning producer/boundary rather than being repaired here.
            % Side effects: None.
            % Consumers and dependencies: Scientific State artefact construction and context/reference linking.
            schema=payload.scientificAnnotation.schema;
            source=schema.source.id;
            if isempty(source),source='cv';end
            modelSource=schema.source.modelSource;
            subgroup=double(schema.source.subgroupIndex);
            classContrast=schema.target.classContrast;
            classIndex=0;
            if isfinite(schema.target.classIndex),classIndex=round(double(schema.target.classIndex));end
            subgroupToken='na';if isfinite(subgroup),subgroupToken=sprintf('%d',round(subgroup));end
            key=sprintf('%s|a%d|t%d|m%d|s%s|ms%s|sg%s|cc%s|cl%d|r%d', ...
                payload.kind,round(double(payload.analysisIndex)),round(double(payload.targetIndex)), ...
                round(double(payload.classifierIndex)),source,modelSource,subgroupToken,classContrast,classIndex,position);
        end

        function groups=cvEquivalenceGroups(NM,indices)
            % Purpose: Partition an explicit analysis set into CV-equivalence classes using the existing nk_GetAnalysisStatus authority.
            % Syntax: groups = NMResultsViewerScientificState.cvEquivalenceGroups(NM,indices)
            % Inputs: Read-only NM and deterministic analysis indices.
            % Outputs: Positive integer group id aligned one-to-one with indices.
            % Authority and flow: Calls nk_GetAnalysisStatus for pairwise representative comparisons and consumes only Status.betweenequal_cv; no TrainInd/CV structure is read or compared here.
            % Scientific/state contract: Group identity is inventory metadata reflecting the existing CV-status authority, not a new CV definition.
            % Invariants: First occurrence defines each group representative; equal analyses receive the same group; ids are consecutive in encounter order.
            % Materialization and performance: O(A^2) compact status calls in the worst case; no result payload or feature-scale materialization.
            % Failure semantics: Missing nk_GetAnalysisStatus is an explicit authority error for multi-analysis inventory.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays; all CV semantics remain delegated to nk_GetAnalysisStatus. Suitable for explicit inventory queries, not retained interaction.
            % Side effects: None.
            % Consumers and dependencies: forAnalysisSet only; depends exclusively on nk_GetAnalysisStatus for CV-equivalence truth.
            groups=zeros(1,numel(indices));
            if isempty(indices),return;end
            if numel(indices)==1,groups(1)=1;return;end
            representatives=[];
            for ii=1:numel(indices)
                assigned=false;
                for gg=1:numel(representatives)
                    status=nk_GetAnalysisStatus(NM,[representatives(gg) indices(ii)]);
                    if status.betweenequal_cv
                        groups(ii)=gg;assigned=true;break;
                    end
                end
                if ~assigned
                    representatives(end+1)=indices(ii); %#ok<AGROW>
                    groups(ii)=numel(representatives);
                end
            end
        end

        function a=artefactTemplate()
            annotation=NMResultsViewerScientificAnnotation.template();
            a=struct('id','','contextKey','','status','','materialized',false,'schema',annotation.schema, ...
                'providerId','','sourceIds',{{}});
        end

        function v=visualizationTemplate()
            annotation=NMResultsViewerScientificAnnotation.template();
            v=struct('id','','contextKey','','status','','schema',annotation.schema, ...
                'providerId','','sourceIds',{{}});
        end
    end
end

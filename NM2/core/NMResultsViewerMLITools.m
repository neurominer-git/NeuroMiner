classdef NMResultsViewerMLITools
% NMResultsViewerMLITools
% -------------------------------------------------------------------------
% Authoritative Results Viewer adapter for persisted NM 1.4/NM2 machine-
% learning interpretation (MLI) results.
%
% Purpose:
%   Resolve one analysis/source/target/classifier/feature-source/subject MLI
%   selection and expose only the selected subject x feature relevance vector
%   plus compact metadata required by the Results Viewer.
%
% Scientific/state contract:
%   MLI uses the Feature Inspection scientific coordinates for analysis,
%   source, target, classifier and feature source, but component.applicable is
%   always false. MLI relevance is persisted in the mapped/original feature
%   space and is never selected or inferred component-wise.
%
% Authority and flow:
%   NM.analysis{a}.MLI and NM.analysis{a}.OOCV{o}.MLI are the only relevance
%   authorities. DataIO datadescriptors are the only feature-provenance and
%   spatial-domain authority. Subject rows are resolved by explicit unique case
%   id/index against NM.cases or NM.OOCV{o}.cases. The method never derives a
%   subject from visual point order.
%
% Materialization/performance:
%   Metadata catalogue construction is O(M), where M is the number of stored
%   MLI modalities. The first interactive payload performs one O(S x F) extrema
%   scan over the selected persisted relevance block(s) to establish a stable
%   cross-subject display range, but does not concatenate, copy or serialize the
%   complete matrix. The resulting two-number range is reused by exact scientific
%   context identity. A subject request otherwise extracts O(F) values for only
%   the selected modality. The subject catalogue is serialized O(S) only when
%   explicitly requested; retained subject updates validate the supplied case
%   id/index directly and omit that catalogue. Spatial reconstruction is delegated
%   to the shared Results Viewer feature-vector adapters and resident caches.
%
% Failure semantics:
%   Missing/ambiguous persisted dimensions, duplicate subject IDs, unavailable
%   feature provenance and invalid selector coordinates fail explicitly. There
%   does not substitute VIS, feature-count heuristics, visual ordering or a
%   component axis.
% -------------------------------------------------------------------------

    methods (Static)
        function payload = getPayload(NM, spec)
            % getPayload  Resolve one authoritative subject-level MLI payload.
            %
            % Persisted MLI results own relevance material. Completed-analysis
            % snapshots own method/fusion/target semantics. DataIO authorities own
            % case identity and modality provenance. Reader-local schema discovery
            % is not part of this path.
            if NMResultsViewerScientificCapability.isQuery(NM)
                P=@NMResultsViewerScientificCapability.provide;
                all=[P('mli_payload','scientific_artefact','ml_interpretation','mli_payload'), ...
                    P('mli_subject_relevance','scientific_artefact','ml_interpretation','subject_relevance'), ...
                    P('voxel_feature_map','scientific_artefact','ml_interpretation','voxel_feature_map'), ...
                    P('surface_feature_map','scientific_artefact','ml_interpretation','surface_feature_map'), ...
                    P('roi_feature_map','scientific_artefact','ml_interpretation','roi_feature_map'), ...
                    P('mli_profile','visualization','',''),P('spatial_feature_map_summary','visualization','','')];
                ids={all.id};
                % nm2-allow: overloaded capability provider boundary distinguishes default interrogation from context interrogation
                if nargin==2
                    q=spec.payload;
                    ids={};
                    if strcmp(q.kind,'mli') && q.ok
                        ids={'mli_payload','mli_subject_relevance','mli_profile'};
                        if ~isempty(q.spatialMaps)
                            sp=q.spatialMaps(1);
                            if sp.enabled
                                ids{end+1}='spatial_feature_map_summary'; %#ok<AGROW>
                                switch sp.mapKind
                                    case 'voxel', ids{end+1}='voxel_feature_map'; %#ok<AGROW>
                                    case 'surface_vertex', ids{end+1}='surface_feature_map'; %#ok<AGROW>
                                    case 'roi', ids{end+1}='roi_feature_map'; %#ok<AGROW>
                                end
                            end
                        end
                    end
                end
                payload=NMResultsViewerScientificCapability.contract('mli',{}, ...
                    NMResultsViewerScientificCapability.subset(all,unique(ids,'stable')));
                return;
            end

            payload=NMResultsViewerMLITools.emptyPayload();
            % One typed Results Viewer specification (idempotent for already canonical specs).
            [~,spec]=NMResultsViewerTools.viewerPlotOptions(spec);
            % MLI's own resolutions: an unspecified analysis is analysis 1, an unspecified native target is the
            % result target, and an empty source selector is cross-validation.
            idx=spec.analysisIndex;if ~isfinite(idx),idx=1;end
            targetResultIndex=spec.targetIndex;
            targetNativeIndex=spec.targetNativeIndex;if ~isfinite(targetNativeIndex),targetNativeIndex=targetResultIndex;end
            classifierIndex=spec.classifierIndex;
            source=spec.source;if isempty(source),source='cv';end
            payload.analysisIndex=idx;payload.targetIndex=targetResultIndex;payload.resultTargetIndex=targetResultIndex;
            payload.targetNativeIndex=targetNativeIndex;payload.classifierIndex=classifierIndex;
            payload.requestedSource=source;payload.selectedSource=source;payload.source=source;
            if idx<1
                payload.message='The selected analysis is unavailable.';return;
            end
            if idx>numel(NM.analysis)
                payload.message='The selected analysis is unavailable.';return;
            end
            A=NM.analysis{idx};
            [root,sourceCases,sourceKind,oocvIndex,msg]=NMResultsViewerMLITools.resolveRoot(NM,A,source);
            payload.sourceKind=sourceKind;
            if strcmp(sourceKind,'oocv'),payload.oocv=struct('ok',true,'requestedGlobalIndex',oocvIndex);end
            if isempty(root),payload.message=msg;return;end
            method=NMResultsViewerMLITools.methodForAnalysis(A);
            payload.method=method;payload.methodLabel=NMResultsViewerMLITools.methodLabel(method);
            fusionMode=NMResultsViewerMLITools.fusionMode(A);payload.fusionMode=fusionMode;
            [contexts,entries,descriptors,msg]=NMResultsViewerMLITools.contextCatalogue(NM,A,root,idx,targetResultIndex,classifierIndex,fusionMode,method);
            if isempty(contexts),payload.message=msg;return;end
            payload.featureContexts=contexts;
            selectedId=spec.featureContextId;
            if isempty(selectedId)
                modelSource=spec.modelSource;
                if startsWith(modelSource,'modality:')
                    modelIndex=str2double(extractAfter(modelSource,'modality:'));
                    hit=find([contexts.modalityIndex]==modelIndex & [contexts.enabled],1,'first');
                    if ~isempty(hit),selectedId=contexts(hit).contextId;end
                end
            end
            if isempty(selectedId)
                hit=find([contexts.enabled]&[contexts.isCombined],1,'first');
                if isempty(hit),hit=find([contexts.enabled],1,'first');end
            else
                hit=find(strcmp({contexts.contextId},selectedId)&[contexts.enabled],1,'first');
                if isempty(hit)
                    payload.message=sprintf('MLI feature source %s is unavailable for the selected scientific context.',selectedId);return;
                end
            end
            if isempty(hit),payload.message='No enabled MLI feature source is available.';return;end
            ctx=contexts(hit);
            [physicalContexts,selectedEntries]=NMResultsViewerMLITools.selectedPhysicalEntries(contexts,entries,ctx);
            payload.contexts=physicalContexts;payload.selectedFeatureContext=ctx;payload.selectedFeatureContextId=ctx.contextId;
            measure=NMResultsViewerMLITools.measureForMethod(method,ctx.contextId);
            nSubjects=NMResultsViewerMLITools.subjectCount(selectedEntries,measure.sourceField);
            nSourceCases=NMResultsViewerMLITools.caseCount(sourceCases);
            if nSourceCases~=nSubjects
                payload.message=sprintf('MLI subject dimension (%d) does not match the authoritative %s case list (%d).',nSubjects,sourceKind,nSourceCases);return;
            end
            [displayRange,displayRangeIdentity,displayPolarity]=NMResultsViewerMLITools.globalDisplayRange( ...
                selectedEntries,measure.sourceField,[physicalContexts.nFeatures],nSubjects,spec,idx,source,targetResultIndex,classifierIndex,ctx.contextId,method);
            measure.displayValueRange=displayRange;measure.displayRangeMode='full_data_range';measure.valuePolarity=displayPolarity;
            payload.displayValueRange=displayRange;payload.displayRangeIdentity=displayRangeIdentity;
            payload.measures=measure;payload.selectedMeasureId=measure.measureId;
            payload.spatialMaps=NMResultsViewerMLITools.spatialMap(NM,ctx,measure,descriptors{hit});
            [caseIndex,caseId,msg]=NMResultsViewerMLITools.resolveSubject(sourceCases,spec,nSubjects);
            if caseIndex<1 && ~isempty(msg),payload.message=msg;return;end
            % nm2-allow: mliIncludeSubjectCatalogue is written only by NMResultsViewerUI_main.js subject refreshes and imagingRequest (false); absent means the catalogue is wanted.
            includeSubjectCatalogue=~isfield(spec,'mliIncludeSubjectCatalogue')||logical(spec.mliIncludeSubjectCatalogue);
            if includeSubjectCatalogue
                scoreCatalogue=NMResultsViewerTools.modelInterpretationSubjectScores(NM,spec);
                payload.subjects=NMResultsViewerMLITools.subjectOptions(sourceCases,scoreCatalogue);
                payload.subjectOrderingAvailable=scoreCatalogue.ok;
                payload.subjectOrderingMessage=scoreCatalogue.message;
                payload.subjectScoreLabel=scoreCatalogue.scoreLabel;
                payload.subjectExpectedLabel=scoreCatalogue.expectedLabel;
                payload.subjectPredictedLabel=scoreCatalogue.predictedLabel;
            end
            payload.selectedSubjectIndex=caseIndex;payload.selectedSubjectCaseId=caseId;
            if caseIndex==0
                payload.scientificAnnotation=NMResultsViewerMLITools.annotation(ctx,physicalContexts,payload,measure,A,NM);
                payload.resolvedSelection=NMResultsViewerMLITools.resolvedSelection(ctx,physicalContexts,payload,measure);
                payload.message='Select a subject to view model interpretation.';
                payload.ok=true;
                return;
            end
            values=NMResultsViewerMLITools.concatenateRows(selectedEntries,measure.sourceField,caseIndex,[physicalContexts.nFeatures]);
            if numel(values)~=ctx.nFeatures
                payload.message=sprintf('Stored MLI vector contains %d values but feature source %s declares %d features.',numel(values),ctx.contextId,ctx.nFeatures);return;
            end
            payload.relevanceValues=values;
            payload.featureNames=NMResultsViewerMLITools.featureNamesForSelection(selectedEntries,physicalContexts,ctx);
            payload.featureNamesPersisted=NMResultsViewerMLITools.persistedFeatureNamesAvailable(selectedEntries,physicalContexts);
            if ~strcmp(method,'shapley')
                payload.relevanceCIUpper=NMResultsViewerMLITools.concatenateRows(selectedEntries,'Y_mapped_ciu',caseIndex,[physicalContexts.nFeatures]);
                payload.relevanceCILower=NMResultsViewerMLITools.concatenateRows(selectedEntries,'Y_mapped_cil',caseIndex,[physicalContexts.nFeatures]);
                payload.relevanceStd=NMResultsViewerMLITools.concatenateRows(selectedEntries,'Y_mapped_std',caseIndex,[physicalContexts.nFeatures]);
                payload.nonSignificantMask=abs(payload.relevanceCIUpper)>abs(payload.relevanceValues);
            end
            [profileValues,profileAvailable,profileMessage]=NMResultsViewerMLITools.subjectFeatureValuesForSelection(NM,selectedEntries,physicalContexts,caseIndex,sourceKind);
            payload.subjectFeatureValues=profileValues;payload.subjectFeatureValuesAvailable=profileAvailable;payload.subjectFeatureValuesMessage=profileMessage;
            payload.scientificAnnotation=NMResultsViewerMLITools.annotation(ctx,physicalContexts,payload,measure,A,NM);
            payload.resolvedSelection=NMResultsViewerMLITools.resolvedSelection(ctx,physicalContexts,payload,measure);
            payload.ok=true;
            payload.message=sprintf('Model interpretation: %s, subject %s, %d features.',payload.methodLabel,caseId,ctx.nFeatures);
        end
        function selection=getAdapterSelection(spec,payload)
            % getAdapterSelection  Bind one successful physical MLI payload to the shared spatial-adapter contract.
            if ~strcmp(payload.kind,'mli') || ~payload.ok
                error('NMResultsViewerMLITools:InvalidPayload','MLI spatial adapter selection requires one successful mli payload.');
            end
            if numel(payload.contexts)~=1
                error('NMResultsViewerMLITools:InvalidContext','MLI spatial adapter selection requires exactly one physical feature context.');
            end
            requested=payload.selectedMeasureId;
            % nm2-allow: public representation request boundary accepts the documented measureIds transport forms
            if isfield(spec,'measureIds') && ~isempty(spec.measureIds)
                raw=spec.measureIds;
                % nm2-allow: public representation request boundary validates one external measure identifier
                if iscell(raw)
                    if numel(raw)~=1,error('NMResultsViewerMLITools:InvalidMeasure','MLI exposes exactly one method-defined relevance measure.');end
                    raw=raw{1};
                end
                % nm2-allow: public representation request boundary validates MATLAB character/string transport
                if isstring(raw)
                    if ~isscalar(raw),error('NMResultsViewerMLITools:InvalidMeasure','MLI exposes exactly one method-defined relevance measure.');end
                    raw=char(raw);
                % nm2-allow: public representation request boundary rejects non-text measure identifier transport
                elseif ~ischar(raw)
                    error('NMResultsViewerMLITools:InvalidMeasure','MLI measureIds must contain one text identifier.');
                end
                requested=raw;
            % nm2-allow: public representation request boundary accepts the optional singular measureId selector
            elseif ~isempty(spec.measureId)
                requested=spec.measureId;
            end
            if ~strcmp(requested,payload.selectedMeasureId)
                error('NMResultsViewerMLITools:InvalidMeasure','MLI exposes exactly one method-defined relevance measure.');
            end
            selection=struct('scientificContractVersion',payload.scientificContractVersion,'scientificAnnotation',payload.scientificAnnotation, ...
                'resolvedSelection',payload.resolvedSelection,'context',payload.contexts,'measureIds',{{requested}},'measures',payload.measures);
        end
        function out=getFeatureVector(NM,spec,measureId,payload) %#ok<INUSD>
            % getFeatureVector  Expose the selected MLI relevance row as the canonical shared spatial feature vector.
            out=struct('ok',false,'message','','scientificContractVersion','','scientificAnnotation',struct(),'resolvedSelection',struct(), ...
                'analysisIndex',0,'targetIndex',0,'resultTargetIndex',NaN,'classifierIndex',0,'context',struct(),'measure',struct(),'spatialMap',struct(), ...
                'component',struct('componentId','','componentIndex',NaN,'componentLabel',''),'values',[],'badcoords',[],'diagnostic',struct());
            if ~payload.ok,out.message=payload.message;return;end
            if ~isempty(measureId) && ~strcmp(measureId,payload.selectedMeasureId)
                out.message='Requested MLI measure does not match the method-defined relevance payload.';return;
            end
            if numel(payload.contexts)~=1,out.message='Combined tabular MLI contexts are not spatial feature-vector materializations.';return;end
            out.scientificContractVersion=payload.scientificContractVersion;out.scientificAnnotation=payload.scientificAnnotation;out.resolvedSelection=payload.resolvedSelection;
            out.analysisIndex=payload.analysisIndex;out.targetIndex=payload.targetIndex;out.resultTargetIndex=payload.resultTargetIndex;out.classifierIndex=payload.classifierIndex;
            out.context=payload.contexts;out.measure=payload.measures;if ~isempty(payload.spatialMaps),out.spatialMap=payload.spatialMaps(1);end
            out.values=double(payload.relevanceValues(:));
            descriptor=NMResultsViewerImagingDescriptorAdapter.resolve(NM,out.context.varind,struct());
            if descriptor.ok,out.badcoords=descriptor.badcoords;end
            out.ok=true;out.message=sprintf('Resolved MLI vector %s with %d values.',payload.selectedMeasureId,numel(out.values));
        end
        function tf=hasStoredResult(NM,analysisIndex,source)
            % hasStoredResult  Test whether one analysis/source owns a persisted MLI Label result.
            tf=false;
            if analysisIndex<1,return;end
            if analysisIndex>numel(NM.analysis),return;end
            A=NM.analysis{analysisIndex};
            [isOOCV,k]=NMResultsViewerTools.parseOOCVSourceId(source);
            if ~isOOCV
                if ~strcmp(source,'cv'),return;end
                % nm2-allow: nk_MLInterpreterPrep conditionally writes analysis.MLI only after CV interpretation execution
                if ~isfield(A,'MLI') || isempty(A.MLI),return;end
                tf=~isempty(A.MLI.Label);
                return;
            end
            % nm2-allow: nk_MLInterpreterPrep writes analysis.OOCV only for application interpretation results
            if ~isfield(A,'OOCV'),return;end
            if k<1,return;end
            if k>numel(A.OOCV),return;end
            if isempty(A.OOCV{k}),return;end
            % nm2-allow: nk_MLInterpreterPrep conditionally writes one OOCV MLI branch after interpretation execution
            if ~isfield(A.OOCV{k},'MLI') || isempty(A.OOCV{k}.MLI),return;end
            tf=~isempty(A.OOCV{k}.MLI.Label);
        end
        function tf=hasAnyStoredResult(NM,analysisIndex)
            % hasAnyStoredResult  Test whether an analysis owns any persisted CV/OOCV MLI result.
            tf=NMResultsViewerMLITools.hasStoredResult(NM,analysisIndex,'cv');
            if tf,return;end
            if analysisIndex<1,return;end
            if analysisIndex>numel(NM.analysis),return;end
            A=NM.analysis{analysisIndex};
            % nm2-allow: nk_MLInterpreterPrep creates analysis.OOCV only when application results exist
            if ~isfield(A,'OOCV'),return;end
            for k=1:numel(A.OOCV)
                if NMResultsViewerMLITools.hasStoredResult(NM,analysisIndex,sprintf('oocv:%d',k)),tf=true;return;end
            end
        end
        function p=emptyPayload()
            contextTemplate=NMResultsViewerMLITools.contextTemplate();
            measureTemplate=NMResultsViewerMLITools.measureTemplate();
            spatialTemplate=NMResultsViewerMLITools.spatialTemplate();
            subjectTemplate=NMResultsViewerMLITools.subjectTemplate();
            p=struct('ok',false,'kind','mli','schemaVersion',1,'scientificContractVersion','NM-MLI-V1','scientificAnnotation',NMResultsViewerScientificAnnotation.template(), ...
                'resolvedSelection',NMResultsViewerScientificAnnotation.legacyResolvedSelectionTemplate(),'analysisIndex',0,'targetIndex',1,'targetNativeIndex',1,'resultTargetIndex',1,'classifierIndex',1, ...
                'requestedSource','cv','selectedSource','cv','source','cv','sourceKind','cv','oocv',struct(),'fusionMode','none','method','','methodLabel','', ...
                'selectedFeatureContextId','','selectedFeatureContext',contextTemplate,'featureContexts',repmat(contextTemplate,1,0),'contexts',repmat(contextTemplate,1,0), ...
                'selectedMeasureId','','measures',repmat(measureTemplate,1,0),'spatialMaps',repmat(spatialTemplate,1,0), ...
                'subjects',repmat(subjectTemplate,1,0),'selectedSubjectIndex',0,'selectedSubjectCaseId','', ...
                'subjectOrderingAvailable',false,'subjectOrderingMessage','','subjectScoreLabel','Model score','subjectExpectedLabel','Expected class','subjectPredictedLabel','Predicted class', ...
                'displayValueRange',[NaN NaN],'displayRangeIdentity','','featureNames',{{}},'featureNamesPersisted',false,'relevanceValues',[], ...
                'relevanceCIUpper',[],'relevanceCILower',[],'relevanceStd',[],'nonSignificantMask',false(1,0),'subjectFeatureValues',[],'subjectFeatureValuesAvailable',false,'subjectFeatureValuesMessage','', ...
                'backprojectionAvailable',false,'backprojectionComponents',struct([]),'selectedBackprojectionComponentId','','componentApplicable',false,'unsupportedPanels',{{}});
        end
        function [root,cases,kind,oocvIndex,msg]=resolveRoot(NM,A,source)
            root=[];cases={};kind='cv';oocvIndex=0;msg='';
            [isOOCV,oocvIndex]=NMResultsViewerTools.parseOOCVSourceId(source);
            if isOOCV
                kind='oocv';
                % nm2-allow: nk_MLInterpreterPrep creates analysis.OOCV only for application-result branches
                if ~isfield(A,'OOCV'),msg=sprintf('No MLI result is stored for OOCV/application source %d.',oocvIndex);return;end
                if oocvIndex<1,msg=sprintf('No MLI result is stored for OOCV/application source %d.',oocvIndex);return;end
                if oocvIndex>numel(A.OOCV),msg=sprintf('No MLI result is stored for OOCV/application source %d.',oocvIndex);return;end
                if isempty(A.OOCV{oocvIndex}),msg=sprintf('No MLI result is stored for OOCV/application source %d.',oocvIndex);return;end
                % nm2-allow: nk_MLInterpreterPrep conditionally writes the OOCV MLI result branch
                if ~isfield(A.OOCV{oocvIndex},'MLI') || isempty(A.OOCV{oocvIndex}.MLI),msg=sprintf('No MLI result is stored for OOCV/application source %d.',oocvIndex);return;end
                if oocvIndex>numel(NM.OOCV),msg=sprintf('OOCV/application source %d has no authoritative case list.',oocvIndex);return;end
                root=A.OOCV{oocvIndex}.MLI;
                cases=NM.OOCV{oocvIndex}.cases;
                return;
            end
            if ~strcmp(source,'cv'),msg=sprintf('Unsupported MLI source %s.',source);return;end
            % nm2-allow: nk_MLInterpreterPrep conditionally writes analysis.MLI only after CV interpretation execution
            if ~isfield(A,'MLI') || isempty(A.MLI),msg='No CV MLI result is stored for the selected analysis.';return;end
            root=A.MLI;
            if isempty(NM.cases),msg='The CV MLI result has no authoritative NM.cases subject identity list.';root=[];return;end
            cases=NM.cases;
        end
        function method=methodForAnalysis(A)
            % nk_InitAnalysisPrep snapshots TrainParam; nk_MLI_config writes MLI.method.
            method=A.params.TrainParam.MLI.method;
        end
        function label=methodLabel(method)
            if strcmp(method,'shapley'),label='Shapley';else,label=strrep(method,'_',' ');if strcmp(method,'prediction_change'),label='Prediction change';end;end
        end
        function mode=fusionMode(A)
            flag=double(A.params.TrainParam.FUSION.flag);
            switch flag
                case 0,mode='none';
                case 1,mode='early';
                case 2,mode='intermediate';
                case 3,mode='late';
                otherwise,error('NMResultsViewerMLITools:InvalidFusionMode','analysis.params.TrainParam.FUSION.flag must be one of 0, 1, 2 or 3.');
            end
        end
        function [contexts,entries,descriptors,msg]=contextCatalogue(NM,A,root,analysisIndex,targetIndex,classifierIndex,fusionMode,method)
            % contextCatalogue  Resolve persisted MLI modality blocks against normalized DataIO provenance.
            contextTemplate=NMResultsViewerMLITools.contextTemplate();
            contexts=repmat(contextTemplate,1,0);entries={};descriptors={};msg='';
            isRegression=NMResultsViewerMLITools.analysisIsRegression(A);
            measure=NMResultsViewerMLITools.measureForMethod(method,'');
            if strcmp(fusionMode,'late')
                nModalities=size(root.Label,1);
            else
                L=NMResultsViewerMLITools.labelEntry(root,targetIndex,1);
                branch=NMResultsViewerMLITools.modelBranch(L,isRegression,classifierIndex);
                nModalities=numel(branch.Modality);
            end
            if nModalities<1,msg='Stored MLI result contains no modality result.';return;end
            contexts=repmat(contextTemplate,1,nModalities+1);entries=cell(1,nModalities+1);descriptors=cell(1,nModalities+1);
            for m=1:nModalities
                labelRow=1;if strcmp(fusionMode,'late'),labelRow=m;end
                L=NMResultsViewerMLITools.labelEntry(root,targetIndex,labelRow);
                branch=NMResultsViewerMLITools.modelBranch(L,isRegression,classifierIndex);
                if strcmp(fusionMode,'late'),entry=branch.Modality(1);else,entry=branch.Modality(m);end
                varind=double(entry.modality_num);
                descriptor=NMResultsViewerImagingDescriptorAdapter.resolve(NM,varind,struct());
                nFeatures=NMResultsViewerMLITools.featureCount(entry,measure.sourceField);
                ctx=contextTemplate;
                ctx.contextId=sprintf('mli_a%d_t%d_c%d_m%d_v%d',analysisIndex,targetIndex,classifierIndex,m,varind);
                ctx.analysisIndex=analysisIndex;ctx.targetIndex=targetIndex;ctx.resultTargetIndex=targetIndex;ctx.classIndex=classifierIndex;
                ctx.modalityIndex=m;ctx.varind=varind;ctx.modalityLabel=NMResultsViewerMLITools.modalityLabel(NM,varind,m);ctx.selectionLabel=ctx.modalityLabel;
                ctx.fusionMode=fusionMode;ctx.sourceKind='mli';ctx.nFeatures=nFeatures;
                if descriptor.ok
                    ctx.featureKind=descriptor.featureKind;ctx.sourceFamily=descriptor.sourceFamily;
                else
                    ctx.featureKind='';ctx.sourceFamily='';ctx.enabled=false;
                    ctx.disabledReason=sprintf('DataIO provenance is unavailable for modality %d: %s',varind,descriptor.message);
                end
                if strcmp(ctx.featureKind,'roi') && descriptor.roiProvenance.ok
                    projection=NMDataIOROIProvenanceTools.spatialProjection(descriptor.roiProvenance);
                    ctx.roiSidecarAvailable=true;ctx.roiSpatialDomain=projection.spatialDomain;ctx.roiSpatialSemantics=projection.spatialSemantics;
                    ctx.roiIdentityModel=projection.identityModel;ctx.roiSpatialReferenceIdentity=projection.spatialReferenceIdentity;
                    ctx.roiHasAtlasCoordinates=any(all(isfinite(double(descriptor.roiProvenance.mniCoordinates)),2));
                    if strcmp(projection.spatialDomain,'volume')
                        ref=NMDataIOROIProvenanceTools.spatialReference(descriptor.roiProvenance,'volumetric_atlas');
                        if numel(ref.sourceFiles)==1,ctx.roiAtlasFile=ref.sourceFiles{1};end
                    end
                end
                ctx.rendererFamily=NMResultsViewerMLITools.rendererFamily(ctx.featureKind);
                if descriptor.ok
                    ctx.enabled=nFeatures>0;
                    if nFeatures<1,ctx.disabledReason='Stored MLI modality contains no feature-level relevance values.';end
                end
                contexts(m)=ctx;entries{m}=entry;descriptors{m}=descriptor;
            end
            contexts=contexts(1:nModalities);entries=entries(1:nModalities);descriptors=descriptors(1:nModalities);
            [combined,combinedOk]=NMResultsViewerMLITools.combinedContext(contexts,analysisIndex,targetIndex,classifierIndex,fusionMode);
            if combinedOk
                contexts(end+1)=combined; %#ok<AGROW>
                entries{end+1}=struct();descriptors{end+1}=struct(); %#ok<AGROW>
            end
        end
        function L=labelEntry(root,targetIndex,rowIndex)
            if rowIndex<1,error('NMResultsViewerMLITools:InvalidMLILabelCoordinates','MLI row index must be positive.');end
            if targetIndex<1,error('NMResultsViewerMLITools:InvalidMLILabelCoordinates','MLI target index must be positive.');end
            if rowIndex>size(root.Label,1),error('NMResultsViewerMLITools:InvalidMLILabelCoordinates','MLI has no Label(%d,%d).',rowIndex,targetIndex);end
            if targetIndex>size(root.Label,2),error('NMResultsViewerMLITools:InvalidMLILabelCoordinates','MLI has no Label(%d,%d).',rowIndex,targetIndex);end
            L=root.Label(rowIndex,targetIndex);
        end
        function branch=modelBranch(L,isRegression,classifierIndex)
            if isRegression
                if isempty(L.RegrResults),error('NMResultsViewerMLITools:MissingRegressionMLI','Stored MLI target has no RegrResults.');end
                branch=L.RegrResults(1);
                return;
            end
            if classifierIndex<1,error('NMResultsViewerMLITools:MissingClassifierMLI','Stored MLI target has no BinResults classifier %d.',classifierIndex);end
            if classifierIndex>numel(L.BinResults),error('NMResultsViewerMLITools:MissingClassifierMLI','Stored MLI target has no BinResults classifier %d.',classifierIndex);end
            branch=L.BinResults(classifierIndex);
        end
        function tf=analysisIsRegression(A)
            mode=A.params.label.modeflag;
            if strcmp(mode,'regression'),tf=true;return;end
            if strcmp(mode,'classification'),tf=false;return;end
            error('NMResultsViewerMLITools:InvalidAnalysisMode','analysis.params.label.modeflag must be classification or regression.');
        end
        function n=featureCount(entry,field)
            n=size(entry.(field),2);
        end
        % Method-defined MLI fields are fixed by nk_MLInterpreter; no reader-side availability predicate is required.
        function [combined,ok]=combinedContext(physical,analysisIndex,targetIndex,classifierIndex,fusionMode)
            combined=NMResultsViewerMLITools.contextTemplate();ok=false;
            if numel(physical)<2,return;end
            if ~strcmp(fusionMode,'early'),return;end
            enabled=physical([physical.enabled]);
            if numel(enabled)~=numel(physical),return;end
            if any(~strcmp({enabled.featureKind},'tabular')),return;end
            if any(~strcmp({enabled.rendererFamily},'tabular')),return;end
            combined.analysisIndex=analysisIndex;combined.targetIndex=targetIndex;combined.resultTargetIndex=targetIndex;combined.classIndex=classifierIndex;
            combined.modalityIndex=0;combined.varind=0;combined.modalityLabel='Combined feature view';combined.selectionLabel='Combined feature view';combined.fusionMode='early';
            combined.sourceKind='mli_combined';combined.sourceFamily='tabular_concatenation';combined.featureKind='tabular';combined.rendererFamily='tabular';
            combined.nFeatures=sum([enabled.nFeatures]);combined.isCombined=true;combined.memberContextIds={enabled.contextId};
            combined.combinedGroupId=sprintf('mli_a%d_t%d_tabular_concat',analysisIndex,targetIndex);combined.contextId=sprintf('mli_a%d_t%d_combined_c%d',analysisIndex,targetIndex,classifierIndex);
            combined.enabled=true;combined.disabledReason='';ok=true;
        end
        function [physicalContexts,selectedEntries]=selectedPhysicalEntries(contexts,entries,selectedContext)
            if ~selectedContext.isCombined
                hit=find(strcmp({contexts.contextId},selectedContext.contextId),1,'first');
                if isempty(hit),error('NMResultsViewerMLITools:MissingPhysicalContext','Selected MLI feature context is absent from its catalogue.');end
                physicalContexts=contexts(hit);selectedEntries={entries{hit}};return;
            end
            memberIds=selectedContext.memberContextIds;mask=~[contexts.isCombined]&ismember({contexts.contextId},memberIds);
            physicalContexts=contexts(mask);selectedEntries=entries(mask);
            if numel(physicalContexts)~=numel(memberIds)
                error('NMResultsViewerMLITools:InvalidCombinedContext','Combined MLI feature context members do not match the physical context catalogue.');
            end
            if ~isequal({physicalContexts.contextId},memberIds)
                error('NMResultsViewerMLITools:InvalidCombinedContext','Combined MLI feature context members do not match the physical context catalogue.');
            end
        end
        function n=subjectCount(entries,field)
            if isempty(entries),n=0;return;end
            n=size(entries{1}.(field),1);
            for ii=2:numel(entries)
                candidate=size(entries{ii}.(field),1);
                if candidate~=n,error('NMResultsViewerMLITools:SubjectDimensionMismatch','Stored MLI feature blocks disagree on the subject dimension.');end
            end
        end
        % nm2-allow: reads the selected measure's source field from persisted NM1.4 MLI entries (dynamic field by measure definition).
        function [range,identity,polarity]=globalDisplayRange(entries,field,featureCounts,nSubjects,spec,analysisIndex,source,targetIndex,classifierIndex,contextId,method)
            % globalDisplayRange  Resolve one stable MLI colour domain across the selected scientific context.
            identity=sprintf('mli-range|a=%d|source=%s|target=%d|classifier=%d|context=%s|method=%s', ...
                analysisIndex,source,targetIndex,classifierIndex,contextId,method);
            carriedIdentity='';
            % nm2-allow: mliDisplayRangeIdentity is written by NMResultsViewerUI_main.js selectedSpec only after an MLI payload exists.
            if isfield(spec,'mliDisplayRangeIdentity'),carriedIdentity=char(spec.mliDisplayRangeIdentity);end
            carried=[];
            % nm2-allow: browser display-state boundary validates the optional retained two-number MLI range
            if isfield(spec,'mliDisplayRange') && ~isempty(spec.mliDisplayRange)
                rawRange=spec.mliDisplayRange;
                % nm2-allow: browser display-state boundary requires one finite numeric two-number range
                if ~isnumeric(rawRange) || numel(rawRange)~=2
                    error('NMResultsViewerMLITools:InvalidDisplayRange','mliDisplayRange must contain exactly two numeric values.');
                end
                carried=double(rawRange(:)');
            end
            if strcmp(carriedIdentity,identity) && ~isempty(carried) && all(isfinite(carried)) && carried(1)<=0 && carried(2)>=0 && carried(1)<=carried(2)
                range=carried;
            else
                lower=Inf;upper=-Inf;foundFinite=false;
                for ii=1:numel(entries)
                    entry=entries{ii};nFeatures=featureCounts(ii);
                    raw=entry.(field);
                    if ~isreal(raw),error('NMResultsViewerMLITools:InvalidMeasureShape','Stored MLI field %s must be real-valued.',field);end
                    if size(raw,1)~=nSubjects,error('NMResultsViewerMLITools:InvalidMeasureShape','Stored MLI field %s does not match the selected subject axis.',field);end
                    if size(raw,2)~=nFeatures,error('NMResultsViewerMLITools:InvalidMeasureShape','Stored MLI field %s does not match the selected feature axis.',field);end
                    blockLower=min(raw(:),[],'omitnan');blockUpper=max(raw(:),[],'omitnan');
                    if isempty(blockLower)||isempty(blockUpper)||isnan(blockLower)||isnan(blockUpper),continue;end
                    if ~isfinite(blockLower)||~isfinite(blockUpper)
                        error('NMResultsViewerMLITools:InfiniteRelevance','Stored MLI field %s contains an infinite relevance value.',field);
                    end
                    foundFinite=true;lower=min(lower,double(blockLower));upper=max(upper,double(blockUpper));
                end
                if ~foundFinite,error('NMResultsViewerMLITools:NoFiniteRelevance','The selected MLI context contains no finite relevance value.');end
                if lower<0&&upper>0
                    maximum=max(abs([lower upper]));range=[-maximum maximum];
                elseif upper<=0
                    range=[lower 0];
                else
                    range=[0 upper];
                end
            end
            if range(1)<0&&range(2)>0,polarity='signed';elseif range(2)<=0&&range(1)<0,polarity='negative';else,polarity='positive';end
        end
        function row=concatenateRows(entries,field,index,featureCounts)
            row=zeros(1,sum(featureCounts));offset=0;
            for ii=1:numel(entries)
                entry=entries{ii};nFeatures=featureCounts(ii);raw=entry.(field);
                if size(raw,1)<index,error('NMResultsViewerMLITools:InvalidMeasureShape','Stored MLI field %s does not contain subject row %d.',field,index);end
                if size(raw,2)~=nFeatures,error('NMResultsViewerMLITools:InvalidMeasureShape','Stored MLI field %s does not match the selected feature axis.',field);end
                row(offset+(1:nFeatures))=double(raw(index,:));offset=offset+nFeatures;
            end
        end
        % nk_MLInterpreter writes the uncertainty family together with Y_mapped; no optional-row schema branch is retained.
        function names=featureNamesForSelection(entries,physicalContexts,selectedContext)
            featureCounts=[physicalContexts.nFeatures];names=cell(1,sum(featureCounts));offset=0;
            for ii=1:numel(entries)
                block=NMResultsViewerMLITools.featureNames(entries{ii},featureCounts(ii));
                if selectedContext.isCombined,block=cellfun(@(name)sprintf('%s · %s',physicalContexts(ii).selectionLabel,name),block,'UniformOutput',false);end
                names(offset+(1:featureCounts(ii)))=block;offset=offset+featureCounts(ii);
            end
        end
        function tf=persistedFeatureNamesAvailable(entries,physicalContexts)
            tf=true;
            for ii=1:numel(entries)
                raw=entries{ii}.modality_featnames;
                if isempty(raw),tf=false;return;end
                if numel(raw)~=physicalContexts(ii).nFeatures,tf=false;return;end
            end
        end
        function names=featureNames(entry,n)
            raw=entry.modality_featnames;
            if ~isempty(raw)
                if numel(raw)~=n,error('NMResultsViewerMLITools:FeatureNameDimensionMismatch','Persisted MLI feature names do not match the method-defined feature axis.');end
                names=reshape(raw,1,[]);return;
            end
            names=cell(1,n);for i=1:n,names{i}=sprintf('Feature %d',i);end
        end
        function measure=measureForMethod(method,contextId)
            % measureForMethod  Resolve the method-fixed MLI relevance measure and its presentation defaults.
            % Scientific/state contract: method selects Y_mapped or ShapleyValues; displayThresholdPolicy affects only
            %   initial visibility and does not define a scientific relevance cutoff. The global colour range is assigned
            %   separately from persisted subject x feature extrema. Performance: O(1), no result arrays are scanned.
            measure=NMResultsViewerMLITools.measureTemplate();measure.contextId=contextId;measure.enabled=true;measure.category='interpretability';measure.valuePolarity='signed';measure.displayThresholdPolicy='show_all_nonzero';measure.thresholdMode='none';measure.thresholdLabel='No default relevance suppression';
            if strcmp(method,'shapley'),measure.measureId='shapley_value';measure.label='Shapley value';measure.sourceField='ShapleyValues';else,measure.measureId='prediction_change';measure.label='Mean prediction change';measure.sourceField='Y_mapped';measure.hasSE=true;measure.seSourceField='Y_mapped_std';end
        end
        function sp=spatialMap(NM,ctx,measure,descriptor)
            % spatialMap  Publish spatial capability metadata for the selected MLI feature context.
            sp=NMResultsViewerMLITools.spatialTemplate();
            sp.spatialMapId=sprintf('%s_spatial_%s',ctx.contextId,measure.measureId);sp.contextId=ctx.contextId;sp.measureId=measure.measureId;
            sp.mapKind=ctx.featureKind;sp.thresholdMode='none';sp.representationFrontend='tabular';
            range=measure.displayValueRange;sp.hasNegativeValues=range(1)<0;sp.hasPositiveValues=range(2)>0;
            switch ctx.featureKind
                case 'voxel'
                    sp.artifactKind='voxel_feature_map';sp.viewerMode='browser_orthogonal_overlay';sp.representationFrontend='imaging';
                    sp.enabled=descriptor.ok&&(descriptor.featureSpaceFileExists||descriptor.embeddedFeatureSpaceAvailable);
                    if descriptor.ok,sp.maskFile=descriptor.featureSpaceFile;end
                case 'surface_vertex'
                    availability=NMResultsViewerSurfaceTools.catalogueAvailability(NM,ctx.varind,ctx.nFeatures);
                    sp.artifactKind='surface_descriptor';sp.viewerMode='native_surface_overlay';sp.representationFrontend='imaging';sp.enabled=availability.enabled;sp.disabledReason=availability.disabledReason;
                    if descriptor.ok,sp.surfaceFile=descriptor.featureSpaceFile;end
                case 'roi'
                    sp.roiSpatialDomain=ctx.roiSpatialDomain;sp.roiIdentityModel=ctx.roiIdentityModel;sp.roiSpatialReferenceIdentity=ctx.roiSpatialReferenceIdentity;
                    sp.hasAtlasCoordinates=ctx.roiHasAtlasCoordinates;sp.atlasFile=ctx.roiAtlasFile;
                    if strcmp(ctx.roiSpatialDomain,'volume')
                        sp.artifactKind='voxel_feature_map';sp.viewerMode='browser_orthogonal_overlay';sp.representationFrontend='imaging';sp.enabled=~isempty(ctx.roiAtlasFile);sp.maskFile=ctx.roiAtlasFile;
                    elseif strcmp(ctx.roiSpatialDomain,'surface')
                        sp.artifactKind='surface_descriptor';sp.viewerMode='native_surface_overlay';sp.representationFrontend='imaging';sp.enabled=true;
                    end
                case 'connectivity_edge'
                    sp.artifactKind='connectivity_feature_map';sp.viewerMode='connectivity_representation';sp.representationFrontend='connectivity';sp.enabled=false;
                    sp.disabledReason='Connectivity MLI visualization is not yet wired to the shared connectivity presentation controller.';
                otherwise
                    sp.enabled=false;sp.disabledReason='This feature source has no spatial renderer.';
            end
        end
        function [idx,id,msg]=resolveSubject(cases,spec,n)
            % resolveSubject  Resolve one subject from canonical DataIO case identity.
            idx=0;id='';msg='';
            requestedId=spec.subjectCaseId;
            requestedIndex=spec.subjectCaseIndex;
            if isfinite(requestedIndex) && requestedIndex~=0
                if requestedIndex~=round(requestedIndex),msg='MLI subject row must be an integer case coordinate.';return;end
                candidate=requestedIndex;
                if candidate<1,msg=sprintf('MLI subject row %d is outside 1..%d.',candidate,n);return;end
                if candidate>n,msg=sprintf('MLI subject row %d is outside 1..%d.',candidate,n);return;end
                candidateId=NMResultsViewerMLITools.caseIdAt(cases,candidate);
                if ~isempty(requestedId)&&~strcmp(candidateId,requestedId),msg=sprintf('Subject identity mismatch: row %d is %s, not %s.',candidate,candidateId,requestedId);return;end
                idx=candidate;id=candidateId;return;
            end
            if ~isempty(requestedId)
                allIds=NMResultsViewerMLITools.caseText(cases);hits=find(strcmp(allIds,requestedId));
                if numel(hits)>1,msg=sprintf('Subject ID %s is duplicated in the authoritative case list.',requestedId);return;end
                if isempty(hits)
                    % nm2-allow: NMResultsViewerUI_main.stateRequestSpecForChange marks exact Case-ID restoration after a scientific-context switch.
                    if isfield(spec,'selectionTransition') && ~isempty(spec.selectionTransition),return;end
                    msg=sprintf('Subject ID %s is not present in the selected result source.',requestedId);return;
                end
                idx=hits(1);id=allIds{idx};return;
            end
            % An omitted subject remains unselected; only explicit identity requests resolve a row.
        end
        function subjects=subjectOptions(cases,scoreCatalogue)
            % subjectOptions  Build the canonical MLI subject catalogue with optional model-score metadata.
            % Score metadata joins only by exact case identity; there is no row-order matching.
            ids=NMResultsViewerMLITools.caseText(cases);
            subjects=repmat(NMResultsViewerMLITools.subjectTemplate(),1,numel(ids));
            scoreRows=scoreCatalogue.rows;scoreLabel=scoreCatalogue.scoreLabel;expectedLabel=scoreCatalogue.expectedLabel;predictedLabel=scoreCatalogue.predictedLabel;
            scoreMap=containers.Map('KeyType','char','ValueType','double');duplicateIds=containers.Map('KeyType','char','ValueType','logical');
            for ii=1:numel(scoreRows)
                sid=scoreRows(ii).caseId;
                if isempty(sid),continue;end
                if isKey(scoreMap,sid),duplicateIds(sid)=true;else,scoreMap(sid)=ii;end
            end
            for ii=1:numel(ids)
                row=NMResultsViewerMLITools.subjectTemplate();row.caseIndex=ii;row.caseId=ids{ii};row.label=ids{ii};row.enabled=true;
                if isKey(scoreMap,ids{ii})&&~isKey(duplicateIds,ids{ii})
                    sr=scoreRows(scoreMap(ids{ii}));score=double(sr.score);
                    row.score=score;row.scoreAvailable=isfinite(score);row.scoreLabel=scoreLabel;row.expectedLabel=expectedLabel;row.predictedLabel=predictedLabel;
                    row.expected=sr.expected;row.predicted=sr.predicted;
                end
                subjects(ii)=row;
            end
        end
        % Uncertainty rows use concatenateRows because nk_MLInterpreter writes the complete fixed uncertainty family.
        function [values,ok,msg]=subjectFeatureValuesForSelection(NM,entries,contexts,caseIndex,sourceKind) %#ok<INUSD>
            % subjectFeatureValuesForSelection  Resolve the optional CV companion profile from resident predictor matrices.
            values=[];ok=false;msg='';
            if strcmp(sourceKind,'oocv'),msg='Original OOCV feature values are not materialized by the MLI result contract.';return;end
            blocks=cell(1,numel(contexts));
            for ii=1:numel(contexts)
                ctx=contexts(ii);
                info=NMModalityInfoTools.fromNM(NM,ctx.varind,struct('ScanInMemory',false));
                if ~strcmp(info.storageMode,'memory')
                    msg=sprintf('Original feature values are not resident for %s.',ctx.selectionLabel);return;
                end
                Y=NM.Y{ctx.varind};
                if size(Y,1)<caseIndex,msg=sprintf('Original feature values do not contain subject row %d for %s.',caseIndex,ctx.selectionLabel);return;end
                if size(Y,2)~=ctx.nFeatures,msg=sprintf('Original feature values do not match the MLI feature axis for %s.',ctx.selectionLabel);return;end
                blocks{ii}=double(Y(caseIndex,:));
            end
            values=[blocks{:}];ok=true;
        end
        function a=annotation(ctx,physicalContexts,payload,measure,A,NM)
            % annotation  Materialize MLI Scientific Annotation from resolved MLI/DataIO authorities.
            material=NMResultsViewerScientificAnnotation.featureInspectionMaterialTemplate();
            material.visualizationContainer='MLI';material.componentContainer='';
            material.analysisIndex=payload.analysisIndex;material.targetIndex=payload.targetIndex;material.targetNativeIndex=payload.targetNativeIndex;
            material.targetSource='analysis';material.targetLabelName=sprintf('Target %d',payload.targetNativeIndex);material.resultTargetIndex=payload.resultTargetIndex;
            material.analysisMode=NMResultsViewerMLITools.analysisMode(A);material.classifierIndex=payload.classifierIndex;material.featureContextId=ctx.contextId;
            material.physicalContextIds={physicalContexts.contextId};material.physicalVisRowIndices=zeros(1,numel(physicalContexts));material.physicalVarinds=[physicalContexts.varind];material.physicalFeatureCounts=[physicalContexts.nFeatures];material.modalityVarinds=[physicalContexts.varind];
            material.featureNamesAvailable=payload.featureNamesPersisted;
            if material.featureNamesAvailable,material.featureNameSource='MLI.modality_featnames';if ctx.isCombined,material.featureNameSource='MLI.modality_featnames + feature-context qualification';end;end
            material.modalityDescriptions=cell(1,numel(physicalContexts));material.modalitySourceTypes=cell(1,numel(physicalContexts));material.modalitySourceTypeLabels=cell(1,numel(physicalContexts));material.modalityDatasources=cell(1,numel(physicalContexts));material.modalitySources=cell(1,numel(physicalContexts));material.modalityTypeCodes=zeros(1,numel(physicalContexts));
            for ii=1:numel(physicalContexts)
                modalityInfo=NMModalityInfoTools.fromNM(NM,physicalContexts(ii).varind,struct('ScanInMemory',false));
                material.modalityDescriptions{ii}=modalityInfo.description;material.modalitySourceTypes{ii}=modalityInfo.sourceType;material.modalitySourceTypeLabels{ii}=modalityInfo.sourceTypeLabel;
                material.modalityDatasources{ii}=modalityInfo.datasource;material.modalitySources{ii}=modalityInfo.source;material.modalityTypeCodes(ii)=double(modalityInfo.typeCode);
            end
            material.featureKind=ctx.featureKind;material.fusionMode=payload.fusionMode;material.selectedContextIsCombined=ctx.isCombined;
            if strcmp(ctx.featureKind,'roi')
                material.roiSpatialDomain=ctx.roiSpatialDomain;material.roiSpatialSemantics=ctx.roiSpatialSemantics;material.roiIdentityModel=ctx.roiIdentityModel;material.roiSpatialReferenceIdentity=ctx.roiSpatialReferenceIdentity;
            end
            material.measureId=measure.measureId;material.requestedMeasureId=measure.measureId;material.measureRequestSatisfied=true;material.measureSelector='method';
            material.payloadField=measure.sourceField;material.payloadSeField=measure.seSourceField;material.backprojectionComponentId='';material.componentIndex=NaN;material.componentPosition=NaN;
            material.contextSelector='featureContextId';material.componentSelector='none';
            a=NMResultsViewerScientificAnnotation.fromMLI(material);
        end
        function r=resolvedSelection(ctx,physicalContexts,payload,measure)
            r=NMResultsViewerScientificAnnotation.legacyResolvedSelectionTemplate();r.analysisIndex=payload.analysisIndex;r.targetIndex=payload.targetIndex;r.resultTargetIndex=payload.resultTargetIndex;r.classifierIndex=payload.classifierIndex;r.featureContextId=ctx.contextId;r.physicalContextIds={physicalContexts.contextId};r.physicalVarinds=[physicalContexts.varind];r.physicalFeatureCounts=[physicalContexts.nFeatures];r.measureId=measure.measureId;r.requestedMeasureId=measure.measureId;r.measureRequestSatisfied=true;r.measureSelector='method';r.backprojectionComponentId='';r.componentIndex=NaN;r.componentPosition=NaN;r.contextSelector='featureContextId';r.componentSelector='none';
        end
        function mode=analysisMode(A)
            mode=A.params.label.modeflag;
            if strcmp(mode,'classification') || strcmp(mode,'regression'),return;end
            error('NMResultsViewerMLITools:InvalidAnalysisMode','analysis.params.label.modeflag must be classification or regression.');
        end
        function label=modalityLabel(NM,varind,displayIndex)
            info=NMModalityInfoTools.fromNM(NM,varind,struct('ScanInMemory',false));
            label=info.description;
            if isempty(label),label=sprintf('Modality %d',displayIndex);end
        end
        function family=rendererFamily(kind)
            switch kind
                case 'voxel',family='voxel_overlay';
                case 'surface_vertex',family='surface_overlay';
                case 'roi',family='imaging';
                case 'connectivity_edge',family='connectivity';
                otherwise,family='tabular';
            end
        end
        function c=contextTemplate()
            c=struct('contextId','','analysisIndex',0,'targetIndex',1,'resultTargetIndex',1,'targetLabel','Target 1','classIndex',1,'classLabel','Classifier 1','isMultiGroup',false,'visRowIndex',0,'modalityIndex',1,'modalityLabel','Modality 1','selectionLabel','Modality 1','varind',1,'componentIndex',NaN,'componentLabel','','backprojectionAvailable',false,'backprojectionComponentCount',0,'fusionMode','none','legacyVisFlag',NaN,'sourceKind','mli','sourceFamily','unknown','featureKind','tabular','rendererFamily','tabular','nFeatures',0,'roiSidecarAvailable',false,'roiSpatialDomain','','roiSpatialSemantics','','roiIdentityModel','','roiSpatialReferenceIdentity','','roiAtlasFile','','roiHasAtlasCoordinates',false,'isCombined',false,'memberContextIds',{{}},'combinedGroupId','','enabled',false,'disabledReason','');
        end
        function m=measureTemplate()
            m=struct('contextId','','measureId','','label','','category','','sourceField','','legacySourceField','','valuePolarity','signed','displayValueRange',[NaN NaN],'displayRangeMode','','displayThresholdPolicy','','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN,'thresholdLabel','','hasSE',false,'seSourceField','','enabled',false,'disabledReason','');
        end
        function s=spatialTemplate()
            s=struct('spatialMapId','','contextId','','componentId','','componentIndex',NaN,'componentLabel','','measureId','','mapKind','tabular','artifactKind','none','viewerMode','none','representationFrontend','tabular','maskFile','','surfaceFile','','atlasFile','','atlasDescriptorFile','','hasIndexedVoxelPositions',false,'hasAtlasCoordinates',false,'nodeCount',0,'edgeCount',0,'coordinateSpace','','coordinateUnits','','roiSpatialDomain','','roiIdentityModel','','roiSpatialReferenceIdentity','','thresholdMode','none','thresholdLow',NaN,'thresholdHigh',NaN,'thresholdValue',NaN,'hasPositiveValues',false,'hasNegativeValues',false,'enabled',false,'disabledReason','');
        end
        function s=subjectTemplate()
            s=struct('caseIndex',0,'caseId','','label','','enabled',false,'scoreAvailable',false,'score',NaN, ...
                'scoreLabel','Model score','expected','','expectedLabel','Expected class','predicted','','predictedLabel','Predicted class');
        end
        function n=caseCount(raw)
            n=numel(raw);
        end
        function id=caseIdAt(raw,index)
            id=raw{index};
        end
        function cases=caseText(raw)
            cases=reshape(raw,1,[]);
        end
    end
end

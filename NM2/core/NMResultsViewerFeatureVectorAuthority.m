classdef NMResultsViewerFeatureVectorAuthority
% NMResultsViewerFeatureVectorAuthority
% -------------------------------------------------------------------------
% Shared scientific-selection seam for feature-vector visualizations.
% Feature Inspection and MLI retain independent result authorities; this class
% only dispatches the already explicit resultType to metadata, adapter-selection
% and exact-vector functions consumed by the common imaging/surface renderers,
% and owns the result-independent certification used for early-fusion tabular
% combined views. It does not infer scientific state or materialize resources.
% -------------------------------------------------------------------------
    methods (Static)
        function payload=metadata(NM,spec)
            % metadata  Dispatch feature-vector metadata to the explicit result-family authority.
            % Inputs: NM plus a spec carrying resultType. Output: FI metadata payload or subject-level MLI payload.
            % Authority/state: this function owns no scientific interpretation; resultType is explicit and never inferred from data.
            % Performance: bounded dispatch only; downstream costs remain owned by the selected authority. Side effects: none.
            kind=spec.resultType;
            switch kind
                case 'mli'
                    payload=NMResultsViewerMLITools.getPayload(NM,spec);
                case 'model_feature_inspection'
                    spec.resultType='model_feature_inspection';spec.featureInspectionPayloadScope='metadata';
                    payload=NMResultsViewerTools.getModelFeatureInspectionPayload(NM,spec);
                otherwise
                    error('NMResultsViewerFeatureVectorAuthority:UnsupportedResultType','Spatial feature-vector visualization does not support result type %s.',kind);
            end
        end
        function selection=selection(spec,payload)
            % selection  Dispatch an already resolved feature-vector payload into the common spatial-selection contract.
            % Performance: O(1) metadata dispatch; no file/resource reads or feature-scale allocations. Side effects: none.
            % Failure semantics: unsupported resultType raises an explicit error rather than falling back to Feature Inspection.
            kind=payload.kind;
            switch kind
                case 'mli',selection=NMResultsViewerMLITools.getAdapterSelection(spec,payload);
                case 'model_feature_inspection',selection=NMResultsViewerTools.getModelFeatureInspectionAdapterSelection(spec,payload);
                otherwise,error('NMResultsViewerFeatureVectorAuthority:UnsupportedResultType','Spatial feature-vector selection does not support result type %s.',kind);
            end
        end
        function out=vector(NM,spec,measureId,payload)
            % vector  Dispatch exact feature-vector materialization to Feature Inspection or MLI.
            % Output: one selected feature vector plus its authoritative context metadata for shared spatial adapters.
            % Materialization/performance: delegates O(F) vector extraction; this seam performs no source read, scan or copy itself.
            % Failure semantics: unsupported resultType raises explicitly. Side effects: none.
            kind=payload.kind;
            switch kind
                case 'mli',out=NMResultsViewerMLITools.getFeatureVector(NM,spec,measureId,payload);
                case 'model_feature_inspection',out=NMResultsViewerTools.getModelFeatureInspectionMeasureVector(NM,spec,measureId,payload);
                otherwise,error('NMResultsViewerFeatureVectorAuthority:UnsupportedResultType','Spatial feature-vector materialization does not support result type %s.',kind);
            end
        end

        function tf=isTabularDescriptor(NM,varind)
            % isTabularDescriptor  Certify one normalized DataIO modality for a combined tabular view.
            %
            % NMModalityInfoTools owns canonical modality normalization. DataIO typeCode
            % 0 is matrix-like; connectivity and ROI are the two canonical type-0
            % source families that are not generic tabular feature spaces.
            info=NMModalityInfoTools.fromNM(NM,varind,struct('ScanInMemory',false));
            tf=info.typeCode==0 && ~ismember(info.sourceType,{'connectivity','roi'});
        end
    end
end

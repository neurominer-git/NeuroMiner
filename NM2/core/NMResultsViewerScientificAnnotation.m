classdef NMResultsViewerScientificAnnotation
% NMResultsViewerScientificAnnotation
% -------------------------------------------------------------------------
% System-level scientific annotation contract for NM 2.0 Results Viewer
% payloads.
%
% Authoritative responsibility:
%   * define the concise cross-domain scientific vocabulary (`schema`);
%   * define the fixed domain materialization record (`material`);
%   * define the versioned schema<->material mapping;
%   * validate that scientific meaning and NM materialization agree;
%   * generate the bounded resolvedSelection projection required by current consumers.
%
% This class does NOT inspect NM, read result containers, materialize payload
% values, choose viewer representations, or execute consumer-specific logic.
% Domain authorities resolve/materialize payloads and pass already-resolved
% material facts here. Consumers may read `schema`; domain authorities may
% use `material`; no consumer may recreate schema<->material mappings.
%
% Contract: NM-SCIENTIFIC-ANNOTATION-V7
% Domains: feature_inspection, ml_interpretation, model_performance, model_optimization
% -------------------------------------------------------------------------

    methods (Static)
        function version = contractVersion()
            % Purpose: Return the current Scientific Annotation contract identifier.
            % Syntax: version = NMResultsViewerScientificAnnotation.contractVersion()
            % Inputs: None.
            % Outputs: version is the immutable contract string NM-SCIENTIFIC-ANNOTATION-V7.
            % Authority and flow: Central version authority for annotations created by this class.
            % Scientific/state contract: V7 includes explicit multi-class target contrast plus result-source/model-source/OOCV-subgroup coordinates.
            % Invariants: Consumers compare this identifier rather than inferring schema version from fields.
            % Materialization and performance: Constant-time metadata only; no file/resource reads or scientific materialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact scientific metadata only and safe on interactive state/annotation paths.
            % Failure semantics: None.
            % Side effects: None.
            % Consumers and dependencies: Annotation templates, validators, Scientific State/Directory and report/viewer consumers.
            version = 'NM-SCIENTIFIC-ANNOTATION-V7';
        end

        function annotation = template()
            persistent cached
            if isempty(cached)
                cached = struct( ...
                    'contractVersion',NMResultsViewerScientificAnnotation.contractVersion(), ...
                    'domain','', ...
                    'schema',NMResultsViewerScientificAnnotation.schemaTemplate(), ...
                    'material',struct());
            end
            annotation=cached;
        end

        function material = featureInspectionMaterialTemplate()
            % Fixed implementation-facing record produced by Feature Inspection.
            material = struct( ...
                'analysisContainer','analysis', ...
                'analysisIndex',0, ...
                'analysisMode','', ...
                'targetIndex',0, ...
                'targetNativeIndex',0, ...
                'targetSource','', ...
                'targetLabelName','', ...
                'resultTargetIndex',NaN, ...
                'visualizationContainer','visdata', ...
                'classifierIndex',0, ...
                'featureContextId','', ...
                'physicalContextIds',{{}}, ...
                'physicalVisRowIndices',[], ...
                'physicalVarinds',[], ...
                'physicalFeatureCounts',[], ...
                'modalityVarinds',[], ...
                'featureNamesAvailable',false, ...
                'featureNameSource','none', ...
                'modalityDescriptions',{{}}, ...
                'modalitySourceTypes',{{}}, ...
                'modalitySourceTypeLabels',{{}}, ...
                'modalityDatasources',{{}}, ...
                'modalitySources',{{}}, ...
                'modalityTypeCodes',[], ...
                'featureKind','', ...
                'roiSpatialDomain','', ...
                'roiSpatialSemantics','', ...
                'roiIdentityModel','', ...
                'roiSpatialReferenceIdentity','', ...
                'fusionField','params.TrainParam.FUSION.flag', ...
                'fusionMode','none', ...
                'selectedContextIsCombined',false, ...
                'measureId','', ...
                'requestedMeasureId','', ...
                'measureRequestSatisfied',false, ...
                'measureSelector','none', ...
                'payloadField','', ...
                'payloadSeField','', ...
                'componentContainer','CompKept', ...
                'backprojectionComponentId','', ...
                'componentIndex',NaN, ...
                'componentPosition',NaN, ...
                'contextSelector','', ...
                'componentSelector','none');
        end

        function material = performanceMaterialTemplate()
            % Purpose: Define the fixed implementation-facing material record for model-performance annotations.
            % Syntax: material = NMResultsViewerScientificAnnotation.performanceMaterialTemplate()
            % Inputs: None.
            % Outputs: material is a scalar fixed-schema struct populated later by the Model Performance authority.
            % Authority and flow: Defines representation fields only; NMResultsViewerTools.scientificResultAnnotation supplies already-resolved analysis, target, class-contrast, source and model facts.
            % Scientific/state contract: Multi-class performance carries classContrast=all_classes or one_vs_rest, with classIndex/className only for one_vs_rest; other result families use not_applicable.
            % Invariants: Field set is fixed and validated exactly by validateResultMaterial.
            % Materialization and performance: Constant-size metadata allocation; no files, XML, atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact scientific metadata only and safe on interactive state/annotation paths.
            % Failure semantics: None at template creation; populated records are validated separately.
            % Side effects: None.
            % Consumers and dependencies: fromModelPerformance/fromModelOptimization and result annotation producers.
            material = struct( ...
                'analysisContainer','analysis', ...
                'analysisIndex',0, ...
                'analysisMode','', ...
                'targetIndex',0, ...
                'targetNativeIndex',0, ...
                'targetSource','', ...
                'targetLabelName','', ...
                'classContrast','not_applicable', ...
                'classIndex',NaN, ...
                'className','', ...
                'sourceId','', ...
                'subgroupIndex',NaN, ...
                'resultContainer','', ...
                'classifierIndex',0, ...
                'payloadFamily','performance', ...
                'payloadType','', ...
                'modelSource','','fusionMode','none');
        end

        function material = optimizationMaterialTemplate()
            material = NMResultsViewerScientificAnnotation.performanceMaterialTemplate();
            material.payloadFamily = 'optimization';
            material.payloadType = 'optimization_payload';
        end

        function mapping = mapping(domain)
            % mapping  Machine-readable authoritative schema<->material map.
            switch domain
                case 'feature_inspection'
                    mapping = NMResultsViewerScientificAnnotation.featureInspectionMapping();
                case 'ml_interpretation'
                    mapping = NMResultsViewerScientificAnnotation.mliMapping();
                case 'model_performance'
                    mapping = NMResultsViewerScientificAnnotation.resultMapping();
                case 'model_optimization'
                    mapping = NMResultsViewerScientificAnnotation.resultMapping();
                case 'synth_experiment'
                    mapping = NMResultsViewerScientificAnnotation.synthMapping();
                otherwise
                    error('NMResultsViewerScientificAnnotation:UnsupportedDomain', ...
                        'Scientific annotation domain "%s" is not registered.',domain);
            end
        end

        function annotation = fromFeatureInspection(material)
            % fromFeatureInspection  Construct one annotation from resolved material facts.
            NMResultsViewerScientificAnnotation.validateFeatureInspectionMaterial(material);
            annotation = NMResultsViewerScientificAnnotation.template();
            annotation.domain = 'feature_inspection';
            annotation.material = material;
            schema = annotation.schema;
            mapping = NMResultsViewerScientificAnnotation.featureInspectionMapping();
            for ii = 1:numel(mapping)
                value = NMResultsViewerScientificAnnotation.applyFeatureInspectionRule( ...
                    mapping(ii),material);
                schema = NMResultsViewerScientificAnnotation.setSchemaValue( ...
                    schema,mapping(ii).schemaPath,value);
            end
            annotation.schema = schema;
        end

        function annotation = fromMLI(material)
            % fromMLI  Construct MLI scientific annotation from fixed material facts.
            %
            % Authority and flow: uses the same resolved analysis/source/target/model/
            % fusion/modality/feature-space material contract as Feature Inspection.
            % Scientific/state contract: MLI deliberately has no component coordinate;
            % componentIndex/backprojectionComponentId must be unset.
            % Materialization/performance: schema projection over fixed scalar/string
            % metadata only; O(number of annotation mapping rows), with no heavy arrays.
            % Failure semantics: a finite/nonempty component coordinate is an explicit
            % contract error. Side effects: none.
            NMResultsViewerScientificAnnotation.validateFeatureInspectionMaterial(material);
            if isfinite(double(material.componentIndex)) || ~isempty(material.backprojectionComponentId)
                error('NMResultsViewerScientificAnnotation:InvalidMLIComponent', ...
                    'Model interpretation does not support a component scientific coordinate.');
            end
            annotation = NMResultsViewerScientificAnnotation.template();
            annotation.domain = 'ml_interpretation';
            annotation.material = material;
            schema = annotation.schema;
            mapping = NMResultsViewerScientificAnnotation.mliMapping();
            for ii = 1:numel(mapping)
                value = NMResultsViewerScientificAnnotation.applyFeatureInspectionRule(mapping(ii),material);
                schema = NMResultsViewerScientificAnnotation.setSchemaValue(schema,mapping(ii).schemaPath,value);
            end
            annotation.schema = schema;
        end

        function annotation = fromPerformance(material)
            NMResultsViewerScientificAnnotation.validateResultMaterial(material,'performance');
            annotation = NMResultsViewerScientificAnnotation.fromResultMaterial('model_performance',material);
        end

        function annotation = fromOptimization(material)
            NMResultsViewerScientificAnnotation.validateResultMaterial(material,'optimization');
            annotation = NMResultsViewerScientificAnnotation.fromResultMaterial('model_optimization',material);
        end

        function material = synthMaterialTemplate()
            % Compact experiment identity; numerical outcomes remain in child analyses.
            material = struct('experimentIndex',0,'experimentId','', ...
                'mode','','sourceAnalysisIndex',0,'observedN',0, ...
                'analysisIndices',[],'status','','configuration',struct());
        end

        function annotation = fromSynthExperiment(material)
            % Parent identity is produced by NMSimulationTools, not inferred here.
            assert(isequal(sort(fieldnames(material)), ...
                sort(fieldnames(NMResultsViewerScientificAnnotation.synthMaterialTemplate()))), ...
                'NMResultsViewerScientificAnnotation:InvalidSynthMaterial', ...
                'SYNTH material must use the declared fixed schema.');
            annotation = NMResultsViewerScientificAnnotation.template();
            annotation.domain = 'synth_experiment';
            annotation.material = material;
            mapping = NMResultsViewerScientificAnnotation.synthMapping();
            for ii=1:numel(mapping)
                annotation.schema = NMResultsViewerScientificAnnotation.setSchemaValue( ...
                    annotation.schema,mapping(ii).schemaPath,material.(mapping(ii).materialField));
            end
            annotation.schema.payload.family = 'synth';
            annotation.schema.payload.type = 'synth_experiment';
        end

        function validate(annotation)
            % validate  Reject malformed or semantically divergent annotations.
            % nm2-allow: public annotation validation boundary checks scalar fixed-schema input
            if ~isstruct(annotation) || ~isscalar(annotation)
                error('NMResultsViewerScientificAnnotation:InvalidAnnotation', ...
                    'scientificAnnotation must be one scalar struct.');
            end
            expected = fieldnames(NMResultsViewerScientificAnnotation.template());
            if ~isempty(setxor(expected,fieldnames(annotation)))
                error('NMResultsViewerScientificAnnotation:InvalidAnnotation', ...
                    'scientificAnnotation must use the fixed annotation field schema.');
            end
            if ~strcmp(annotation.contractVersion,NMResultsViewerScientificAnnotation.contractVersion())
                error('NMResultsViewerScientificAnnotation:InvalidContractVersion', ...
                    'scientificAnnotation must implement %s.', ...
                    NMResultsViewerScientificAnnotation.contractVersion());
            end
            domain = annotation.domain;
            switch domain
                case 'feature_inspection'
                    rebuilt = NMResultsViewerScientificAnnotation.fromFeatureInspection(annotation.material);
                case 'ml_interpretation'
                    rebuilt = NMResultsViewerScientificAnnotation.fromMLI(annotation.material);
                case 'model_performance'
                    rebuilt = NMResultsViewerScientificAnnotation.fromPerformance(annotation.material);
                case 'model_optimization'
                    rebuilt = NMResultsViewerScientificAnnotation.fromOptimization(annotation.material);
                case 'synth_experiment'
                    rebuilt = NMResultsViewerScientificAnnotation.fromSynthExperiment(annotation.material);
                otherwise
                    error('NMResultsViewerScientificAnnotation:UnsupportedDomain', ...
                        'Scientific annotation domain "%s" is not registered.',domain);
            end
            if ~isequaln(annotation.schema,rebuilt.schema)
                error('NMResultsViewerScientificAnnotation:SchemaMaterialMismatch', ...
                    'scientificAnnotation.schema disagrees with its authoritative material mapping.');
            end
        end

        function resolved = legacyResolvedSelectionTemplate()
            % Fixed resolvedSelection projection for the accepted G1 contract.
            resolved = struct( ...
                'analysisIndex',0,'targetIndex',0,'resultTargetIndex',NaN, ...
                'classifierIndex',0,'featureContextId','', ...
                'physicalContextIds',{{}},'physicalVisRowIndices',[], ...
                'physicalVarinds',[],'physicalFeatureCounts',[], ...
                'measureId','','requestedMeasureId','', ...
                'measureRequestSatisfied',false,'measureSelector','none', ...
                'backprojectionComponentId','','componentIndex',NaN, ...
                'componentPosition',NaN,'contextSelector','', ...
                'componentSelector','none');
        end

        function resolved = legacyResolvedSelection(annotation)
            % legacyResolvedSelection  One-way resolvedSelection projection.
            NMResultsViewerScientificAnnotation.validate(annotation);
            if ~ismember(annotation.domain,{'feature_inspection','ml_interpretation'})
                error('NMResultsViewerScientificAnnotation:UnsupportedLegacyProjection', ...
                    'Legacy resolvedSelection projection is defined only for feature-vector scientific annotations.');
            end
            m = annotation.material;
            resolved = NMResultsViewerScientificAnnotation.legacyResolvedSelectionTemplate();
            fields = fieldnames(resolved);
            for ii = 1:numel(fields)
                field = fields{ii};
                resolved.(field) = m.(field);
            end
        end

        function annotation = updateFeatureMeasure(annotation,measureId,requestedMeasureId, ...
                requestSatisfied,measureSelector,payloadField,payloadSeField)
            % updateFeatureMeasure  Rebind one materialized vector to an exact measure.
            NMResultsViewerScientificAnnotation.validate(annotation);
            if ~strcmp(annotation.domain,'feature_inspection')
                error('NMResultsViewerScientificAnnotation:UnsupportedDomain', ...
                    'Feature-measure updates require a feature_inspection annotation.');
            end
            m = annotation.material;
            m.measureId = measureId;
            m.requestedMeasureId = requestedMeasureId;
            m.measureRequestSatisfied = requestSatisfied;
            m.measureSelector = measureSelector;
            m.payloadField = payloadField;
            m.payloadSeField = payloadSeField;
            annotation = NMResultsViewerScientificAnnotation.fromFeatureInspection(m);
        end
    end

    methods (Static, Access = private)
        function schema = schemaTemplate()
            % Purpose: Define the canonical cross-domain scientific schema shape.
            % Syntax: schema = NMResultsViewerScientificAnnotation.schemaTemplate()
            % Inputs: None.
            % Outputs: schema is the fixed semantic coordinate struct used by all annotation domains.
            % Authority and flow: This private schema authority is populated from domain material through explicit mapping tables.
            % Scientific/state contract: target includes native/effective identity plus classContrast/classIndex/className; source carries result source, model source and OOCV subgroup identity as queryable scientific coordinates.
            % Invariants: Consumers read semantic coordinates from schema and do not recreate material-to-schema mappings.
            % Materialization and performance: Constant-size metadata allocation only; no scientific payload/resource materialization.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact scientific metadata only and safe on interactive state/annotation paths.
            % Failure semantics: None.
            % Side effects: None.
            % Consumers and dependencies: template(), mapping application, Scientific Directory and Scientific State.
            persistent cached
            if isempty(cached)
                cached = struct( ...
                    'analysis',struct('index',0), ...
                    'target',struct('index',0,'nativeIndex',0,'name','', ...
                        'classContrast','not_applicable','classIndex',NaN,'className',''), ...
                    'modelResult',struct('type','','index',0,'dichotomizationIndex',NaN), ...
                    'fusion',struct('mode','none'), ...
                    'featureSpace',struct('kind','','scope','unspecified','namesAvailable',false,'nameSource','none', ...
                        'spatialDomain','','spatialSemantics','','identityModel','','spatialReferenceIdentity',''), ...
                    'modality',struct('varinds',[],'descriptions',{{}},'provenanceTypes',{{}}, ...
                        'provenanceTypeLabels',{{}},'role','unspecified'), ...
                    'component',struct('applicable',false,'index',NaN,'scope','not_applicable'), ...
                    'source',struct('id','','modelSource','','subgroupIndex',NaN), ...
                    'payload',struct('family','','type',''));
            end
            schema=cached;
        end

        function annotation = fromResultMaterial(domain,material)
            annotation = NMResultsViewerScientificAnnotation.template();
            annotation.domain = domain;
            annotation.material = material;
            schema = annotation.schema;
            mapping = NMResultsViewerScientificAnnotation.resultMapping();
            for ii = 1:numel(mapping)
                value = NMResultsViewerScientificAnnotation.applyResultRule(mapping(ii),material);
                schema = NMResultsViewerScientificAnnotation.setSchemaValue(schema,mapping(ii).schemaPath,value);
            end
            annotation.schema = schema;
        end

        function mapping = synthMapping()
            % Canonical SYNTH coordinates in the existing scientific vocabulary.
            mapping = struct('schemaPath',{'schema.analysis.index', ...
                'schema.source.id'},'materialField',{'experimentIndex','experimentId'});
        end

        function mapping = resultMapping()
            % Purpose: Define the authoritative material-to-schema mapping for model performance and optimization.
            % Syntax: mapping = NMResultsViewerScientificAnnotation.resultMapping()
            % Inputs: None.
            % Outputs: mapping is the ordered machine-readable mapping table consumed by fromResultMaterial.
            % Authority and flow: Maps already-resolved material fields into analysis, target, class contrast, result, payload and fusion schema coordinates; it never reads NM.
            % Scientific/state contract: classContrast/classIndex/className and source id/modelSource/subgroupIndex are explicit schema coordinates and therefore participate in downstream Scientific State/Directory identity.
            % Invariants: Every mapping row references one declared material field and one canonical schema path; no consumer-side aliases or inference are permitted.
            % Materialization and performance: Constant-size metadata construction; no files/resources or feature-scale work.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact scientific metadata only and safe on interactive state/annotation paths.
            % Failure semantics: Invalid mapping paths are rejected by applyResultRule/fromResultMaterial.
            % Side effects: None.
            % Consumers and dependencies: fromResultMaterial for model_performance and model_optimization domains.
            persistent cached
            if ~isempty(cached), mapping=cached; return; end
            tmpl = struct('schemaPath','','materialPaths',{{}},'rule','','applicability','','meaning','');
            mapping = repmat(tmpl,1,16);
            mapping(1) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.analysis.index',{'material.analysisIndex'},'direct','always','Analysis identity.');
            mapping(2) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.index',{'material.targetIndex'},'direct','always','Analysis-local target position used by result materializers.');
            mapping(3) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.nativeIndex',{'material.targetNativeIndex'},'direct','always','Originating NM.label column when the target is native.');
            mapping(4) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.name',{'material.targetLabelName'},'direct','always','Human-facing resolved target name.');
            mapping(5) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.classContrast',{'material.classContrast'},'normalized_enum','always','Target-class contrast represented by the performance artefact.');
            mapping(6) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.classIndex',{'material.classIndex'},'direct','always','Selected target-class identity for one-vs-rest performance; NaN otherwise.');
            mapping(7) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.className',{'material.className'},'direct','always','Selected target-class label for one-vs-rest performance; empty otherwise.');
            mapping(8) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modelResult.type',{'material.payloadType'},'payload_to_model_result_type','always','Scientific result kind.');
            mapping(9) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modelResult.index',{'material.classifierIndex'},'direct','always','Model-result identity.');
            mapping(10) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modelResult.dichotomizationIndex',{'material.classifierIndex','material.payloadType'}, ...
                'performance_dichotomization_index','binary_classification','Binary dichotomization identity when applicable.');
            mapping(11) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.payload.family',{'material.payloadFamily'},'normalized_enum','always','Cross-domain payload family.');
            mapping(12) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.payload.type',{'material.payloadType'},'normalized_enum','always','Canonical payload identity.');
            mapping(13) = NMResultsViewerScientificAnnotation.mapRow('schema.fusion.mode',{'material.fusionMode'},'normalized_enum','always','Training fusion topology of the resolved model result.');
            mapping(14) = NMResultsViewerScientificAnnotation.mapRow('schema.source.id',{'material.sourceId'},'normalized_enum','always','Evaluation/result source identity, e.g. cv or an OOCV/application source.');
            mapping(15) = NMResultsViewerScientificAnnotation.mapRow('schema.source.modelSource',{'material.modelSource'},'normalized_enum','always','Resolved primary/meta/modality model source.');
            mapping(16) = NMResultsViewerScientificAnnotation.mapRow('schema.source.subgroupIndex',{'material.subgroupIndex'},'direct','always','Resolved OOCV subgroup index when applicable; NaN otherwise.');
            cached=mapping;
        end

        function value = applyResultRule(mappingRow,material)
            paths = mappingRow.materialPaths;
            values = cell(1,numel(paths));
            for ii=1:numel(paths)
                field = paths{ii}(10:end);
                values{ii}=material.(field);
            end
            switch mappingRow.rule
                case 'direct'
                    value=values{1};
                case 'normalized_enum'
                    value=values{1};
                case 'payload_to_model_result_type'
                    switch values{1}
                        case 'classification', value='binary_classification';
                        case 'regression', value='regression';
                        case 'multiclass', value='multiclass_classification';
                        case 'optimization_payload', value='model_optimization';
                        otherwise, value=values{1};
                    end
                case 'performance_dichotomization_index'
                    if strcmp(values{2},'classification')
                        value=double(values{1});
                    else
                        value=NaN;
                    end
                otherwise
                    error('NMResultsViewerScientificAnnotation:InvalidMappingRule', ...
                        'Unsupported result-annotation mapping rule %s.',mappingRow.rule);
            end
        end

        function mapping = featureInspectionMapping()
            persistent cached
            if ~isempty(cached), mapping=cached; return; end
            tmpl = struct('schemaPath','','materialPaths',{{}},'rule','', ...
                'applicability','','meaning','');
            mapping = repmat(tmpl,1,26);
            mapping(1) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.analysis.index',{'material.analysisIndex'},'direct','always','Analysis identity.');
            mapping(2) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.index',{'material.targetIndex'},'direct','always','Analysis-local target position used by result materializers.');
            mapping(3) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.nativeIndex',{'material.targetNativeIndex'},'direct','always','Originating NM.label column when the target is native.');
            mapping(4) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.target.name',{'material.targetLabelName'},'direct','always','Human-facing resolved target name.');
            mapping(5) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modelResult.type',{'material.analysisMode'},'model_result_type','always','Scientific model-result kind.');
            mapping(6) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modelResult.index',{'material.classifierIndex'},'direct','always','Model-result index resolved by the domain authority.');
            mapping(7) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modelResult.dichotomizationIndex',{'material.classifierIndex','material.analysisMode'}, ...
                'binary_dichotomizer_index','binary_dichotomizer','Binary dichotomization identity when applicable.');
            mapping(8) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.fusion.mode',{'material.fusionMode'},'normalized_enum','always','Feature-fusion topology.');
            mapping(9) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.featureSpace.kind',{'material.featureKind'},'normalized_enum','always','Scientific feature-domain kind.');
            mapping(10) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.featureSpace.scope',{'material.fusionMode','material.selectedContextIsCombined'}, ...
                'fusion_combined_to_feature_space_scope','always','Cross-modal versus modality-local feature space.');
            mapping(11) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modality.varinds',{'material.modalityVarinds'},'direct','always','Authoritative DataIO modality identities.');
            mapping(12) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modality.descriptions',{'material.modalityDescriptions'},'direct','always','User-provided DataIO modality descriptions.');
            mapping(13) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modality.provenanceTypes',{'material.modalitySourceTypes'},'direct','always','Canonical DataIO provenance source types.');
            mapping(14) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modality.provenanceTypeLabels',{'material.modalitySourceTypeLabels'},'direct','always','DataIO-owned user-facing source-type labels.');
            mapping(15) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.modality.role',{'material.fusionMode','material.componentIndex','material.selectedContextIsCombined'}, ...
                'fusion_component_to_modality_role','always','Role of modality inside the resolved feature topology.');
            mapping(16) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.component.applicable',{'material.componentIndex','material.backprojectionComponentId'}, ...
                'component_applicability','always','Whether a retained/backprojected component is part of the scientific identity.');
            mapping(17) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.component.index',{'material.componentIndex'},'finite_component_index','component_applicable','Scientific component identity.');
            mapping(18) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.component.scope',{'material.fusionMode','material.componentIndex'}, ...
                'fusion_to_component_scope','always','Cross-modal versus modality-local component semantics.');
            mapping(19) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.payload.family',{},'constant:feature','always','Cross-domain payload family.');
            mapping(20) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.payload.type',{'material.measureId'},'direct','always','Canonical feature-measure identity.');
            mapping(21) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.featureSpace.namesAvailable',{'material.featureNamesAvailable'},'direct','always','Whether the resolved feature space has authoritative semantic names.');
            mapping(22) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.featureSpace.nameSource',{'material.featureNameSource'},'direct','always','Authoritative semantic feature-name source for the resolved feature space.');
            mapping(23) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.featureSpace.spatialDomain',{'material.roiSpatialDomain'},'normalized_enum','roi_only','Canonical ROI spatial representation domain.');
            mapping(24) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.featureSpace.spatialSemantics',{'material.roiSpatialSemantics'},'normalized_enum','roi_only','Canonical ROI spatial semantics.');
            mapping(25) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.featureSpace.identityModel',{'material.roiIdentityModel'},'normalized_enum','roi_only','Canonical ROI parcel identity model.');
            mapping(26) = NMResultsViewerScientificAnnotation.mapRow( ...
                'schema.featureSpace.spatialReferenceIdentity',{'material.roiSpatialReferenceIdentity'},'direct','roi_only','Opaque producer-owned ROI spatial-reference identity.');
            cached=mapping;
        end

        function mapping = mliMapping()
            % mliMapping  Reuse Feature Inspection coordinates without a component axis.
            %
            % Authority/scientific contract: the Feature Inspection mapping is the
            % canonical coordinate mapping for analysis/target/model/fusion/modality/
            % feature-space semantics. MLI changes only schema.payload.family; fromMLI
            % enforces component non-applicability before projection.
            % Materialization/performance: copies one compact mapping table; no result
            % arrays or spatial resources are touched. Failure semantics: absence of the
            % canonical payload-family mapping is an explicit contract error.
            % Side effects: none.
            persistent cached
            if ~isempty(cached), mapping=cached; return; end
            mapping = NMResultsViewerScientificAnnotation.featureInspectionMapping();
            hit = find(strcmp({mapping.schemaPath},'schema.payload.family'),1,'first');
            if isempty(hit)
                error('NMResultsViewerScientificAnnotation:InvalidMapping','Feature-vector mapping lacks schema.payload.family.');
            end
            mapping(hit).rule = 'constant:ml_interpretation';
            mapping(hit).meaning = 'Machine-learning interpretation payload family.';
            cached=mapping;
        end

        function row = mapRow(schemaPath,materialPaths,rule,applicability,meaning)
            row = struct('schemaPath',schemaPath, ...
                'materialPaths',{materialPaths}, ...
                'rule',rule, ...
                'applicability',applicability, ...
                'meaning',meaning);
        end

        function value = applyFeatureInspectionRule(mappingRow,material)
            paths = mappingRow.materialPaths;
            values = cell(1,numel(paths));
            for ii = 1:numel(paths)
                field = paths{ii}(10:end);
                values{ii} = material.(field);
            end
            switch mappingRow.rule
                case 'direct'
                    value = values{1};
                case 'normalized_enum'
                    value = values{1};
                case 'model_result_type'
                    value = NMResultsViewerScientificAnnotation.modelResultType(values{1});
                case 'binary_dichotomizer_index'
                    if strcmp(NMResultsViewerScientificAnnotation.modelResultType(values{2}),'binary_dichotomizer')
                        value = double(values{1});
                    else
                        value = NaN;
                    end
                case 'fusion_combined_to_feature_space_scope'
                    value = NMResultsViewerScientificAnnotation.featureSpaceScope(values{1},values{2});
                case 'fusion_component_to_modality_role'
                    componentApplicable = isfinite(double(values{2})) && ~isempty(material.backprojectionComponentId);
                    value = NMResultsViewerScientificAnnotation.modalityRole(values{1},componentApplicable,values{3});
                case 'component_applicability'
                    value = isfinite(double(values{1})) && ~isempty(values{2});
                case 'finite_component_index'
                    if isfinite(double(values{1})) && ~isempty(material.backprojectionComponentId)
                        value = double(values{1});
                    else
                        value = NaN;
                    end
                case 'fusion_to_component_scope'
                    componentApplicable = isfinite(double(values{2})) && ~isempty(material.backprojectionComponentId);
                    value = NMResultsViewerScientificAnnotation.componentScope(values{1},componentApplicable);
                case 'constant:feature'
                    value = 'feature';
                case 'constant:ml_interpretation'
                    value = 'ml_interpretation';
                otherwise
                    error('NMResultsViewerScientificAnnotation:InvalidMappingRule', ...
                        'Unsupported scientific-annotation mapping rule %s.',mappingRow.rule);
            end
        end

        function schema = setSchemaValue(schema,schemaPath,value)
            parts = strsplit(schemaPath,'.');
            schema.(parts{2}).(parts{3}) = value;
        end

        function validateFeatureInspectionMaterial(material)
            % nm2-allow: fixed annotation material boundary validates scalar struct shape
            if ~isstruct(material) || ~isscalar(material)
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'Feature Inspection scientific material must be one scalar struct.');
            end
            expected = fieldnames(NMResultsViewerScientificAnnotation.featureInspectionMaterialTemplate());
            actual = fieldnames(material);
            if ~isempty(setxor(expected,actual))
                error('NMResultsViewerScientificAnnotation:InvalidMaterialSchema', ...
                    'Feature Inspection scientific material must use the fixed V1 field schema.');
            end
            scalarFields = {'analysisIndex','targetIndex','targetNativeIndex','resultTargetIndex','classifierIndex'};
            for ii = 1:numel(scalarFields)
                value = double(material.(scalarFields{ii}));
                % nm2-allow: fixed annotation material boundary validates positive integer coordinates
                if numel(value) ~= 1 || ~isfinite(value) || value < 1 || value ~= round(value)
                    error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                        'material.%s must be one positive integer.',scalarFields{ii});
                end
            end
            vectorFields = {'physicalVisRowIndices','physicalVarinds','physicalFeatureCounts'};
            lengths = zeros(1,numel(vectorFields));
            for ii = 1:numel(vectorFields)
                value = double(material.(vectorFields{ii}));
                if ~isvector(value) || any(~isfinite(value)) || any(value < 0) || any(value ~= round(value))
                    error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                        'material.%s must be a finite non-negative integer vector.',vectorFields{ii});
                end
                lengths(ii) = numel(value);
            end
            % nm2-allow: fixed annotation material boundary validates aligned physical context axes
            if numel(material.physicalContextIds) ~= lengths(1) || any(lengths ~= lengths(1))
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'Physical context IDs, VIS rows, varinds, and feature counts must have equal length.');
            end
            modalityVarinds = double(material.modalityVarinds);
            if ~isempty(modalityVarinds) && (~isvector(modalityVarinds) || any(~isfinite(modalityVarinds)) || any(modalityVarinds < 1) || any(modalityVarinds ~= round(modalityVarinds)))
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'material.modalityVarinds must be a finite positive-integer vector.');
            end
            modalityCount = numel(modalityVarinds);
            % nm2-allow: fixed annotation material boundary validates canonical logical metadata
            if ~islogical(material.featureNamesAvailable) || ~isscalar(material.featureNamesAvailable)
                error('NMResultsViewerScientificAnnotation:InvalidMaterial','material.featureNamesAvailable must be one logical scalar.');
            end
            % nm2-allow: fixed annotation material boundary validates caller-provided text metadata
            if ~ischar(material.featureNameSource) && ~(isstring(material.featureNameSource) && isscalar(material.featureNameSource))
                error('NMResultsViewerScientificAnnotation:InvalidMaterial','material.featureNameSource must be one text scalar.');
            end
            optionalCellFields = {'modalityDescriptions','modalitySourceTypes','modalitySourceTypeLabels', ...
                'modalityDatasources','modalitySources'};
            for ii = 1:numel(optionalCellFields)
                value = material.(optionalCellFields{ii});
                % nm2-allow: fixed annotation material boundary validates modality metadata axes
                if ~iscell(value) || (~isempty(value) && numel(value) ~= modalityCount)
                    error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                        'material.%s must be empty or align one-to-one with analysis modality identities.',optionalCellFields{ii});
                end
            end
            typeCodes = double(material.modalityTypeCodes);
            % nm2-allow: fixed annotation material boundary validates modality type-code axis
            if ~isempty(typeCodes) && (~isvector(typeCodes) || numel(typeCodes) ~= modalityCount)
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'material.modalityTypeCodes must be empty or align one-to-one with analysis modality identities.');
            end
            fusion = material.fusionMode;
            if ~ismember(fusion,{'none','early','intermediate','late'})
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'material.fusionMode must be none, early, intermediate, or late.');
            end
            roiTextFields = {'roiSpatialDomain','roiSpatialSemantics','roiIdentityModel','roiSpatialReferenceIdentity'};
            for ii = 1:numel(roiTextFields)
                value = material.(roiTextFields{ii});
                % nm2-allow: fixed annotation material boundary validates ROI provenance text scalars
                if ~ischar(value) && ~(isstring(value) && isscalar(value))
                    error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                        'material.%s must be one text scalar.',roiTextFields{ii});
                end
            end
            if strcmp(material.featureKind,'roi')
                domain = material.roiSpatialDomain;
                identityModel = material.roiIdentityModel;
                if ~ismember(domain,{'volume','surface'}) || ...
                        ~strcmp(material.roiSpatialSemantics,'canonical_roi') || ...
                        ~ismember(identityModel,{'atlas_label_id','hemisphere_annotation_id'}) || ...
                        isempty(material.roiSpatialReferenceIdentity) || ...
                        (strcmp(domain,'volume') && ~strcmp(identityModel,'atlas_label_id')) || ...
                        (strcmp(domain,'surface') && ~strcmp(identityModel,'hemisphere_annotation_id'))
                    error('NMResultsViewerScientificAnnotation:InvalidROIProvenance', ...
                        ['ROI Feature Inspection material requires complete canonical spatial provenance with ', ...
                         'volume/atlas_label_id or surface/hemisphere_annotation_id identity semantics.']);
                end
            elseif any(~cellfun(@isempty,{material.roiSpatialDomain,material.roiSpatialSemantics, ...
                    material.roiIdentityModel,material.roiSpatialReferenceIdentity}))
                error('NMResultsViewerScientificAnnotation:InvalidROIProvenance', ...
                    'Non-ROI Feature Inspection material must not carry ROI spatial provenance semantics.');
            end
        end

        function validateResultMaterial(material,expectedFamily)
            % Purpose: Validate one populated performance/optimization material record before it becomes Scientific Annotation.
            % Syntax: NMResultsViewerScientificAnnotation.validateResultMaterial(material,expectedFamily)
            % Inputs: material is one fixed-schema result material struct; expectedFamily is performance or optimization.
            % Outputs: No return value; successful completion certifies the material contract.
            % Authority and flow: Validates facts already resolved by the domain materializer; it does not inspect NM or repair missing semantics.
            % Scientific/state contract: Multi-class performance must be all_classes with no class identity or one_vs_rest with a positive classIndex and non-empty className; non-multiclass/optimization material must mark class contrast not_applicable.
            % Invariants: Exact field schema, positive integer scientific indices, non-empty payload type, and family agreement are mandatory.
            % Materialization and performance: O(number of fixed material fields); no files, XML, atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale allocation.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact scientific metadata only and safe on interactive state/annotation paths.
            % Failure semantics: Violations raise NMResultsViewerScientificAnnotation:InvalidMaterial or :InvalidMaterialSchema; no substitute material is constructed.
            % Side effects: None.
            % Consumers and dependencies: fromModelPerformance/fromModelOptimization via result-material construction.
            % nm2-allow: fixed result material boundary validates scalar struct shape
            if ~isstruct(material)||~isscalar(material)
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'Scientific result material must be one scalar struct.');
            end
            if strcmp(expectedFamily,'performance')
                expected=fieldnames(NMResultsViewerScientificAnnotation.performanceMaterialTemplate());
            else
                expected=fieldnames(NMResultsViewerScientificAnnotation.optimizationMaterialTemplate());
            end
            if ~isempty(setxor(expected,fieldnames(material)))
                error('NMResultsViewerScientificAnnotation:InvalidMaterialSchema', ...
                    'Scientific result material must use the fixed field schema.');
            end
            numericFields={'analysisIndex','targetIndex','targetNativeIndex','classifierIndex'};
            for ii=1:numel(numericFields)
                value=double(material.(numericFields{ii}));
                % nm2-allow: fixed result material boundary validates positive integer coordinates
                if numel(value)~=1||~isfinite(value)||value<1||value~=round(value)
                    error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                        'material.%s must be one positive integer.',numericFields{ii});
                end
            end
            if ~strcmp(material.payloadFamily,expectedFamily)
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'material.payloadFamily must equal %s.',expectedFamily);
            end
            subgroupIndex=double(material.subgroupIndex);
            if ~(isscalar(subgroupIndex) && (isnan(subgroupIndex) || (isfinite(subgroupIndex) && subgroupIndex>=1 && subgroupIndex==round(subgroupIndex))))
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'material.subgroupIndex must be NaN or one positive integer.');
            end
            payloadType=material.payloadType;
            if isempty(payloadType)
                error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                    'material.payloadType must be non-empty.');
            end
            contrast=material.classContrast;
            classIndex=double(material.classIndex);
            className=material.className;
            if strcmp(expectedFamily,'performance') && strcmp(payloadType,'multiclass')
                if ~ismember(contrast,{'all_classes','one_vs_rest'})
                    error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                        'Multi-class performance material.classContrast must be all_classes or one_vs_rest.');
                end
                if strcmp(contrast,'one_vs_rest')
                    if ~isscalar(classIndex)||~isfinite(classIndex)||classIndex<1||classIndex~=round(classIndex)||isempty(className)
                        error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                            'One-vs-rest performance requires one positive integer classIndex and non-empty className.');
                    end
                elseif ~(isscalar(classIndex)&&isnan(classIndex)) || ~isempty(className)
                    error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                        'Aggregate multi-class performance must not carry a selected class identity.');
                end
            else
                if ~strcmp(contrast,'not_applicable') || ~(isscalar(classIndex)&&isnan(classIndex)) || ~isempty(className)
                    error('NMResultsViewerScientificAnnotation:InvalidMaterial', ...
                        'Non-multiclass performance/optimization material must use a non-applicable class contrast.');
                end
            end
        end

        function type = modelResultType(analysisMode)
            switch analysisMode
                case 'regression'
                    type = 'regression_model';
                case {'classification','multiclass'}
                    type = 'binary_dichotomizer';
                otherwise
                    type = 'model_result';
            end
        end

        function scope = featureSpaceScope(fusionMode,isCombined)
            switch fusionMode
                case 'early'
                    scope = 'cross_modal';
                case 'intermediate'
                    if isCombined, scope = 'cross_modal'; else, scope = 'modality_local'; end
                case {'late','none'}
                    scope = 'modality_local';
                otherwise
                    scope = 'unspecified';
            end
        end

        function role = modalityRole(fusionMode,componentApplicable,isCombined)
            if strcmp(fusionMode,'early')
                if componentApplicable
                    role = 'component_projection';
                elseif isCombined
                    role = 'cross_modal_members';
                else
                    role = 'signature_partition';
                end
            elseif strcmp(fusionMode,'intermediate') && isCombined
                role = 'cross_modal_members';
            else
                role = 'feature_space';
            end
        end

        function scope = componentScope(fusionMode,componentApplicable)
            if ~componentApplicable
                scope = 'not_applicable';
            elseif strcmp(fusionMode,'early')
                scope = 'cross_modal';
            else
                scope = 'modality_local';
            end
        end
    end
end

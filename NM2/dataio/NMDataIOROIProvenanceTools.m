classdef NMDataIOROIProvenanceTools
% NMDataIOROIProvenanceTools
% -------------------------------------------------------------------------
% Canonical DataIO authority for ROI feature identity and spatial provenance.
%
% Multiple DataIO producers may create ROI matrices, but downstream consumers
% must receive one normalized contract.  This class is the only Results Viewer
% boundary permitted to interpret the retained raw ROI producer provenance.
%
% Contract R2A invariants:
%   - data-column order is the canonical ROI order;
%   - column-to-ROI identity is explicit and dimensionally exact;
%   - surface identity is hemisphere + source annotation ROI ID;
%   - every ROI field has a validated volumetric-atlas or surface-annotation
%     spatial reference;
%   - names, vector length, or generic VIS feature metadata never imply ROI
%     semantics.
% -------------------------------------------------------------------------

    methods (Static)
        function out = template()
            out = struct( ...
                'schema','NMDataIOROIProvenance', ...
                'schemaVersion',1, ...
                'contractVersion','R2A', ...
                'ok',false, ...
                'message','ROI spatial information is unavailable.', ...
                'featureDomain','roi_field', ...
                'nColumns',0, ...
                'columnIndex',[], ...
                'columnToROI',[], ...
                'columnKeys',{{}}, ...
                'roiIDs',[], ...
                'roiNames',{{}}, ...
                'hemisphere',{{}}, ...
                'mniCoordinates',zeros(0,3), ...
                'spatialReferences',NMDataIOROIProvenanceTools.emptySpatialReferences(), ...
                'producer',NMDataIOROIProvenanceTools.producerTemplate());
        end

        function tf = declaredInDescriptor(dd)
            % declaredInDescriptor  Test only documented ROI producer/canonical fields.
            tf = false;
            if ~isstruct(dd) || ~isscalar(dd), return; end
            names = {'roiProvenance','atlasCollapseProvenance','surfaceRoiInfo'};
            tf = any(cellfun(@(f)isfield(dd,f) && isstruct(dd.(f)) && ~isempty(fieldnames(dd.(f))),names));
            if tf, return; end
            if isfield(dd,'input_settings') && isstruct(dd.input_settings) && isscalar(dd.input_settings)
                input = dd.input_settings;
                tf = any(cellfun(@(f)isfield(input,f) && isstruct(input.(f)) && ~isempty(fieldnames(input.(f))),names));
            end
        end

        function out = normalizeDescriptor(dd, nColumns)
            % normalizeDescriptor  Resolve one descriptor through the canonical ROI boundary.
            %
            % The resolution path is deterministic: persisted canonical contract,
            % then one documented raw producer family for compatibility.  Generic
            % ROI-looking fields are deliberately ignored.
            if nargin < 2, nColumns = []; end
            out = NMDataIOROIProvenanceTools.template();
            if ~isstruct(dd) || ~isscalar(dd)
                out.message = 'The ROI modality information is invalid.';
                return;
            end
            if isfield(dd,'roiProvenance') && isstruct(dd.roiProvenance) && ~isempty(fieldnames(dd.roiProvenance))
                out = NMDataIOROIProvenanceTools.validate(dd.roiProvenance, nColumns);
                return;
            end
            input = struct();
            if isfield(dd,'input_settings') && isstruct(dd.input_settings) && isscalar(dd.input_settings)
                input = dd.input_settings;
            end
            if isfield(input,'roiProvenance') && isstruct(input.roiProvenance) && ~isempty(fieldnames(input.roiProvenance))
                out = NMDataIOROIProvenanceTools.validate(input.roiProvenance, nColumns);
                return;
            end

            atlasProv = NMDataIOROIProvenanceTools.documentedField(dd, input, 'atlasCollapseProvenance');
            surfaceProv = NMDataIOROIProvenanceTools.documentedField(dd, input, 'surfaceRoiInfo');
            if ~isempty(fieldnames(atlasProv)) && ~isempty(fieldnames(surfaceProv))
                out.message = ['The saved ROI definition contains both a volumetric atlas definition and a surface annotation, ', ...
                    'but does not identify which one defines the ROI columns. Re-import the modality and select one ROI definition.'];
                return;
            end
            if ~isempty(fieldnames(atlasProv))
                out = NMDataIOROIProvenanceTools.fromAtlasCollapse(atlasProv, nColumns);
                return;
            end
            if ~isempty(fieldnames(surfaceProv))
                out = NMDataIOROIProvenanceTools.fromSurfaceCollapse(surfaceProv, nColumns);
                return;
            end
            out.message = 'The modality does not contain the ROI definition required for spatial QC.';
        end

        function out = fromAtlasCollapse(prov, nColumns)
            % fromAtlasCollapse  Normalize explicit volumetric atlas-collapse provenance.
            if nargin < 2, nColumns = []; end
            out = NMDataIOROIProvenanceTools.template();
            if ~isstruct(prov) || ~isscalar(prov)
                out.message = 'The saved atlas-based ROI definition is invalid.';
                return;
            end
            columnToROI = NMDataIOROIProvenanceTools.numericRowField(prov,'columnToROI');
            atlasROIIDs = NMDataIOROIProvenanceTools.numericRowField(prov,'roiIDs');
            atlasROINames = NMDataIOROIProvenanceTools.cellstrField(prov,'roiNames');
            if isempty(columnToROI)
                out.message = 'The saved atlas-based ROI definition does not map data columns to ROI IDs.';
                return;
            end
            if isempty(atlasROIIDs)
                out.message = 'The saved atlas-based ROI definition is missing ROI IDs.';
                return;
            end
            if numel(atlasROINames) ~= numel(atlasROIIDs)
                out.message = sprintf('Atlas-collapse ROI names/IDs differ in length: names=%g, IDs=%g.', numel(atlasROINames), numel(atlasROIIDs));
                return;
            end
            if numel(unique(atlasROIIDs)) ~= numel(atlasROIIDs)
                out.message = 'The saved atlas-based ROI definition contains duplicate ROI IDs.';
                return;
            end
            [matched, loc] = ismember(columnToROI, atlasROIIDs);
            if ~all(matched)
                out.message = sprintf('columnToROI contains ROI IDs absent from the atlas ROI identity list: %s.', ...
                    NMDataIOROIProvenanceTools.shortNumericList(columnToROI(~matched), 12));
                return;
            end
            if numel(unique(columnToROI)) ~= numel(columnToROI)
                out.message = 'Atlas-collapse columnToROI mapping assigns more than one feature column to the same ROI ID.';
                return;
            end
            if ~NMDataIOROIProvenanceTools.validCount(nColumns, numel(columnToROI))
                out.message = sprintf('Atlas-collapse ROI mapping has %g column(s), but the modality has %g feature column(s).', numel(columnToROI), double(nColumns));
                return;
            end
            atlasFile = NMDataIOROIProvenanceTools.textField(prov,'brainmaskOrAtlasFile');
            if isempty(atlasFile)
                out.message = 'The saved atlas-based ROI definition does not identify the atlas image used for this modality.';
                return;
            end
            atlasKind = NMDataIOROIProvenanceTools.textField(prov,'kind');
            if isempty(atlasKind), atlasKind = 'discrete3d'; end
            names = atlasROINames(loc);
            out.nColumns = numel(columnToROI);
            out.columnIndex = 1:out.nColumns;
            out.columnToROI = double(columnToROI);
            out.columnKeys = arrayfun(@(id)sprintf('volume:%0.15g',id), double(columnToROI), 'UniformOutput', false);
            out.roiIDs = double(columnToROI);
            out.roiNames = names(:)';
            out.hemisphere = repmat({''},1,out.nColumns);
            out.mniCoordinates = nan(out.nColumns,3);
            spatial = NMDataIOROIProvenanceTools.spatialTemplate();
            spatial.kind = 'volumetric_atlas';
            spatial.sourceFiles = {atlasFile};
            spatial.contentHash = NMDataIOROIProvenanceTools.textField(prov,'atlasContentHash');
            spatial.labelModel = atlasKind;
            spatial.roiIDs = double(atlasROIIDs);
            spatial.referenceDim = NMDataIOROIProvenanceTools.numericRowAlias(prov, {'referenceImageDim','voxelSpaceDim'});
            spatial.referenceMat = NMDataIOROIProvenanceTools.matrixAlias(prov, {'referenceImageMat','voxelSpaceMat'});
            if isempty(spatial.contentHash) || numel(spatial.referenceDim)~=3 || ~isequal(size(spatial.referenceMat),[4 4])
                spatial.identity = atlasFile;
            else
                spatial.identity = NMDataIOROIProvenanceTools.volumetricReferenceIdentity( ...
                    spatial.contentHash,spatial.referenceDim,spatial.referenceMat);
            end
            spatial.labelDescriptor = NMDataIOROIProvenanceTools.structField(prov,'atlasLabelDescriptor');
            spatial.validated = true;
            spatial.validationBasis = 'atlas_collapse_producer';
            out.spatialReferences = spatial;
            out.producer.kind = 'atlas_collapse';
            out.producer.collapseMethod = NMDataIOROIProvenanceTools.textField(prov,'collapseMethod');
            out.producer.sourceFiles = NMDataIOROIProvenanceTools.cellstrField(prov,'originalImageFiles');
            out = NMDataIOROIProvenanceTools.validate(out, nColumns);
        end

        function out = fromSurfaceCollapse(info, nColumns)
            % fromSurfaceCollapse  Normalize native annotation-collapse output into canonical surface ROI provenance.
            %
            % Purpose and authority:
            %   Preserve the collapse producer's exact hemisphere + source annotation-ID identity and
            %   canonical annotation files. Optional surfaceGeometryFilesByHemisphere is propagated only
            %   as validated display geometry; it does not participate in ROI identity construction.
            %
            % Scientific/state contract:
            %   Column order is the canonical ROI order. Annotation IDs define parcel membership and
            %   hemisphere is part of every ROI key. Names and mesh geometry are never used to infer IDs.
            %
            % Materialization and performance:
            %   Pure provenance normalization. Performs no file reads, annotation parsing, or mesh scans;
            %   safe after the producer has completed explicit source materialization.
            %
            % Failure semantics:
            %   Missing/duplicate IDs, invalid hemisphere identities, or column-count disagreement make
            %   the returned provenance invalid explicitly; no positional or anatomical-name fallback is used.
            if nargin < 2, nColumns = []; end
            out = NMDataIOROIProvenanceTools.template();
            if ~isstruct(info) || ~isscalar(info)
                out.message = 'The saved surface ROI definition is invalid.';
                return;
            end
            roiIDs = NMDataIOROIProvenanceTools.numericRowField(info,'roiSourceIDs');
            names = NMDataIOROIProvenanceTools.cellstrField(info,'roiNames');
            hemi = NMDataIOROIProvenanceTools.cellstrField(info,'hemisphere');
            annotationFiles = NMDataIOROIProvenanceTools.cellstrField(info,'annotationFiles');
            if isempty(roiIDs)
                out.message = 'The saved surface ROI definition is missing annotation ROI IDs.';
                return;
            end
            if numel(names) ~= numel(roiIDs) || numel(hemi) ~= numel(roiIDs)
                out.message = sprintf('Surface ROI identity arrays differ in length: IDs=%g, names=%g, hemispheres=%g.', numel(roiIDs), numel(names), numel(hemi));
                return;
            end
            if isempty(annotationFiles)
                out.message = 'The saved surface ROI definition does not identify the annotation file used for this modality.';
                return;
            end
            hemi = cellfun(@(x)NMDataIOROIProvenanceTools.normalizeHemisphere(x), hemi, 'UniformOutput', false);
            if any(cellfun(@isempty,hemi))
                out.message = 'The saved surface ROI definition contains an unsupported or missing hemisphere.';
                return;
            end
            keys = cell(1,numel(roiIDs));
            for ii=1:numel(roiIDs)
                keys{ii} = sprintf('%s:%0.15g',hemi{ii},double(roiIDs(ii)));
            end
            if numel(unique(keys)) ~= numel(keys)
                out.message = 'The saved surface ROI definition maps more than one feature column to the same hemisphere and annotation ROI.';
                return;
            end
            if ~NMDataIOROIProvenanceTools.validCount(nColumns, numel(roiIDs))
                out.message = sprintf('Surface ROI mapping has %g column(s), but the modality has %g feature column(s).', numel(roiIDs), double(nColumns));
                return;
            end
            out.nColumns = numel(roiIDs);
            out.columnIndex = 1:out.nColumns;
            out.columnToROI = double(roiIDs);
            out.columnKeys = keys;
            out.roiIDs = double(roiIDs);
            out.roiNames = names(:)';
            out.hemisphere = hemi(:)';
            out.mniCoordinates = nan(out.nColumns,3);
            spatial = NMDataIOROIProvenanceTools.spatialTemplate();
            spatial.kind = 'surface_annotation';
            spatial.sourceFiles = annotationFiles(:)';
            spatial.identity = NMDataIOROIProvenanceTools.surfaceReferenceIdentity(roiIDs,names,hemi);
            spatial.labelModel = 'annotation_labels';
            spatial.roiIDs = double(roiIDs);
            spatial.validated = true;
            spatial.validationBasis = 'surface_annotation_collapse_producer';
            if isfield(info,'annotationFilesByHemisphere') && isstruct(info.annotationFilesByHemisphere)
                spatial.annotationFilesByHemisphere = info.annotationFilesByHemisphere;
            end
            if isfield(info,'surfaceGeometryFilesByHemisphere') && isstruct(info.surfaceGeometryFilesByHemisphere)
                spatial.surfaceGeometryFilesByHemisphere = info.surfaceGeometryFilesByHemisphere;
            end
            out.spatialReferences = spatial;
            out.producer.kind = 'surface_annotation_collapse';
            out.producer.collapseMethod = NMDataIOROIProvenanceTools.textField(info,'collapseMethod');
            out.producer.sourceFiles = NMDataIOROIProvenanceTools.cellstrField(info,'scalarFiles');
            out = NMDataIOROIProvenanceTools.validate(out, nColumns);
        end

        function out = fromDirectImport(roiIDs, roiNames, hemisphere, mniCoordinates, spatialReferences, producer, nColumns)
            % fromDirectImport  Construct canonical ROI provenance from an explicitly validated direct import.
            if nargin < 7, nColumns = []; end
            out = NMDataIOROIProvenanceTools.template();
            roiIDs = double(roiIDs(:)');
            roiNames = NMDataIOROIProvenanceTools.asCellstr(roiNames);
            hemisphere = NMDataIOROIProvenanceTools.asCellstr(hemisphere);
            if isempty(hemisphere), hemisphere = repmat({''},1,numel(roiIDs)); end
            if numel(roiNames) ~= numel(roiIDs) || numel(hemisphere) ~= numel(roiIDs)
                out.message = 'Direct ROI identity arrays must have identical lengths.';
                return;
            end
            keys = cell(1,numel(roiIDs));
            for ii=1:numel(roiIDs)
                if isempty(hemisphere{ii})
                    keys{ii}=sprintf('volume:%0.15g',roiIDs(ii));
                else
                    h=NMDataIOROIProvenanceTools.normalizeHemisphere(hemisphere{ii});
                    if isempty(h)
                        out.message=sprintf('Direct ROI hemisphere entry %g is invalid.',ii);
                        return;
                    end
                    hemisphere{ii}=h;
                    keys{ii}=sprintf('%s:%0.15g',h,roiIDs(ii));
                end
            end
            if numel(unique(keys)) ~= numel(keys)
                out.message = 'Direct ROI import contains duplicate column identities.';
                return;
            end
            if isempty(mniCoordinates), mniCoordinates=nan(numel(roiIDs),3); end
            out.nColumns=numel(roiIDs);
            out.columnIndex=1:out.nColumns;
            out.columnToROI=roiIDs;
            out.columnKeys=keys;
            out.roiIDs=roiIDs;
            out.roiNames=roiNames(:)';
            out.hemisphere=hemisphere(:)';
            out.mniCoordinates=double(mniCoordinates);
            out.spatialReferences=spatialReferences;
            out.producer=producer;
            out=NMDataIOROIProvenanceTools.validate(out,nColumns);
        end

        function s = validatedSpatialReference(kind, sourceFiles, roiIDs, opts)
            % validatedSpatialReference  Build one spatial reference after producer-side validation.
            if nargin < 4 || isempty(opts), opts=struct(); end
            s=NMDataIOROIProvenanceTools.spatialTemplate();
            s.kind=char(string(kind));
            s.sourceFiles=NMDataIOROIProvenanceTools.asCellstr(sourceFiles);
            s.identity=strjoin(s.sourceFiles,'|');
            if isfield(opts,'identity') && ~isempty(opts.identity)
                s.identity=strtrim(char(string(opts.identity)));
            end
            if isfield(opts,'contentHash') && ~isempty(opts.contentHash)
                s.contentHash=strtrim(char(string(opts.contentHash)));
            end
            s.roiIDs=double(roiIDs(:)');
            s.labelModel=NMDataIOROIProvenanceTools.textField(opts,'labelModel');
            s.referenceDim=NMDataIOROIProvenanceTools.numericRowField(opts,'referenceDim');
            if isfield(opts,'referenceMat') && isnumeric(opts.referenceMat), s.referenceMat=double(opts.referenceMat); end
            if isfield(opts,'labelDescriptor') && isstruct(opts.labelDescriptor), s.labelDescriptor=opts.labelDescriptor; end
            if isfield(opts,'annotationFilesByHemisphere') && isstruct(opts.annotationFilesByHemisphere), s.annotationFilesByHemisphere=opts.annotationFilesByHemisphere; end
            if isfield(opts,'surfaceGeometryFilesByHemisphere') && isstruct(opts.surfaceGeometryFilesByHemisphere), s.surfaceGeometryFilesByHemisphere=opts.surfaceGeometryFilesByHemisphere; end
            s.validated=true;
            s.validationBasis=NMDataIOROIProvenanceTools.textField(opts,'validationBasis');
            if isempty(s.validationBasis), s.validationBasis='direct_import_validation'; end
        end

        function identity = volumetricReferenceIdentity(contentHash, referenceDim, referenceMat)
            % volumetricReferenceIdentity  Build a path-independent identity for one labelled atlas.
            contentHash=strtrim(char(string(contentHash)));
            if isempty(contentHash)
                error('NMDataIOROIProvenanceTools:MissingAtlasContentIdentity', ...
                    'Path-independent volumetric atlas identity requires validated atlas content.');
            end
            referenceDim=double(referenceDim(:)');
            if numel(referenceDim)~=3 || any(~isfinite(referenceDim)) || any(referenceDim<1) || any(referenceDim~=round(referenceDim)) || ...
                    ~isequal(size(referenceMat),[4 4]) || any(~isfinite(double(referenceMat(:))))
                error('NMDataIOROIProvenanceTools:InvalidAtlasSpatialIdentity', ...
                    'Path-independent volumetric atlas identity requires finite 3-D dimensions and a finite 4-by-4 affine.');
            end
            parts={['content=' contentHash],['dim=' mat2str(double(referenceDim(:)'),17)], ...
                ['mat=' mat2str(double(referenceMat),17)]};
            identity=['volume-atlas-v1:' NMImagingContentIdentity.hashText(strjoin(parts,'|'))];
        end

        function identity = surfaceReferenceIdentity(roiIDs, roiNames, hemisphere)
            % surfaceReferenceIdentity  Stable semantic identity for a surface parcellation.
            roiIDs=double(roiIDs(:)');
            roiNames=NMDataIOROIProvenanceTools.asCellstr(roiNames);
            hemisphere=NMDataIOROIProvenanceTools.asCellstr(hemisphere);
            if any([numel(roiIDs),numel(roiNames),numel(hemisphere)] ~= numel(roiIDs)) || isempty(roiIDs)
                error('NMDataIOROIProvenanceTools:surfaceIdentityDimension','Surface ROI IDs, names, and hemisphere assignments must contain the same number of entries.');
            end
            parts=cell(1,numel(roiIDs));
            for ii=1:numel(roiIDs)
                h=NMDataIOROIProvenanceTools.normalizeHemisphere(hemisphere{ii});
                name=strtrim(char(string(roiNames{ii})));
                id=roiIDs(ii);
                if isempty(h) || isempty(name) || ~isfinite(id) || id==0 || abs(id-round(id))>1e-6
                    error('NMDataIOROIProvenanceTools:surfaceIdentityValue','Surface ROI column %g has an invalid hemisphere, ROI ID, or ROI name.',ii);
                end
                parts{ii}=sprintf('%s:%0.15g:%g:%s',h,id,numel(name),name);
            end
            identity=['surface-parcellation-v1|' strjoin(parts,'|')];
        end

        function p = directProducer(kind, sourceFiles, collapseMethod)
            % directProducer  Build compact producer provenance for a direct ROI import.
            if nargin < 3, collapseMethod=''; end
            p=NMDataIOROIProvenanceTools.producerTemplate();
            p.kind=char(string(kind));
            p.sourceFiles=NMDataIOROIProvenanceTools.asCellstr(sourceFiles);
            p.collapseMethod=char(string(collapseMethod));
        end

        function ref = spatialReference(roi, kind)
            % spatialReference  Resolve one validated canonical ROI spatial-reference record by exact kind.
            %
            % Purpose
            %   Centralize selection of the producer-owned spatial reference so downstream materializers do
            %   not independently scan canonical provenance or implement competing ambiguity rules.
            %
            % Inputs/outputs and authority
            %   roi is canonical ROI provenance; kind is volumetric_atlas or surface_annotation. ref is the
            %   exact validated reference record already owned by the provenance contract.
            %
            % Scientific/state contract
            %   Exactly one validated record of the requested kind is permitted. No fallback between volume
            %   and surface families and no inference from feature names, vector length, or source filenames.
            %
            % Materialization and performance
            %   O(R) metadata validation only. Performs no file IO, XML/annotation parsing, atlas/mesh loading,
            %   voxel/vertex scans, or feature-scale allocation. Safe on interactive selection/navigation paths.
            %
            % Failure semantics
            %   Invalid provenance, unsupported reference kind, absence, or ambiguity fail explicitly.
            kind = lower(strtrim(char(string(kind))));
            if ~ismember(kind,{'volumetric_atlas','surface_annotation'})
                error('NMDataIOROIProvenanceTools:UnsupportedSpatialKind', ...
                    'ROI spatial QC requires either a volumetric atlas or a surface annotation.');
            end
            roi = NMDataIOROIProvenanceTools.validate(roi, []);
            if ~roi.ok
                error('NMDataIOROIProvenanceTools:InvalidROIProvenance','%s',roi.message);
            end
            refs = roi.spatialReferences;
            hits = find(arrayfun(@(r)strcmp(NMDataIOROIProvenanceTools.textField(r,'kind'),kind) && logical(r.validated),refs));
            if numel(hits) ~= 1
                error('NMDataIOROIProvenanceTools:ROIReferenceAmbiguous', ...
                    'ROI spatial QC requires exactly one valid %s reference for this modality.',kind);
            end
            ref = refs(hits);
        end

        function projection = spatialProjection(roi)
            % spatialProjection  Project canonical ROI provenance into compact downstream spatial semantics.
            %
            % Purpose
            %   Provide Scientific Annotation/State and viewer dispatch with the minimum stable facts required
            %   to distinguish volumetric-atlas ROI fields from surface-annotation ROI fields.
            %
            % Inputs/outputs and authority
            %   roi is a canonical NMDataIOROIProvenance value. projection contains no voxel/vertex arrays and
            %   does not duplicate ROI identity; spatialReferenceIdentity is the opaque producer-owned identity.
            %
            % Scientific/state contract
            %   Exactly one validated spatial representation family must apply to one canonical ROI field.
            %   Volumetric identity is atlas label ID; surface identity is hemisphere + annotation ID.
            %
            % Materialization and performance
            %   O(R) metadata validation only. Performs no file IO, XML/annotation parsing, atlas/mesh loading,
            %   voxel/vertex scans, or feature-scale allocation. Safe on Results Viewer selection/navigation paths.
            %
            % Failure semantics
            %   Invalid, absent, or competing spatial families fail explicitly. No feature-name or vector-length
            %   inference is permitted.
            roi = NMDataIOROIProvenanceTools.validate(roi, []);
            if ~roi.ok
                error('NMDataIOROIProvenanceTools:InvalidROIProvenance','%s',roi.message);
            end
            refs = roi.spatialReferences;
            kinds = arrayfun(@(r)NMDataIOROIProvenanceTools.textField(r,'kind'),refs,'UniformOutput',false);
            hits = find(ismember(kinds,{'volumetric_atlas','surface_annotation'}) & arrayfun(@(r)logical(r.validated),refs));
            if numel(hits) ~= 1
                error('NMDataIOROIProvenanceTools:AmbiguousSpatialProvenance', ...
                    'ROI spatial QC requires exactly one valid volumetric-atlas or surface-annotation reference.');
            end
            ref = refs(hits);
            kind = kinds{hits};
            if strcmp(kind,'volumetric_atlas')
                domain = 'volume'; identityModel = 'atlas_label_id';
            else
                domain = 'surface'; identityModel = 'hemisphere_annotation_id';
            end
            projection = struct('canonical',true,'spatialDomain',domain, ...
                'spatialSemantics','canonical_roi','identityModel',identityModel, ...
                'spatialReferenceKind',kind,'spatialReferenceIdentity',NMDataIOROIProvenanceTools.textField(ref,'identity'));
        end

        function payload = viewerMaterialization(roi, measureIds, valuesByMeasure)
            % viewerMaterialization  Retain canonical ROI columns and measure vectors at the viewer boundary.
            %
            % Purpose:
            %   Give ROI Mapper the producer-validated ROI axis and original ROI values without reconstructing
            %   either from an atlas-wide voxel/vertex field.
            %
            % Syntax:
            %   payload = NMDataIOROIProvenanceTools.viewerMaterialization()
            %   payload = NMDataIOROIProvenanceTools.viewerMaterialization(roi,measureIds,valuesByMeasure)
            %
            % Inputs:
            %   roi is validated NMDataIOROIProvenance. measureIds is one unique ID per cell in valuesByMeasure;
            %   each cell contains exactly one value per canonical ROI column.
            %
            % Outputs:
            %   A compact browser-resident payload containing the ordered ROI identity records and original
            %   per-measure ROI vectors. The zero-argument form returns the unavailable workspace template.
            %
            % Authority and scientific contract:
            %   Column order, ROI ID, hemisphere and spatial identity come only from canonical DataIO provenance.
            %   Measure values are retained before spatial expansion. Atlas labels, parcel names, geometry and
            %   expanded voxel/vertex counts never create or enlarge the ROI axis.
            %
            % Invariants:
            %   One column record exists for every canonical data column; measure IDs are unique; every measure
            %   vector has exactly nColumns values; spatial identity is the exact producer-owned identity.
            %
            % Materialization and performance:
            %   O(R*M) metadata/value copying at explicit workspace construction. No files, atlas arrays, annotation
            %   arrays or meshes are read, and no feature-scale spatial array is allocated.
            %
            % Failure, side effects and consumers:
            %   Invalid provenance, duplicate/empty measure IDs or dimensional disagreement fail explicitly.
            %   The method has no side effects. Results Viewer ROI Mapper is the sole browser consumer.
            columnTemplate = struct('columnIndex',0,'columnKey','','roiId',NaN,'roiName','','hemisphere','');
            overlayTemplate = struct('measureId','','values',[]);
            payload = struct('schema','NMCanonicalROIViewerMaterialization','schemaVersion',1, ...
                'available',false,'spatialDomain','','identityModel','','spatialReferenceIdentity','', ...
                'nColumns',0,'columns',repmat(columnTemplate,1,0),'overlays',repmat(overlayTemplate,1,0));
            if nargin == 0, return; end
            if nargin ~= 3
                error('NMDataIOROIProvenanceTools:ViewerMaterializationArguments', ...
                    'The ROI viewer requires valid ROI spatial information, measure names, and ROI values.');
            end
            roi = NMDataIOROIProvenanceTools.validate(roi, []);
            if ~roi.ok
                error('NMDataIOROIProvenanceTools:InvalidROIProvenance','%s',roi.message);
            end
            ids = NMDataIOROIProvenanceTools.asCellstr(measureIds);
            if ~iscell(valuesByMeasure) || numel(ids) ~= numel(valuesByMeasure) || isempty(ids) || ...
                    any(cellfun(@isempty,ids)) || numel(unique(ids)) ~= numel(ids)
                error('NMDataIOROIProvenanceTools:ViewerMeasureIdentity', ...
                    'The ROI viewer requires unique non-empty measure names and one ROI-value vector per measure.');
            end
            projection = NMDataIOROIProvenanceTools.spatialProjection(roi);
            columns = repmat(columnTemplate,1,roi.nColumns);
            for ii=1:roi.nColumns
                columns(ii) = struct('columnIndex',double(roi.columnIndex(ii)), ...
                    'columnKey',char(string(roi.columnKeys{ii})), ...
                    'roiId',double(roi.roiIDs(ii)), ...
                    'roiName',char(string(roi.roiNames{ii})), ...
                    'hemisphere',char(string(roi.hemisphere{ii})));
            end
            overlays = repmat(overlayTemplate,1,numel(ids));
            for ii=1:numel(ids)
                values = valuesByMeasure{ii};
                if ~(isnumeric(values) || islogical(values)) || ~isreal(values) || ~isvector(values) || numel(values) ~= roi.nColumns
                    error('NMDataIOROIProvenanceTools:ViewerMeasureDimension', ...
                        'Measure %s must provide exactly %g real ROI values.',ids{ii},roi.nColumns);
                end
                if any(isinf(double(values(:))))
                    error('NMDataIOROIProvenanceTools:ViewerMeasureInfinite', ...
                        'Measure %s contains infinite ROI values, which cannot be displayed safely.',ids{ii});
                end
                overlays(ii) = struct('measureId',ids{ii},'values',double(values(:)'));
            end
            payload.available = true;
            payload.spatialDomain = projection.spatialDomain;
            payload.identityModel = projection.identityModel;
            payload.spatialReferenceIdentity = projection.spatialReferenceIdentity;
            payload.nColumns = double(roi.nColumns);
            payload.columns = columns;
            payload.overlays = overlays;
        end

        function mapping = volumetricMappingTemplate(varargin)
            % volumetricMappingTemplate  Create the fixed resident canonical ROI voxel-column mapping contract.
            %
            % Purpose:
            %   Represent the invariant exact atlas-label -> canonical ROI-column mapping once so interactive
            %   measure changes do not repeat atlas membership discovery over the full voxel grid.
            %
            % Authority and flow:
            %   The mapping is produced only by prepareVolumetricMapping from validated canonical ROI provenance
            %   and the authoritative labelled atlas array. It is a visualization materialization of DataIO ROI
            %   identity, not a second ROI-identity authority.
            %
            % Scientific/state contract:
            %   lookupIndex is one-based into [unsupported; canonical ROI columns]: 1 means unsupported and
            %   2..nColumns+1 map exactly to canonical data columns 1..nColumns. No name matching, interpolation,
            %   resampling, or parcel inference is represented by this contract.
            %
            % Materialization and performance:
            %   The template itself allocates no feature-scale arrays. A populated mapping owns one compact integer
            %   voxel field plus O(R) parcel counts and is intended to remain resident across payload switches.
            tmpl = struct( ...
                'schema','NMCanonicalROIVolumetricMapping', ...
                'schemaVersion',1, ...
                'contractVersion','exact_atlas_label_columns_v1', ...
                'authorityIdentity','', ...
                'materializationIdentity','', ...
                'dimensions',[0 0 0], ...
                'nColumns',0, ...
                'roiIDs',[], ...
                'lookupIndexClass','', ...
                'lookupIndex',uint8([]), ...
                'voxelCounts',[], ...
                'supportVoxelCount',0);
            if nargin > 0 && isequal(varargin{1}, [])
                mapping = tmpl([]);
            else
                mapping = tmpl;
            end
        end

        function mapping = prepareVolumetricMapping(roi, atlasLabels, authorityIdentity)
            % prepareVolumetricMapping  Materialize exact atlas-label -> canonical ROI-column membership once.
            %
            % Purpose:
            %   Convert one authoritative labelled atlas into the compact lookup used by repeated canonical ROI
            %   viewer payloads. This removes repeated O(V) ismember/support-discovery work from metric switching.
            %
            % Syntax:
            %   mapping = NMDataIOROIProvenanceTools.prepareVolumetricMapping(roi,atlasLabels,authorityIdentity)
            %
            % Inputs:
            %   roi               Valid canonical ROI provenance.
            %   atlasLabels       Resident labelled atlas array on the canonical ROI feature grid.
            %   authorityIdentity Explicit identity of that resident atlas materialization (for Results Viewer this
            %                     is the feature-space cache key). If omitted, persisted spatial-reference identity
            %                     is used; callers retaining mappings across requests should provide it explicitly.
            %
            % Outputs:
            %   NMCanonicalROIVolumetricMapping with one compact integer lookup field and O(R) voxel counts.
            %
            % Authority and flow:
            %   Exact numeric atlas labels and canonical ROI IDs are the only mapping inputs. The output may be
            %   retained by a viewer/runtime cache, but downstream consumers must not reinterpret ROI identity.
            %
            % Scientific/state contract:
            %   Every canonical ROI ID must occur in the supplied atlas. lookupIndex=1 denotes voxels outside the
            %   canonical ROI set; lookupIndex=k+1 denotes canonical data column k exactly.
            %
            % Invariants:
            %   ROI order is unchanged; every mapped voxel has exactly one canonical column; supportVoxelCount equals
            %   the sum of per-ROI voxelCounts; materializationIdentity is derived from authoritative compact inputs.
            %
            % Materialization and performance:
            %   Performs exactly one O(V+R) atlas-membership pass and creates one compact uint8/uint16/uint32 lookup
            %   array. It performs no file IO, no dense feature-value expansion, no feature-scale hashing, and no
            %   repeated support validation. This is an explicit workspace/materialization operation, not a per-frame
            %   or per-payload operation.
            %
            % Failure semantics:
            %   Invalid provenance/atlas input or incomplete atlas coverage fails explicitly. No fallback mapping is
            %   attempted.
            if nargin < 3, authorityIdentity = ''; end
            projection = NMDataIOROIProvenanceTools.spatialProjection(roi);
            if ~strcmp(projection.spatialReferenceKind,'volumetric_atlas')
                error('NMDataIOROIProvenanceTools:NotVolumetricROI','Volumetric ROI display requires a volumetric-atlas spatial reference.');
            end
            roi = NMDataIOROIProvenanceTools.validate(roi, []);
            if ~(isnumeric(atlasLabels) || islogical(atlasLabels)) || ~isreal(atlasLabels) || isempty(atlasLabels)
                error('NMDataIOROIProvenanceTools:AtlasLabelsInvalid','Atlas labels must be one non-empty real numeric/logical array.');
            end
            if ~(ischar(authorityIdentity) || (isstring(authorityIdentity) && isscalar(authorityIdentity)))
                error('NMDataIOROIProvenanceTools:MappingAuthorityIdentity','The volumetric ROI mapping identifier is invalid.');
            end
            authorityIdentity = char(string(authorityIdentity));
            if isempty(authorityIdentity), authorityIdentity = projection.spatialReferenceIdentity; end
            dims = size(atlasLabels);
            if numel(dims) < 3, dims(end+1:3) = 1; end
            if numel(dims) > 3 && any(dims(4:end) ~= 1)
                error('NMDataIOROIProvenanceTools:AtlasDimensions','ROI atlas display requires one three-dimensional labelled atlas.');
            end
            dims = double(dims(1:3));
            ids = double(roi.roiIDs(:)');
            [mapped,columnIndex] = ismember(double(atlasLabels(:)),ids);
            counts = accumarray(columnIndex(mapped),1,[numel(ids) 1]);
            if any(counts < 1)
                missing = ids(counts < 1);
                error('NMDataIOROIProvenanceTools:AtlasCoverage', ...
                    'The labelled atlas is missing ROI ID(s) used by this modality: %s.',mat2str(missing(1:min(12,numel(missing)))));
            end
            maxLookupValue = numel(ids) + 1;
            if maxLookupValue <= double(intmax('uint8'))
                indexClass = 'uint8';
            elseif maxLookupValue <= double(intmax('uint16'))
                indexClass = 'uint16';
            else
                indexClass = 'uint32';
            end
            lookupIndex = ones(numel(columnIndex),1,indexClass);
            lookupIndex(mapped) = cast(columnIndex(mapped) + 1,indexClass);
            lookupIndex = reshape(lookupIndex,dims);
            roiIdentity = strjoin(roi.columnKeys,'>');
            materializationIdentity = NMImagingContentIdentity.hashText(strjoin({ ...
                'canonical_roi_voxel_columns_v1',authorityIdentity,projection.spatialReferenceIdentity, ...
                roiIdentity,mat2str(dims)},'|'));
            mapping = NMDataIOROIProvenanceTools.volumetricMappingTemplate();
            mapping.authorityIdentity = authorityIdentity;
            mapping.materializationIdentity = materializationIdentity;
            mapping.dimensions = dims;
            mapping.nColumns = double(roi.nColumns);
            mapping.roiIDs = ids;
            mapping.lookupIndexClass = indexClass;
            mapping.lookupIndex = lookupIndex;
            mapping.voxelCounts = double(counts(:)');
            mapping.supportVoxelCount = double(sum(counts));
        end

        function [expanded, support] = expandVolumetricValues(roi, roiValues, atlasLabels)
            % expandVolumetricValues  Expand one canonical ROI vector by exact atlas-label identity.
            %
            % Purpose and authority
            %   This is the single pure mapping authority for volumetric ROI values. Consumers provide the
            %   resident labelled atlas array; this function maps canonical ROI IDs to exactly matching voxels.
            %
            % Scientific/state contract
            %   No interpolation, resampling, fuzzy name matching, parcel reclassification, or vector-length
            %   inference is allowed. Every canonical ROI ID must occur in the supplied atlas.
            %
            % Materialization and performance
            %   O(V + R) over resident arrays using one ismember pass. Performs no file IO or atlas loading and
            %   creates one value array plus one logical support array on the supplied atlas grid. Safe only on
            %   explicit spatial materialization paths, not per-frame interactive navigation.
            %
            % Failure semantics
            %   Invalid provenance, non-real/non-numeric arrays, ROI-vector mismatch, or missing atlas labels
            %   raise deterministic errors.
            projection = NMDataIOROIProvenanceTools.spatialProjection(roi);
            if ~strcmp(projection.spatialReferenceKind,'volumetric_atlas')
                error('NMDataIOROIProvenanceTools:NotVolumetricROI','Volumetric ROI display requires a volumetric-atlas spatial reference.');
            end
            roi = NMDataIOROIProvenanceTools.validate(roi, []);
            if ~(isnumeric(roiValues) || islogical(roiValues)) || ~isreal(roiValues) || ~isvector(roiValues) || numel(roiValues)~=roi.nColumns
                error('NMDataIOROIProvenanceTools:ROIValueDimension','ROI values must be one real numeric/logical vector with exactly %g elements.',roi.nColumns);
            end
            if ~(isnumeric(atlasLabels) || islogical(atlasLabels)) || ~isreal(atlasLabels) || isempty(atlasLabels)
                error('NMDataIOROIProvenanceTools:AtlasLabelsInvalid','Atlas labels must be one non-empty real numeric/logical array.');
            end
            ids = double(roi.roiIDs(:)'); values = double(roiValues(:)');
            [mapped,columnIndex] = ismember(double(atlasLabels(:)),ids);
            counts = accumarray(columnIndex(mapped),1,[numel(ids) 1]);
            if any(counts<1)
                missing=ids(counts<1);
                error('NMDataIOROIProvenanceTools:AtlasCoverage', ...
                    'The labelled atlas is missing ROI ID(s) used by this modality: %s.',mat2str(missing(1:min(12,numel(missing)))));
            end
            expanded = nan(size(atlasLabels));
            expanded(mapped) = values(columnIndex(mapped));
            support = reshape(mapped,size(atlasLabels));
        end

        function [expanded, support, canonicalColumns] = expandSurfaceValues(roi, roiValues, hemisphere, annotationLabels)
            % expandSurfaceValues  Expand one canonical ROI vector onto one annotation-labelled hemisphere.
            %
            % Purpose and authority
            %   This is the single pure mapping authority for surface ROI values. ROI identity is always the
            %   ordered pair hemisphere + source annotation ID; numeric annotation IDs may repeat across hemispheres.
            %
            % Scientific/state contract
            %   The mesh supplies geometry only. Parcel membership comes exclusively from annotationLabels.
            %   No anatomical-name matching, smoothing, interpolation, or opposite-hemisphere fallback is allowed.
            %
            % Materialization and performance
            %   O(P + R_h) over resident annotation labels. Performs no file IO, annotation parsing, or mesh scans
            %   beyond the supplied label vector; creates one vertex value vector and logical support vector.
            %
            % Failure semantics
            %   Unsupported hemisphere, mismatched ROI values, or incomplete annotation coverage fail explicitly.
            projection = NMDataIOROIProvenanceTools.spatialProjection(roi);
            if ~strcmp(projection.spatialReferenceKind,'surface_annotation')
                error('NMDataIOROIProvenanceTools:NotSurfaceROI','Surface ROI display requires a surface-annotation spatial reference.');
            end
            roi = NMDataIOROIProvenanceTools.validate(roi, []);
            token = NMDataIOROIProvenanceTools.normalizeHemisphere(hemisphere);
            if isempty(token)
                error('NMDataIOROIProvenanceTools:SurfaceHemisphereInvalid','Surface ROI expansion requires hemisphere lh or rh.');
            end
            if ~(isnumeric(roiValues) || islogical(roiValues)) || ~isreal(roiValues) || ~isvector(roiValues) || numel(roiValues)~=roi.nColumns
                error('NMDataIOROIProvenanceTools:ROIValueDimension','ROI values must be one real numeric/logical vector with exactly %g elements.',roi.nColumns);
            end
            if ~(isnumeric(annotationLabels) || islogical(annotationLabels)) || ~isreal(annotationLabels) || isempty(annotationLabels)
                error('NMDataIOROIProvenanceTools:AnnotationLabelsInvalid','Annotation labels must be one non-empty real numeric/logical vector.');
            end
            canonicalColumns = find(strcmp(roi.hemisphere,token));
            if isempty(canonicalColumns)
                error('NMDataIOROIProvenanceTools:HemisphereNotUsed','This ROI modality contains no %s surface parcels.',upper(token));
            end
            ids = double(roi.roiIDs(canonicalColumns)); values = double(roiValues(canonicalColumns));
            labels = double(annotationLabels(:));
            [mapped,localIndex] = ismember(labels,ids);
            counts = accumarray(localIndex(mapped),1,[numel(ids) 1]);
            if any(counts<1)
                missing=ids(counts<1);
                error('NMDataIOROIProvenanceTools:AnnotationCoverage', ...
                    'The %s annotation is missing ROI ID(s) used by this modality: %s.',upper(token),mat2str(missing(1:min(12,numel(missing)))));
            end
            expanded = nan(numel(labels),1);
            expanded(mapped) = values(localIndex(mapped));
            support = mapped;
        end

        function out = validate(in, nColumns)
            % validate  Validate a persisted canonical ROI contract without loading scientific arrays.
            if nargin < 2, nColumns = []; end
            out = NMDataIOROIProvenanceTools.template();
            if ~isstruct(in) || ~isscalar(in)
                out.message = 'The saved ROI definition is invalid.';
                return;
            end
            if ~isfield(in,'schema') || ~strcmp(NMDataIOROIProvenanceTools.textField(in,'schema'),'NMDataIOROIProvenance') || ...
                    ~isfield(in,'schemaVersion') || ~isnumeric(in.schemaVersion) || ~isscalar(in.schemaVersion) || ~isequal(double(in.schemaVersion),1)
                out.message = 'This saved ROI definition was created by an unsupported NM2 version. Re-import the modality.';
                return;
            end
            required = {'featureDomain','nColumns','columnIndex','columnToROI','columnKeys','roiIDs','roiNames','hemisphere','mniCoordinates','spatialReferences','producer'};
            missing = required(~cellfun(@(f)isfield(in,f),required));
            if ~isempty(missing)
                out.message = sprintf('The saved ROI definition is incomplete; missing: %s.', strjoin(missing,', '));
                return;
            end
            if ~strcmp(NMDataIOROIProvenanceTools.textField(in,'featureDomain'),'roi_field')
                out.message = 'The saved ROI definition does not describe ROI-field data.';
                return;
            end
            if ~isnumeric(in.nColumns) || ~isscalar(in.nColumns)
                out.message = 'The saved ROI definition contains an invalid number of ROI columns.';
                return;
            end
            n = double(in.nColumns);
            if ~isfinite(n) || n < 1 || n ~= round(n)
                out.message = 'The saved ROI definition contains an invalid number of ROI columns.';
                return;
            end
            if ~NMDataIOROIProvenanceTools.validCount(nColumns,n)
                out.message = sprintf('The saved ROI definition contains %g ROI columns, but the modality contains %g feature columns.', n, double(nColumns));
                return;
            end
            if ~isnumeric(in.columnIndex) || ~isnumeric(in.columnToROI) || ~isnumeric(in.roiIDs)
                out.message = 'The saved ROI column and ROI-ID mappings are invalid.';
                return;
            end
            columnIndex = double(in.columnIndex(:)');
            columnToROI = double(in.columnToROI(:)');
            roiIDs = double(in.roiIDs(:)');
            if any(~isfinite(roiIDs)) || any(roiIDs == 0) || any(abs(roiIDs-round(roiIDs)) > 1e-6) || ...
                    any(~isfinite(columnToROI)) || any(columnToROI == 0) || any(abs(columnToROI-round(columnToROI)) > 1e-6)
                out.message = 'ROI IDs in the saved ROI definition must be finite non-zero integers.';
                return;
            end
            names = NMDataIOROIProvenanceTools.asCellstr(in.roiNames);
            hemi = NMDataIOROIProvenanceTools.asCellstr(in.hemisphere);
            keys = NMDataIOROIProvenanceTools.asCellstr(in.columnKeys);
            if ~isequal(columnIndex,1:n)
                out.message = 'The saved ROI column mapping does not match the data-column order.';
                return;
            end
            if any([numel(columnToROI),numel(roiIDs),numel(names),numel(hemi),numel(keys)] ~= n)
                out.message = 'The saved ROI definition must contain exactly one ROI entry per data column.';
                return;
            end
            if ~isequal(columnToROI,roiIDs)
                out.message = 'The saved ROI column-to-ID mapping is inconsistent.';
                return;
            end
            if any(cellfun(@isempty,names)) || any(cellfun(@isempty,keys))
                out.message = 'Every ROI data column must have a non-empty ROI name and identity.';
                return;
            end
            if numel(unique(keys)) ~= n
                out.message = 'ROI identities are duplicated across data columns.';
                return;
            end
            coords = double(in.mniCoordinates);
            if isempty(coords), coords = nan(n,3); end
            if ~isequal(size(coords),[n 3])
                out.message = sprintf('ROI MNI coordinates must contain %g rows and three columns (X, Y, Z).', n);
                return;
            end
            finiteRows = all(isfinite(coords),2);
            missingRows = all(isnan(coords),2);
            if any(~(finiteRows | missingRows))
                out.message = 'Each ROI must have either three finite MNI coordinates or three missing coordinate values.';
                return;
            end
            refs = in.spatialReferences;
            if ~isstruct(refs) || isempty(refs)
                out.message = 'ROI spatial QC requires an atlas or surface-annotation reference.';
                return;
            end
            allowedKinds = {'volumetric_atlas','surface_annotation'};
            kinds = cell(1,numel(refs));
            for ii=1:numel(refs)
                if ~isfield(refs(ii),'kind') || ~ismember(NMDataIOROIProvenanceTools.textField(refs(ii),'kind'),allowedKinds)
                    out.message = 'The saved ROI spatial reference type is unsupported.';
                    return;
                end
                kinds{ii} = NMDataIOROIProvenanceTools.textField(refs(ii),'kind');
                if ~isfield(refs(ii),'validated') || ~isscalar(refs(ii).validated) || ~isequal(logical(refs(ii).validated),true)
                    out.message = 'The saved ROI spatial reference could not be validated.';
                    return;
                end
                files = NMDataIOROIProvenanceTools.cellstrField(refs(ii),'sourceFiles');
                identity = NMDataIOROIProvenanceTools.textField(refs(ii),'identity');
                if isempty(files) || any(cellfun(@isempty,files)) || isempty(identity)
                    out.message = 'The saved ROI spatial reference does not identify its source atlas or annotation completely.';
                    return;
                end
                refIDs = NMDataIOROIProvenanceTools.numericRowField(refs(ii),'roiIDs');
                if isempty(refIDs) || any(~isfinite(refIDs)) || any(refIDs == 0) || any(abs(refIDs-round(refIDs)) > 1e-6)
                    out.message = 'The saved ROI spatial reference contains invalid ROI label IDs.';
                    return;
                end
                if ~all(ismember(roiIDs,refIDs))
                    out.message = 'The saved ROI spatial reference does not contain every ROI ID used by the data columns.';
                    return;
                end
                if strcmp(kinds{ii},'surface_annotation')
                    normalizedHemi = cellfun(@(x)NMDataIOROIProvenanceTools.normalizeHemisphere(x),hemi,'UniformOutput',false);
                    if any(cellfun(@isempty,normalizedHemi)) || ~isequal(normalizedHemi,hemi)
                        out.message = 'Every surface ROI data column must be assigned to the left or right hemisphere.';
                        return;
                    end
                    byHemi = struct();
                    if isfield(refs(ii),'annotationFilesByHemisphere') && isstruct(refs(ii).annotationFilesByHemisphere)
                        byHemi = refs(ii).annotationFilesByHemisphere;
                    end
                    usedHemi = unique(hemi,'stable');
                    geometryByHemi = struct();
                    if isfield(refs(ii),'surfaceGeometryFilesByHemisphere') && isstruct(refs(ii).surfaceGeometryFilesByHemisphere)
                        geometryByHemi = refs(ii).surfaceGeometryFilesByHemisphere;
                    end
                    for hh=1:numel(usedHemi)
                        token = usedHemi{hh};
                        if ~isfield(byHemi,token) || isempty(NMDataIOROIProvenanceTools.asCellstr(byHemi.(token)))
                            out.message = sprintf('The surface ROI definition does not identify an annotation file for hemisphere %s.',upper(token));
                            return;
                        end
                        if isfield(geometryByHemi,token) && ~isempty(geometryByHemi.(token)) && isempty(NMDataIOROIProvenanceTools.asCellstr(geometryByHemi.(token)))
                            out.message = sprintf('The surface ROI definition contains invalid display geometry for hemisphere %s.',upper(token));
                            return;
                        end
                    end
                end
            end
            if numel(unique(kinds)) ~= numel(kinds)
                out.message = 'The ROI definition contains more than one spatial reference of the same type.';
                return;
            end
            if ~isstruct(in.producer) || ~isscalar(in.producer) || isempty(NMDataIOROIProvenanceTools.textField(in.producer,'kind'))
                out.message = 'The saved ROI definition does not identify how the ROI data were created.';
                return;
            end
            out = in;
            out.ok = true;
            out.message = sprintf('Validated ROI spatial information for %g feature column(s).', n);
        end

        function tf = hasSpatialKind(roi, kind)
            roi = NMDataIOROIProvenanceTools.validate(roi, []);
            tf = false;
            if ~roi.ok, return; end
            refs = roi.spatialReferences;
            tf = any(arrayfun(@(r)strcmp(NMDataIOROIProvenanceTools.textField(r,'kind'),kind) && logical(r.validated), refs));
        end
    end

    methods (Static, Access = private)
        function refs = emptySpatialReferences()
            refs = repmat(NMDataIOROIProvenanceTools.spatialTemplate(),0,1);
        end

        function s = spatialTemplate()
            s = struct('kind','','identity','','contentHash','','sourceFiles',{{}},'labelModel','','roiIDs',[], ...
                'referenceDim',[],'referenceMat',[],'labelDescriptor',struct(), ...
                'annotationFilesByHemisphere',struct(),'surfaceGeometryFilesByHemisphere',struct(), ...
                'validated',false,'validationBasis','');
        end

        function p = producerTemplate()
            p = struct('kind','','collapseMethod','','sourceFiles',{{}});
        end

        function v = documentedField(dd, input, name)
            v = struct();
            if isfield(dd,name) && isstruct(dd.(name)) && isscalar(dd.(name)) && ~isempty(fieldnames(dd.(name)))
                v = dd.(name);
                return;
            end
            if isfield(input,name) && isstruct(input.(name)) && isscalar(input.(name)) && ~isempty(fieldnames(input.(name)))
                v = input.(name);
            end
        end

        function tf = validCount(requested, actual)
            tf = true;
            if isempty(requested), return; end
            requested = double(requested);
            tf = isscalar(requested) && isfinite(requested) && requested == actual;
        end

        function v = numericRowField(s, name)
            v = [];
            if isstruct(s) && isfield(s,name) && isnumeric(s.(name))
                v = double(s.(name)(:))';
            end
        end

        function v = numericRowAlias(s, names)
            v = [];
            for ii=1:numel(names)
                v = NMDataIOROIProvenanceTools.numericRowField(s,names{ii});
                if ~isempty(v), return; end
            end
        end

        function v = matrixAlias(s, names)
            v = [];
            for ii=1:numel(names)
                if isstruct(s) && isfield(s,names{ii}) && isnumeric(s.(names{ii})) && ~isempty(s.(names{ii}))
                    v = double(s.(names{ii}));
                    return;
                end
            end
        end

        function v = structField(s, name)
            v = struct();
            if isstruct(s) && isfield(s,name) && isstruct(s.(name))
                v = s.(name);
            end
        end

        function c = cellstrField(s, name)
            c = {};
            if isstruct(s) && isfield(s,name)
                c = NMDataIOROIProvenanceTools.asCellstr(s.(name));
            end
        end

        function c = asCellstr(v)
            if isempty(v), c = {}; return; end
            if ischar(v), c = cellstr(v); return; end
            if isstring(v), c = cellstr(v(:)); return; end
            if iscell(v)
                c = cell(size(v));
                for ii=1:numel(v)
                    if ischar(v{ii}) || isstring(v{ii})
                        c{ii} = strtrim(char(string(v{ii})));
                    else
                        c{ii} = strtrim(char(string(v{ii})));
                    end
                end
                c = c(:)';
                return;
            end
            c = cellstr(string(v(:)));
            c = c(:)';
        end

        function txt = textField(s, name)
            txt = '';
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                v = s.(name);
                if ischar(v) || (isstring(v) && isscalar(v))
                    txt = strtrim(char(string(v)));
                end
            end
        end

        function h = normalizeHemisphere(v)
            h = lower(strtrim(char(string(v))));
            switch h
                case {'l','left','lh'}, h='lh';
                case {'r','right','rh'}, h='rh';
                otherwise, h='';
            end
        end

        function txt = shortNumericList(v, nMax)
            v = double(v(:)');
            if nargin < 2 || isempty(nMax), nMax = 12; end
            k = min(numel(v),nMax);
            parts = arrayfun(@(x)sprintf('%0.15g',x),v(1:k),'UniformOutput',false);
            txt = strjoin(parts,', ');
            if numel(v)>k, txt=[txt ', ...']; end
        end
    end
end

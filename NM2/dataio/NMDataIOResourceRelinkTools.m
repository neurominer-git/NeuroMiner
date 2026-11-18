classdef NMDataIOResourceRelinkTools
% NMDataIOResourceRelinkTools
% Modality-scoped inventory and validated relocation of persisted file resources.
% Externalized feature storage remains owned by NMDataIOExternalStorageTools.

    methods (Static)
        function resources = list(NM,varind)
            dd = NM.datadescriptor{varind};
            state = NMDataIOStateTools.ioToState(dd.input_settings);
            resources = repmat(NMDataIOResourceRelinkTools.row(),0,1);

            switch state.sourceType
                case 'roi'
                    roiState = state.roi;
                    resources = NMDataIOResourceRelinkTools.addList(resources,'roi.files','ROI source file','Source data',roiState.files,false,'');
                    resources = NMDataIOResourceRelinkTools.addList(resources,'roi.vectorFiles','ROI vector file','Source data',roiState.vectorFiles,false,'');
                    resources = NMDataIOResourceRelinkTools.addOne(resources,'roi.tableFile','ROI table','Source data',roiState.tableFile,false,'');
                    resources = NMDataIOResourceRelinkTools.addList(resources,'roi.auxiliaryTableFiles','Auxiliary table','Auxiliary data',roiState.auxiliaryTableFiles,false,'');
                    resources = NMDataIOResourceRelinkTools.addOne(resources,'roi.sidecar','ROI description file','ROI definition',roiState.roiSidecarFile,false,'');
                    resources = NMDataIOResourceRelinkTools.addList(resources,'roi.globalTableFiles','Global-value table','Auxiliary data',roiState.globalTableFiles,false,'');
                    resources = NMDataIOResourceRelinkTools.addList(resources,'roi.weightingFiles','ROI weighting file','Weighting',roiState.weightingFiles,false,'');
                    roi = NMDataIOResourceRelinkTools.canonicalROI(NM,varind,dd);
                    resources = NMDataIOResourceRelinkTools.addROIReference(resources,roi,true);

                case {'image-list','surface-list'}
                    img = state.image;
                    resources = NMDataIOResourceRelinkTools.addList(resources,'image.imageFiles','Subject source file','Source data',img.imageFiles,false,'');
                    resources = NMDataIOResourceRelinkTools.addList(resources,'image.auxiliaryTableFiles','Auxiliary table','Auxiliary data',img.auxiliaryTableFiles,false,'');
                    resources = NMDataIOResourceRelinkTools.addList(resources,'image.globalTableFiles','Global-value table','Auxiliary data',img.globalTableFiles,false,'');
                    resources = NMDataIOResourceRelinkTools.addList(resources,'image.weightingFiles','Weighting / ranking map','Weighting',img.weightingFiles,false,'');
                    resources = NMDataIOResourceRelinkTools.addOne(resources,'image.atlasLabelFile','Atlas label descriptor','ROI definition',img.atlasLabelFile,false,'');
                    resources = NMDataIOResourceRelinkTools.addOne(resources,'image.maskFile','Mask / space-defining image','Spatial resource',img.maskFile,false,'');

                    if strcmp(state.sourceType,'surface-list')
                        contractAvailable = ~isempty(fieldnames(img.surfaceGeometryContract));
                        resources = NMDataIOResourceRelinkTools.addSurfaceGeometry(resources,img,contractAvailable);
                        resources = NMDataIOResourceRelinkTools.addList(resources,'surface.roi.lhScalar','LH surface scalar','Source data',img.surfaceRoiLHScalarFiles,false,'');
                        resources = NMDataIOResourceRelinkTools.addList(resources,'surface.roi.lhAnnot','LH subject annotation','Source data',img.surfaceRoiLHAnnotFiles,false,'');
                        resources = NMDataIOResourceRelinkTools.addList(resources,'surface.roi.rhScalar','RH surface scalar','Source data',img.surfaceRoiRHScalarFiles,false,'');
                        resources = NMDataIOResourceRelinkTools.addList(resources,'surface.roi.rhAnnot','RH subject annotation','Source data',img.surfaceRoiRHAnnotFiles,false,'');
                    end
                    if NMDataIOROIProvenanceTools.declaredInDescriptor(dd)
                        roi = NMDataIOResourceRelinkTools.canonicalROI(NM,varind,dd);
                        resources = NMDataIOResourceRelinkTools.addROIReference(resources,roi,false);
                    end
            end

            for k=1:numel(resources)
                % nm2-allow: explicit external resource status inspection boundary
                resources(k).exists = exist(NMDataIOResourceRelinkTools.filePart(resources(k).path),'file')==2;
                if resources(k).exists, resources(k).status='available'; else, resources(k).status='missing'; end
            end
        end

        function out = summary(resources)
            out = struct('count',numel(resources),'missing',nnz(strcmp({resources.status},'missing')), ...
                'relinkable',nnz([resources.relinkable]));
        end

        function [NM,messages,resources] = relink(NM,varind,resourceId,newPath)
            replacements = struct('resourceId',resourceId,'resourcePath',newPath);
            [NM,messages,resources] = NMDataIOResourceRelinkTools.relinkMany(NM,varind,replacements);
        end

        function replacements = locateUnderRoot(NM,varind,resourceIds,rootDir)
            % Resolve exact resource basenames under a user-selected root. Never pick an ambiguous match.
            if exist(rootDir,'dir')~=7
                error('NMDataIOResourceRelinkTools:MissingRoot','Selected resource root does not exist: %s',rootDir);
            end
            resources = NMDataIOResourceRelinkTools.list(NM,varind);
            if isempty(resourceIds) || numel(unique(resourceIds)) ~= numel(resourceIds)
                error('NMDataIOResourceRelinkTools:InvalidSelection','Select one or more distinct resource IDs.');
            end
            selected = repmat(NMDataIOResourceRelinkTools.row(),numel(resourceIds),1);
            for k=1:numel(resourceIds)
                hit = find(strcmp({resources.id},resourceIds{k}),1);
                if isempty(hit)
                    error('NMDataIOResourceRelinkTools:UnknownResource','Unknown modality resource: %s',resourceIds{k});
                end
                selected(k) = resources(hit);
                if ~selected(k).relinkable
                    error('NMDataIOResourceRelinkTools:ReadOnlyResource','Resource is inspection-only: %s',selected(k).role);
                end
            end
            % One directory enumeration for the full selection. File identity is checked at apply.
            entries = [dir(fullfile(rootDir,'*')); dir(fullfile(rootDir,'**','*'))];
            entries = entries(~[entries.isdir]);
            entries = entries(ismember(lower(string({entries.name})),lower(string({selected.basename}))));
            candidates = cell(numel(entries),1);
            for i=1:numel(entries)
                candidates{i} = fullfile(entries(i).folder,entries(i).name);
            end
            replacements = repmat(struct('resourceId','','resourcePath',''),numel(selected),1);
            for k=1:numel(selected)
                matched = unique(candidates(strcmpi({entries.name},selected(k).basename)),'stable');
                if isempty(matched)
                    error('NMDataIOResourceRelinkTools:MissingRootMatch', ...
                        'No file named %s was found under %s. Select a different root or relink the file individually.', ...
                        selected(k).basename,rootDir);
                end
                if numel(matched)~=1
                    error('NMDataIOResourceRelinkTools:AmbiguousRootMatch', ...
                        'Multiple files named %s were found under %s. Choose a narrower root or relink this resource individually. Matches: %s', ...
                        selected(k).basename,rootDir,strjoin(matched,' | '));
                end
                replacements(k).resourceId = selected(k).id;
                replacements(k).resourcePath = matched{1};
            end
        end

        function [NM,messages,resources] = relinkMany(NM,varind,replacements)
            % Apply a complete replacement set transactionally; validate coupled surface parts together.
            resources = NMDataIOResourceRelinkTools.list(NM,varind);
            if isempty(replacements) || numel(unique({replacements.resourceId})) ~= numel(replacements)
                error('NMDataIOResourceRelinkTools:InvalidSelection','Supply distinct resource replacements.');
            end
            surface = false(numel(replacements),1);
            surfaceROI = false(numel(replacements),1);
            for k=1:numel(replacements)
                hit = find(strcmp({resources.id},replacements(k).resourceId),1);
                if isempty(hit)
                    error('NMDataIOResourceRelinkTools:UnknownResource','Unknown modality resource: %s',replacements(k).resourceId);
                end
                resource = resources(hit);
                if ~resource.relinkable
                    error('NMDataIOResourceRelinkTools:ReadOnlyResource','Resource is inspection-only: %s',resource.role);
                end
                if exist(NMDataIOResourceRelinkTools.filePart(replacements(k).resourcePath),'file')~=2
                    error('NMDataIOResourceRelinkTools:MissingReplacement','Replacement resource does not exist: %s',replacements(k).resourcePath);
                end
                surface(k) = ismember(resource.validator,{'surface_native_geometry','surface_inflated_geometry'});
                surfaceROI(k) = ismember(resource.validator,{'roi_annotation_lh','roi_annotation_rh','roi_geometry_lh','roi_geometry_rh'});
            end
            candidate = NM;
            messages = NMDataIOMessageTools.emptyMessages();
            if any(surface)
                [candidate,msg] = NMDataIOResourceRelinkTools.relinkSurfaceGeometrySet(candidate,varind,replacements(surface));
                messages = [messages; msg];
            end
            if any(surfaceROI)
                [candidate,msg] = NMDataIOResourceRelinkTools.relinkDirectROISurfaceSet(candidate,varind,replacements(surfaceROI),resources);
                messages = [messages; msg];
                if NMDataIOMessageTools.hasFatal(msg), return; end
            end
            for k=find(~(surface(:)' | surfaceROI(:)'))
                hit = find(strcmp({resources.id},replacements(k).resourceId),1);
                resource = resources(hit);
                newPath = replacements(k).resourcePath;
                switch resource.validator
                    case 'roi_atlas'
                        [candidate,msg] = NMDataIOResourceRelinkTools.relinkDirectROIAtlas(candidate,varind,newPath);
                    otherwise
                        error('NMDataIOResourceRelinkTools:UnsupportedValidator','Unsupported resource validator: %s',resource.validator);
                end
                messages = [messages; msg];
                if NMDataIOMessageTools.hasFatal(msg), return; end
            end
            NM = candidate;
            resources = NMDataIOResourceRelinkTools.list(NM,varind);
        end
    end

    methods (Static, Access=private)
        function roi = canonicalROI(NM,varind,dd)
            roi = NMDataIOROIProvenanceTools.normalizeDescriptor(dd,size(NM.Y{varind},2));
            if ~roi.ok
                error('NMDataIOResourceRelinkTools:InvalidROIProvenance','%s',roi.message);
            end
        end

        function resources = addROIReference(resources,roi,relinkable)
            projection = NMDataIOROIProvenanceTools.spatialProjection(roi);
            ref = NMDataIOROIProvenanceTools.spatialReference(roi,projection.spatialReferenceKind);
            switch projection.spatialReferenceKind
                case 'volumetric_atlas'
                    resources = NMDataIOResourceRelinkTools.addOne(resources,'roi.atlas','Volumetric ROI atlas','ROI spatial reference', ...
                        ref.sourceFiles{1},relinkable,'roi_atlas');
                case 'surface_annotation'
                    if ~isempty(ref.annotationFilesByHemisphere.lh)
                        resources = NMDataIOResourceRelinkTools.addOne(resources,'roi.annotation.lh','LH ROI annotation','ROI spatial reference', ...
                            ref.annotationFilesByHemisphere.lh{1},relinkable,'roi_annotation_lh');
                    end
                    if ~isempty(ref.annotationFilesByHemisphere.rh)
                        resources = NMDataIOResourceRelinkTools.addOne(resources,'roi.annotation.rh','RH ROI annotation','ROI spatial reference', ...
                            ref.annotationFilesByHemisphere.rh{1},relinkable,'roi_annotation_rh');
                    end
                    if ~isempty(ref.surfaceGeometryFilesByHemisphere.lh)
                        resources = NMDataIOResourceRelinkTools.addOne(resources,'roi.geometry.lh','LH ROI display geometry','ROI spatial reference', ...
                            ref.surfaceGeometryFilesByHemisphere.lh{1},relinkable,'roi_geometry_lh');
                    end
                    if ~isempty(ref.surfaceGeometryFilesByHemisphere.rh)
                        resources = NMDataIOResourceRelinkTools.addOne(resources,'roi.geometry.rh','RH ROI display geometry','ROI spatial reference', ...
                            ref.surfaceGeometryFilesByHemisphere.rh{1},relinkable,'roi_geometry_rh');
                    end
            end
        end

        function resources = addSurfaceGeometry(resources,img,relinkable)
            native = NMDataIOSurfaceTools.splitSurfaceFileList(img.surfaceGeometryFile);
            inflated = NMDataIOSurfaceTools.splitSurfaceFileList(img.surfaceInflatedGeometryFile);
            for k=1:numel(native)
                resources = NMDataIOResourceRelinkTools.addOne(resources,sprintf('surface.geometry.native.%d',k), ...
                    sprintf('Surface native geometry %d',k),'Surface geometry',native{k},relinkable,'surface_native_geometry');
            end
            for k=1:numel(inflated)
                resources = NMDataIOResourceRelinkTools.addOne(resources,sprintf('surface.geometry.inflated.%d',k), ...
                    sprintf('Surface inflated geometry %d',k),'Surface geometry',inflated{k},relinkable,'surface_inflated_geometry');
            end
        end

        function [NM,messages] = relinkDirectROIAtlas(NM,varind,newPath)
            dd = NM.datadescriptor{varind};
            state = NMDataIOStateTools.ioToState(dd.input_settings);
            roi = NMDataIOResourceRelinkTools.canonicalROI(NM,varind,dd);
            ref = NMDataIOROIProvenanceTools.spatialReference(roi,'volumetric_atlas');
            candidate = NMDataIOAtlasDescriptorTools.atlasNodeCoordinates(newPath,ref.roiIDs);
            if ~candidate.ok || ~all(candidate.matchedMask)
                error('NMDataIOResourceRelinkTools:AtlasLabels','Replacement ROI atlas failed label validation: %s',candidate.message);
            end
            if ~isempty(ref.referenceDim) && ~isequal(double(ref.referenceDim(:)'),candidate.referenceDim)
                error('NMDataIOResourceRelinkTools:AtlasGeometry','Replacement ROI atlas dimensions do not match the persisted spatial reference.');
            end
            if ~isempty(ref.referenceMat) && max(abs(double(ref.referenceMat(:))-candidate.referenceMat(:)))>1e-6
                error('NMDataIOResourceRelinkTools:AtlasGeometry','Replacement ROI atlas affine does not match the persisted spatial reference.');
            end
            [matched,loc] = ismember(double(roi.roiIDs(:)'),double(ref.roiIDs(:)'));
            if ~all(matched), error('NMDataIOResourceRelinkTools:AtlasLabels','Persisted ROI identities are inconsistent with the atlas spatial reference.'); end
            stored = double(roi.mniCoordinates);
            finiteRows = all(isfinite(stored),2);
            replacement = double(candidate.coordinates(loc,:));
            if any(finiteRows) && any(max(abs(stored(finiteRows,:)-replacement(finiteRows,:)),[],2)>1e-4)
                error('NMDataIOResourceRelinkTools:AtlasCoordinates','Replacement ROI atlas centroids do not match the persisted labelled-atlas contract.');
            end

            hit = find(strcmp({roi.spatialReferences.kind},'volumetric_atlas'));
            roi.spatialReferences(hit).sourceFiles = {newPath};
            roi.spatialReferences(hit).identity = candidate.spatialIdentity;
            roi.spatialReferences(hit).referenceDim = candidate.referenceDim;
            roi.spatialReferences(hit).referenceMat = candidate.referenceMat;
            state.roi.atlasFile = newPath;
            state.matrix.roiProvenance = roi;
            dd = NMDataIOResourceRelinkTools.persistState(NM,varind,dd,state);
            dd.roiProvenance = roi;
            dd.input_settings.roiProvenance = roi;
            NM.datadescriptor{varind} = dd;
            messages = NMDataIOMessageTools.make('ok',false,'resourceRelink.atlas', ...
                sprintf('Relinked ROI atlas to %s.',newPath),0,'green*');
        end

        function [NM,messages] = relinkDirectROISurfaceSet(NM,varind,replacements,resources)
            dd = NM.datadescriptor{varind};
            state = NMDataIOStateTools.ioToState(dd.input_settings);
            roi = NMDataIOResourceRelinkTools.canonicalROI(NM,varind,dd);
            oldRef = NMDataIOROIProvenanceTools.spatialReference(roi,'surface_annotation');
            spec = state.roi;
            for k=1:numel(replacements)
                hit = find(strcmp({resources.id},replacements(k).resourceId),1);
                validator = resources(hit).validator;
                newPath = replacements(k).resourcePath;
                switch validator
                    case 'roi_annotation_lh', spec.lhAnnotationFile = newPath;
                    case 'roi_annotation_rh', spec.rhAnnotationFile = newPath;
                    case 'roi_geometry_lh', spec.lhSurfaceGeometryFile = newPath;
                    case 'roi_geometry_rh', spec.rhSurfaceGeometryFile = newPath;
                end
            end
            [replacement,messages] = NMDataIOROIDirectTools.validateSurfaceAnnotations(spec,roi.roiIDs,roi.roiNames,roi.hemisphere);
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if ~strcmp(replacement.identity,oldRef.identity)
                error('NMDataIOResourceRelinkTools:SurfaceROIIdentity','Replacement surface ROI resource changes the persisted ROI identity.');
            end
            hit = find(strcmp({roi.spatialReferences.kind},'surface_annotation'));
            roi.spatialReferences(hit) = replacement;
            state.roi.lhAnnotationFile = spec.lhAnnotationFile;
            state.roi.rhAnnotationFile = spec.rhAnnotationFile;
            state.roi.lhSurfaceGeometryFile = spec.lhSurfaceGeometryFile;
            state.roi.rhSurfaceGeometryFile = spec.rhSurfaceGeometryFile;
            state.matrix.roiProvenance = roi;
            dd = NMDataIOResourceRelinkTools.persistState(NM,varind,dd,state);
            dd.roiProvenance = roi;
            dd.input_settings.roiProvenance = roi;
            NM.datadescriptor{varind} = dd;
        end

        function [NM,messages] = relinkSurfaceGeometrySet(NM,varind,replacements)
            dd = NM.datadescriptor{varind};
            state = NMDataIOStateTools.ioToState(dd.input_settings);
            img = state.image;
            native = NMDataIOSurfaceTools.splitSurfaceFileList(img.surfaceGeometryFile);
            inflated = NMDataIOSurfaceTools.splitSurfaceFileList(img.surfaceInflatedGeometryFile);
            for k=1:numel(replacements)
                resourceId = replacements(k).resourceId;
                index = str2double(regexp(resourceId,'\d+$','match','once'));
                if startsWith(resourceId,'surface.geometry.native.')
                    native{index} = replacements(k).resourcePath;
                else
                    inflated{index} = replacements(k).resourcePath;
                end
            end
            nativeText = strjoin(native,';');
            inflatedText = strjoin(inflated,';');
            options = struct('surfaceTemplate',img.surfaceTemplate,'surfaceHemisphere',img.surfaceHemisphere);
            replacement = NMDataIOSurfaceTools.validateSurfaceGeometryContract(nativeText,inflatedText,img.surfaceGeometryContract.vertexCount,options);
            expected = img.surfaceGeometryContract;
            if ~strcmp(replacement.nativeGeometryIdentity,expected.nativeGeometryIdentity) || ...
                    ~strcmp(replacement.topologyIdentity,expected.topologyIdentity) || ...
                    ~strcmp(replacement.vertexOrderIdentity,expected.vertexOrderIdentity) || ...
                    ~strcmp(replacement.inflatedGeometryIdentity,expected.inflatedGeometryIdentity)
                error('NMDataIOResourceRelinkTools:SurfaceGeometryIdentity','Replacement surface geometry does not match the persisted geometry/topology identity.');
            end
            state.image.surfaceGeometryFile = nativeText;
            state.image.surfaceInflatedGeometryFile = inflatedText;
            state.image.surfaceGeometryContract = replacement;
            state.image.surfaceGeometryIdentity = replacement.nativeGeometryIdentity;
            state.image.surfaceInflatedGeometryIdentity = replacement.inflatedGeometryIdentity;
            state.image.surfaceTopologyIdentity = replacement.topologyIdentity;
            state.image.surfaceVertexOrderIdentity = replacement.vertexOrderIdentity;
            state.image.surfaceInflatedValidated = replacement.inflatedValidated;
            dd = NMDataIOResourceRelinkTools.persistState(NM,varind,dd,state);
            dd.Vm(1).surfaceGeometryFile = nativeText;
            dd.Vm(1).surfaceInflatedGeometryFile = inflatedText;
            dd.Vm(1).surfaceGeometryContract = replacement;
            dd.Vm(1).surfaceGeometryIdentity = replacement.nativeGeometryIdentity;
            dd.Vm(1).surfaceInflatedGeometryIdentity = replacement.inflatedGeometryIdentity;
            dd.Vm(1).surfaceTopologyIdentity = replacement.topologyIdentity;
            dd.Vm(1).surfaceVertexOrderIdentity = replacement.vertexOrderIdentity;
            dd.Vm(1).surfaceInflatedValidated = replacement.inflatedValidated;
            NM.datadescriptor{varind} = dd;
            messages = NMDataIOMessageTools.make('ok',false,'resourceRelink.surfaceGeometry', ...
                sprintf('Relinked %d surface geometry file(s) after joint identity validation.',numel(replacements)),0,'green*');
        end

        function dd = persistState(NM,varind,dd,state)
            IO = NMDataIOStateTools.stateToIO(state,NM,varind);
            % Resource relinking updates normalized resource fields without replacing unrelated persisted import metadata.
            input = dd.input_settings;
            if strcmp(state.sourceType,'roi')
                updated = IO.input_settings;
                names = fieldnames(updated);
                for k = 1:numel(names), input.(names{k}) = updated.(names{k}); end
            end
            dd.input_settings = NMDataIOImportTools.enrichInputSettingsFromIO(input, IO);
        end

        function resources = addOne(resources,id,role,category,path,relinkable,validator)
            if isempty(path), return; end
            r = NMDataIOResourceRelinkTools.row();
            r.id=id; r.role=role; r.category=category; r.path=path;
            r.basename=NMDataIOResourceRelinkTools.basename(path); r.relinkable=relinkable; r.validator=validator;
            resources(end+1)=r; %#ok<AGROW>
        end

        function resources = addList(resources,prefix,role,category,paths,relinkable,validator)
            paths = NMDataIOStateTools.asCaseCell(paths);
            for k=1:numel(paths)
                resources = NMDataIOResourceRelinkTools.addOne(resources,sprintf('%s.%d',prefix,k),role,category,paths{k},relinkable,validator);
            end
        end

        function r = row()
            r = struct('id','','role','','category','','path','','basename','','status','', ...
                'exists',false,'relinkable',false,'validator','');
        end

        function path = filePart(path)
            path = regexprep(path,',\d+$','');
        end

        function b = basename(path)
            path = NMDataIOResourceRelinkTools.filePart(path);
            [~,name,ext] = fileparts(path);
            if strcmpi(ext,'.gz'), [~,name2,ext2]=fileparts(name); b=[name2 ext2 ext]; else, b=[name ext]; end
        end
    end
end

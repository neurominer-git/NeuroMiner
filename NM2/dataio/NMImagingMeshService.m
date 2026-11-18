classdef NMImagingMeshService
% NMImagingMeshService
% -------------------------------------------------------------------------
% Deterministic world-millimetre anatomy-mesh preparation for the Results
% Viewer imaging stack. This service does not project feature values, infer
% atlas labels, modify thresholds or choose camera state.
%
% Mesh service with mask-first lazy surface preparation.
% Documentation: docs/NMImaging3DMeshContract.md and
% docs/NMImagingLazySurfaceAssetsC18g5R3B.md
% -------------------------------------------------------------------------

    methods (Static)
        function [foregroundMask, provenance] = prepareAnatomyMask(structuralData, spatialReference, options)
            % prepareAnatomyMask  Prepare the deterministic anatomy support without extracting a mesh.
            if nargin < 3 || isempty(options), options = struct(); end
            data = double(structuralData);
            if ndims(data) ~= 3 || any(size(data) < 2)
                error('NMImagingMeshService:InvalidStructuralVolume', ...
                    'Structural data must be a nondegenerate three-dimensional array.');
            end
            NMImagingSpatialReference.validateReference(spatialReference);
            expectedDimensions = double(spatialReference.dimensions(:)');
            if ~isequal(double(size(data)), expectedDimensions)
                error('NMImagingMeshService:DimensionMismatch', ...
                    'Structural dimensions %s do not match spatial-reference dimensions %s.', ...
                    mat2str(size(data)),mat2str(expectedDimensions));
            end
            surfaceDepthMm = NMImagingMeshService.numericField(options,'surfaceDepthMm',0);
            if ~isfinite(surfaceDepthMm) || surfaceDepthMm < 0 || surfaceDepthMm > 12
                error('NMImagingMeshService:InvalidSurfaceDepth', ...
                    'Surface depth must be finite and within [0, 12] mm.');
            end
            [baseMask,maskAudit] = NMImagingMeshService.structuralForegroundMask(data);
            [mask,depthAudit] = NMImagingMeshService.applySurfaceDepth( ...
                baseMask,spatialReference,surfaceDepthMm);
            foregroundMask = logical(mask);
            provenance = struct( ...
                'maskPolicy','boundary_difference_largest_component_exterior_fill_physical_inset_v1', ...
                'surfaceDepthMm',surfaceDepthMm, ...
                'surfaceDepthApplied',surfaceDepthMm > 0, ...
                'morphologyApplied',surfaceDepthMm > 0, ...
                'topologyCleanupApplied',true, ...
                'maskAudit',maskAudit, ...
                'surfaceDepthAudit',depthAudit);
        end

        function mesh = prepareAnatomyMesh(foregroundMask, spatialReference, options, maskProvenance)
            % prepareAnatomyMesh  Extract one clean anatomy envelope from the prepared support mask.
            mask = logical(foregroundMask);
            NMImagingSpatialReference.validateReference(spatialReference);
            expectedDimensions = double(spatialReference.dimensions(:)');
            if ndims(mask) ~= 3 || ~isequal(double(size(mask)), expectedDimensions)
                error('NMImagingMeshService:DimensionMismatch', ...
                    'Foreground-mask dimensions %s do not match spatial-reference dimensions %s.', ...
                    mat2str(size(mask)),mat2str(expectedDimensions));
            end
            quality = NMImagingMeshService.normalizeQuality( ...
                NMImagingMeshService.textField(options,'quality','balanced'));
            surfaceDepthMm = maskProvenance.surfaceDepthMm;
            [surfaceField,smoothingAudit] = NMImagingMeshService.surfaceField( ...
                mask,quality,surfaceDepthMm);
            fv = isosurface(surfaceField,0.5);
            if isempty(fv.faces) || isempty(fv.vertices)
                error('NMImagingMeshService:EmptySurface', ...
                    'The deterministic structural foreground mask produced no anatomy surface.');
            end

            sourceFaceCount = size(fv.faces,1);
            targetFaceCount = NMImagingMeshService.targetFaceCount(quality);
            if sourceFaceCount > targetFaceCount
                fv = reducepatch(fv,targetFaceCount);
            end

            % MATLAB isosurface vertices use [column row slice]. Convert to
            % direct one-based SPM [I J K] before applying the affine.
            voxelIJK = [double(fv.vertices(:,2)) double(fv.vertices(:,1)) double(fv.vertices(:,3))];
            verticesWorldMm = NMImagingSpatialReference.voxelToWorld(spatialReference,voxelIJK);
            faces = double(fv.faces);
            [faces,orientationAudit] = NMImagingMeshService.orientFacesOutward(verticesWorldMm,faces);
            faces = uint32(faces);
            normalsWorld = NMImagingMeshService.vertexNormals(verticesWorldMm,faces);
            bounds = NMImagingMeshService.worldBounds(verticesWorldMm);

            mesh = struct( ...
                'schema','NMImagingWorldMesh', ...
                'schemaVersion',1, ...
                'contractVersion','C18d2.3', ...
                'coordinateSpace','world_mm', ...
                'indexBase',0, ...
                'quality',quality, ...
                'vertices',single(verticesWorldMm), ...
                'normals',single(normalsWorld), ...
                'indices',uint32(reshape(double(faces).',[],1)-1), ...
                'vertexCount',size(verticesWorldMm,1), ...
                'faceCount',size(faces,1), ...
                'boundsWorldMm',bounds, ...
                'sourceGridId',char(string(spatialReference.gridId)), ...
                'provenance',struct( ...
                    'meshRole','anatomy_surface', ...
                    'surfaceMethod','isosurface_clean_physical_inset_0_5', ...
                    'maskPolicy',maskProvenance.maskPolicy, ...
                    'surfaceDepthMm',surfaceDepthMm, ...
                    'surfaceDepthApplied',maskProvenance.surfaceDepthApplied, ...
                    'morphologyApplied',maskProvenance.morphologyApplied, ...
                    'topologyCleanupApplied',maskProvenance.topologyCleanupApplied, ...
                    'surfaceSmoothingApplied',smoothingAudit.applied, ...
                    'surfaceSmoothingSigmaVox',smoothingAudit.sigmaVox, ...
                    'sourceFaceCount',sourceFaceCount, ...
                    'targetFaceCount',targetFaceCount, ...
                    'maskAudit',maskProvenance.maskAudit, ...
                    'surfaceDepthAudit',maskProvenance.surfaceDepthAudit, ...
                    'orientationAudit',orientationAudit));
            NMImagingMeshService.validateMesh(mesh);
        end

        function validateMesh(mesh)
            required = {'vertices','normals','indices','vertexCount','faceCount','boundsWorldMm','coordinateSpace'};
            for ii=1:numel(required)
                if ~isstruct(mesh) || ~isfield(mesh,required{ii})
                    error('NMImagingMeshService:InvalidMesh','Mesh is missing field %s.',required{ii});
                end
            end
            if ~strcmp(mesh.coordinateSpace,'world_mm')
                error('NMImagingMeshService:InvalidCoordinateSpace','Imaging viewer meshes must use world millimetres.');
            end
            if size(mesh.vertices,2)~=3 || size(mesh.normals,2)~=3 || size(mesh.normals,1)~=size(mesh.vertices,1)
                error('NMImagingMeshService:InvalidGeometry','Mesh vertices and normals must be matching N-by-3 arrays.');
            end
            if mod(numel(mesh.indices),3)~=0 || any(double(mesh.indices(:))<0) || ...
                    any(double(mesh.indices(:))>=size(mesh.vertices,1))
                error('NMImagingMeshService:InvalidIndices','Mesh indices must be zero-based triangles within the vertex array.');
            end
            if any(~isfinite(double(mesh.vertices(:)))) || any(~isfinite(double(mesh.normals(:))))
                error('NMImagingMeshService:NonfiniteGeometry','Mesh geometry contains nonfinite values.');
            end
        end
    end

    methods (Static, Access=private)
        function [mask,audit] = structuralForegroundMask(data)
            finiteMask = isfinite(data);
            if nnz(finiteMask) < 8
                error('NMImagingMeshService:InsufficientStructuralData','Structural data contain too few finite voxels.');
            end
            boundary = [reshape(data(1,:,:),[],1);reshape(data(end,:,:),[],1); ...
                reshape(data(:,1,:),[],1);reshape(data(:,end,:),[],1); ...
                reshape(data(:,:,1),[],1);reshape(data(:,:,end),[],1)];
            boundary = boundary(isfinite(boundary));
            if isempty(boundary)
                error('NMImagingMeshService:MissingBoundaryData','Structural boundary contains no finite values.');
            end
            background = median(boundary);
            difference = abs(data-background);
            positiveDifference = difference(finiteMask & difference>0);
            if isempty(positiveDifference)
                error('NMImagingMeshService:ConstantStructuralVolume','Structural volume is constant and cannot define an anatomy envelope.');
            end
            contrast = prctile(positiveDifference,99);
            numericalFloor = max(1, max(abs(data(finiteMask)))) * 1e-7;
            threshold = max(numericalFloor,0.02*contrast);
            rawMask = finiteMask & difference >= threshold;
            rawOccupancy = nnz(rawMask)/numel(rawMask);
            if rawOccupancy < 0.001 || rawOccupancy > 0.90
                error('NMImagingMeshService:ImplausibleForegroundMask', ...
                    'Deterministic structural foreground occupancy %.4f is outside [0.001, 0.90].',rawOccupancy);
            end

            [largestMask,largestCount,componentCount] = NMImagingMeshService.largestComponent6(rawMask);
            if largestCount < 8
                error('NMImagingMeshService:MissingPrimaryComponent', ...
                    'Structural foreground contains no nondegenerate primary component.');
            end
            mask = NMImagingMeshService.fillEnclosedBackground(largestMask);
            finalOccupancy = nnz(mask)/numel(mask);
            if finalOccupancy < 0.001 || finalOccupancy > 0.90
                error('NMImagingMeshService:ImplausibleCleanMask', ...
                    'Cleaned anatomy-envelope occupancy %.4f is outside [0.001, 0.90].',finalOccupancy);
            end
            audit = struct('backgroundEstimate',background,'contrastP99',contrast, ...
                'differenceThreshold',threshold,'rawForegroundVoxelCount',nnz(rawMask), ...
                'rawForegroundFraction',rawOccupancy,'componentCount',componentCount, ...
                'largestComponentVoxelCount',largestCount, ...
                'filledForegroundVoxelCount',nnz(mask), ...
                'filledForegroundFraction',finalOccupancy, ...
                'boundarySampleCount',numel(boundary));
        end

        function [field,audit] = surfaceField(mask,quality,surfaceDepthMm)
            switch quality
                case 'draft', sigma = 0.90;
                case 'balanced', sigma = 0.75;
                case 'high', sigma = 0.60;
                otherwise, sigma = 0.75;
            end
            % Deeper presentation surfaces should retain more local relief.
            % This changes only the rendered anatomy mesh, never source data.
            sigma = max(0.35,sigma/(1 + 0.08*double(surfaceDepthMm)));
            window = max(3,2*ceil(2*sigma)+1);
            if mod(window,2)==0, window=window+1; end
            field = smooth3(single(mask),'gaussian',[window window window],sigma);
            field = min(max(field,0),1);
            audit = struct('applied',true,'sigmaVox',sigma, ...
                'surfaceDepthMm',double(surfaceDepthMm), ...
                'windowVox',[window window window]);
        end

        function [mask,audit] = applySurfaceDepth(baseMask,spatialReference,surfaceDepthMm)
            baseMask = logical(baseMask);
            spacingMm = NMImagingMeshService.voxelSpacingMm(spatialReference);
            if surfaceDepthMm <= 0
                mask = baseMask;
                audit = struct('method','none','surfaceDepthMm',0, ...
                    'voxelSpacingMm',spacingMm, ...
                    'baseVoxelCount',nnz(baseMask), ...
                    'insetVoxelCount',nnz(baseMask), ...
                    'componentCountAfterInset',1);
                return;
            end
            distanceSquared = NMImagingMeshService.distanceToBackgroundSquared( ...
                baseMask,spacingMm);
            candidate = baseMask & distanceSquared > surfaceDepthMm.^2;
            [mask,count,nComponents] = NMImagingMeshService.largestComponent6(candidate);
            if count < 8
                error('NMImagingMeshService:SurfaceDepthRemovedAnatomy', ...
                    ['Surface depth %.3g mm removes the primary anatomy component. ' ...
                     'Choose a smaller value.'],surfaceDepthMm);
            end
            fraction = count / max(1,nnz(baseMask));
            if fraction < 0.01
                error('NMImagingMeshService:ImplausibleSurfaceDepth', ...
                    ['Surface depth %.3g mm retains only %.4f of the base anatomy. ' ...
                     'Choose a smaller value.'],surfaceDepthMm,fraction);
            end
            audit = struct('method','anisotropic_squared_euclidean_distance_transform_v1', ...
                'surfaceDepthMm',surfaceDepthMm, ...
                'voxelSpacingMm',spacingMm, ...
                'baseVoxelCount',nnz(baseMask), ...
                'candidateVoxelCount',nnz(candidate), ...
                'insetVoxelCount',count, ...
                'retainedFraction',fraction, ...
                'componentCountAfterInset',nComponents);
        end

        function spacing = voxelSpacingMm(spatialReference)
            affine = double(spatialReference.affineVoxel1ToWorld);
            spacing = sqrt(sum(affine(1:3,1:3).^2,1));
            if any(~isfinite(spacing)) || any(spacing <= 0)
                error('NMImagingMeshService:InvalidVoxelSpacing', ...
                    'Spatial reference contains invalid voxel spacing.');
            end
        end

        function distanceSquared = distanceToBackgroundSquared(mask,spacingMm)
            % Exact separable squared Euclidean distance transform with
            % anisotropic physical spacing. A one-voxel false border makes
            % the outside of the finite display grid explicit.
            padded = false(size(mask)+2);
            padded(2:end-1,2:end-1,2:end-1) = logical(mask);
            distanceSquared = inf(size(padded));
            distanceSquared(~padded) = 0;
            for axisIndex = 1:3
                distanceSquared = NMImagingMeshService.distanceTransformAxis( ...
                    distanceSquared,axisIndex,spacingMm(axisIndex));
            end
            distanceSquared = distanceSquared(2:end-1,2:end-1,2:end-1);
        end

        function transformed = distanceTransformAxis(values,axisIndex,spacingMm)
            order = [axisIndex setdiff(1:3,axisIndex,'stable')];
            permuted = permute(values,order);
            originalSize = size(permuted);
            lines = reshape(permuted,originalSize(1),[]);
            transformedLines = zeros(size(lines));
            for lineIndex = 1:size(lines,2)
                transformedLines(:,lineIndex) = ...
                    NMImagingMeshService.distanceTransformLine(lines(:,lineIndex),spacingMm);
            end
            transformed = ipermute(reshape(transformedLines,originalSize),order);
        end

        function output = distanceTransformLine(input,spacingMm)
            input = double(input(:));
            n = numel(input);
            sites = find(isfinite(input));
            output = inf(n,1);
            if isempty(sites), return; end
            a = double(spacingMm).^2;
            v = zeros(numel(sites),1);
            z = zeros(numel(sites)+1,1);
            k = 1;
            v(1) = sites(1);
            z(1) = -Inf;
            z(2) = Inf;
            for siteIndex = 2:numel(sites)
                q = sites(siteIndex);
                s = NMImagingMeshService.parabolaIntersection(input,q,v(k),a);
                while k > 1 && s <= z(k)
                    k = k - 1;
                    s = NMImagingMeshService.parabolaIntersection(input,q,v(k),a);
                end
                k = k + 1;
                v(k) = q;
                z(k) = s;
                z(k+1) = Inf;
            end
            envelopeCount = k;
            k = 1;
            for q = 1:n
                while k < envelopeCount && z(k+1) < q
                    k = k + 1;
                end
                delta = q-v(k);
                output(q) = input(v(k)) + a*delta*delta;
            end
        end

        function s = parabolaIntersection(values,q,v,a)
            numerator = (values(q)+a*q*q) - (values(v)+a*v*v);
            denominator = 2*a*(q-v);
            s = numerator/denominator;
        end

        function [largest,count,nComponents] = largestComponent6(mask)
            mask = logical(mask);
            if ~any(mask(:))
                largest=false(size(mask));count=0;nComponents=0;return;
            end
            if exist('bwconncomp','file')==2
                cc=bwconncomp(mask,6);
                nComponents=cc.NumObjects;
                sizes=cellfun(@numel,cc.PixelIdxList);
                [count,idx]=max(sizes);
                largest=false(size(mask));
                if ~isempty(idx),largest(cc.PixelIdxList{idx})=true;end
                return;
            end
            [largest,count,nComponents] = NMImagingMeshService.largestComponent6Fallback(mask);
        end

        function [largest,bestCount,nComponents] = largestComponent6Fallback(mask)
            dims=size(mask);n1=dims(1);n2=dims(2);n12=n1*n2;
            remaining=mask;total=nnz(mask);queue=zeros(total,1,'uint32');
            largest=false(size(mask));bestCount=0;nComponents=0;
            while true
                seed=find(remaining,1);
                if isempty(seed),break;end
                nComponents=nComponents+1;head=1;tail=1;queue(1)=uint32(seed);remaining(seed)=false;
                while head<=tail
                    idx=double(queue(head));head=head+1;
                    i=mod(idx-1,n1)+1;q=floor((idx-1)/n1);j=mod(q,n2)+1;k=floor(q/n2)+1;
                    if i>1 && remaining(idx-1),tail=tail+1;queue(tail)=uint32(idx-1);remaining(idx-1)=false;end
                    if i<n1 && remaining(idx+1),tail=tail+1;queue(tail)=uint32(idx+1);remaining(idx+1)=false;end
                    if j>1 && remaining(idx-n1),tail=tail+1;queue(tail)=uint32(idx-n1);remaining(idx-n1)=false;end
                    if j<n2 && remaining(idx+n1),tail=tail+1;queue(tail)=uint32(idx+n1);remaining(idx+n1)=false;end
                    if k>1 && remaining(idx-n12),tail=tail+1;queue(tail)=uint32(idx-n12);remaining(idx-n12)=false;end
                    if k<dims(3) && remaining(idx+n12),tail=tail+1;queue(tail)=uint32(idx+n12);remaining(idx+n12)=false;end
                end
                if tail>bestCount
                    bestCount=tail;largest(:)=false;largest(double(queue(1:tail)))=true;
                end
            end
        end

        function filled = fillEnclosedBackground(mask)
            background=~logical(mask);dims=size(mask);n1=dims(1);n2=dims(2);n12=n1*n2;
            boundary=false(size(mask));
            boundary(1,:,:)=true;boundary(end,:,:)=true;boundary(:,1,:)=true;boundary(:,end,:)=true;boundary(:,:,1)=true;boundary(:,:,end)=true;
            seeds=find(background & boundary);
            exterior=false(size(mask));
            if isempty(seeds),filled=true(size(mask));return;end
            queue=zeros(nnz(background),1,'uint32');tail=numel(seeds);queue(1:tail)=uint32(seeds);exterior(seeds)=true;
            head=1;
            while head<=tail
                idx=double(queue(head));head=head+1;
                i=mod(idx-1,n1)+1;q=floor((idx-1)/n1);j=mod(q,n2)+1;k=floor(q/n2)+1;
                if i>1 && background(idx-1) && ~exterior(idx-1),tail=tail+1;queue(tail)=uint32(idx-1);exterior(idx-1)=true;end
                if i<n1 && background(idx+1) && ~exterior(idx+1),tail=tail+1;queue(tail)=uint32(idx+1);exterior(idx+1)=true;end
                if j>1 && background(idx-n1) && ~exterior(idx-n1),tail=tail+1;queue(tail)=uint32(idx-n1);exterior(idx-n1)=true;end
                if j<n2 && background(idx+n1) && ~exterior(idx+n1),tail=tail+1;queue(tail)=uint32(idx+n1);exterior(idx+n1)=true;end
                if k>1 && background(idx-n12) && ~exterior(idx-n12),tail=tail+1;queue(tail)=uint32(idx-n12);exterior(idx-n12)=true;end
                if k<dims(3) && background(idx+n12) && ~exterior(idx+n12),tail=tail+1;queue(tail)=uint32(idx+n12);exterior(idx+n12)=true;end
            end
            filled=~exterior;
        end

        function [faces,audit] = orientFacesOutward(vertices,faces)
            center=mean(vertices,1);
            a=vertices(faces(:,1),:);b=vertices(faces(:,2),:);c=vertices(faces(:,3),:);
            fn=cross(b-a,c-a,2);fc=(a+b+c)/3;
            score=sum(fn.*(fc-center),2);finiteScore=score(isfinite(score));
            medianScore=median(finiteScore);
            flipped=false;
            if ~isempty(medianScore) && medianScore<0
                faces=faces(:,[1 3 2]);flipped=true;medianScore=-medianScore;
            end
            audit=struct('orientationPolicy','median_face_normal_from_mesh_center', ...
                'facesFlipped',flipped,'medianOutwardScore',medianScore);
        end

        function normals = vertexNormals(vertices,faces)
            vertices = double(vertices);
            faces = double(faces);
            first = vertices(faces(:,1),:);
            second = vertices(faces(:,2),:);
            third = vertices(faces(:,3),:);
            faceNormals = cross(second-first,third-first,2);
            vertexIds = faces(:);
            normals = zeros(size(vertices));
            for axisIndex = 1:3
                repeated = repmat(faceNormals(:,axisIndex),3,1);
                normals(:,axisIndex) = accumarray( ...
                    vertexIds,repeated,[size(vertices,1) 1],@sum,0);
            end
            lengths = sqrt(sum(normals.^2,2));
            lengths(lengths == 0) = 1;
            normals = normals ./ lengths;
        end

        function bounds = worldBounds(vertices)
            lo=min(vertices,[],1);hi=max(vertices,[],1);center=(lo+hi)/2;
            radius=max(sqrt(sum((vertices-center).^2,2)));
            bounds=struct('min',double(lo),'max',double(hi),'center',double(center),'radius',double(radius));
        end

        function quality = normalizeQuality(value)
            quality=lower(strtrim(char(string(value))));
            if ~ismember(quality,{'draft','balanced','high'})
                error('NMImagingMeshService:InvalidQuality','Unsupported anatomy mesh quality "%s".',quality);
            end
        end

        function count = targetFaceCount(quality)
            switch quality
                case 'draft', count=24000;
                case 'balanced', count=70000;
                case 'high', count=140000;
                otherwise, count=70000;
            end
        end

        function value = textField(s,name,defaultValue)
            value=defaultValue;
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), value=char(string(s.(name))); end
        end

        function value = numericField(s,name,defaultValue)
            value=defaultValue;
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                candidate=double(s.(name));
                if isscalar(candidate), value=candidate; end
            end
        end
    end
end

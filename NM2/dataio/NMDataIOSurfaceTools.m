classdef NMDataIOSurfaceTools
% NMDataIOSurfaceTools
% -------------------------------------------------------------------------
% Minimal browser DataIO surface scalar reader utilities. This first surface
% stream slice supports vertexwise GIFTI and FreeSurfer MGH/MGZ scalar files.
% ROI-based surface import and browser WebGL surface viewing are handled
% in this class without routing through volumetric image preview code.
% -------------------------------------------------------------------------

    methods (Static)
        function [Y, metas, messages] = readSurfaceMatrix(files, progressTask)
            % readSurfaceMatrix  Read multiple surface scalar files into a subject-by-vertex matrix.
            %
            % Consumes files; returns Y, metas, messages.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            files = NMDataIOSurfaceTools.asCellstr(files);
            if nargin < 2 || isempty(progressTask), progressTask = NMProgressTools.emptyTaskForLocalUse(); end
            messages = NMDataIOMessageTools.emptyMessages();
            metas = repmat(NMDataIOSurfaceTools.emptyMeta(), numel(files), 1);
            Y = [];
            nVert = NaN;
            for i = 1:numel(files)
                progressTask = NMProgressTools.step(progressTask, i-1, max(numel(files),1), sprintf('Reading surface subject %g of %g.', i, max(numel(files),1)));
                try
                    [vec, meta] = NMDataIOSurfaceTools.readSurfaceScalar(files{i});
                    metas(i) = meta;
                    if i == 1
                        nVert = numel(vec);
                        Y = nan(numel(files), nVert);
                    elseif numel(vec) ~= nVert
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceFiles.vertexCount', ...
                            sprintf(['Surface vertex-space mismatch during commit: first file has %g vertices, but file %g has %g vertices (%s). ', ...
                                     'Vertexwise surface import requires a common template mesh. Native-space files must be resampled/registered outside DataIO or imported later through the ROI-based surface pathway.'], ...
                                     nVert, i, numel(vec), files{i}), 1, 'red*')]; %#ok<AGROW>
                        return;
                    end
                    Y(i,:) = double(vec(:)');
                    progressTask = NMProgressTools.step(progressTask, i, max(numel(files),1), sprintf('Read surface subject %g of %g.', i, max(numel(files),1)));
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, sprintf('surfaceFiles.read[%g]', i))]; %#ok<AGROW>
                    return;
                end
            end
        end

        function [vec, meta] = readSurfaceScalar(filename)
            % readSurfaceScalar  Read one supported surface scalar file and return its data vector plus metadata.
            %
            % Purpose:
            %   Materialize one vertexwise scalar payload from GIFTI, compressed GIFTI, MGH/MGZ,
            %   or a FreeSurfer native morphometry file.
            %
            % Authority and flow:
            %   File-format dispatch is owned here and is compound-extension aware. A .gii.gz source
            %   remains the provenance file but is resolved to a deterministic cached .gii copy before
            %   the GIFTI reader is invoked. Unsupported suffixes remain FreeSurfer morphometry
            %   candidates and are delegated to read_curv.
            %
            % Scientific/state contract:
            %   Returned values preserve the source vertex order exactly. Compression is a storage
            %   property and must not alter vertex identity or cause a GIFTI payload to enter the
            %   FreeSurfer read_curv path.
            %
            % Materialization and performance:
            %   Reads one scalar file and materializes its complete vertex vector. Compressed GIFTI
            %   sources are gunzipped once into a source-identity cache and reused on subsequent reads.
            %   This function is appropriate for explicit Probe/import/QC materialization, not for
            %   repeated interactive navigation over raw source files.
            %
            % Failure semantics:
            %   Missing files, decompression failures, unavailable format readers, non-scalar GIFTI
            %   payloads, and nonnumeric data fail explicitly.
            filename = char(string(filename));
            if isempty(filename) || exist(filename,'file') ~= 2
                error('NMDataIOSurfaceTools:MissingFile', 'Surface scalar file does not exist: %s', filename);
            end
            [formatKind, readFile] = NMDataIOSurfaceTools.resolveSurfaceStorageFile(filename);
            meta = NMDataIOSurfaceTools.emptyMeta();
            meta.file = filename;
            meta.format = formatKind;
            switch formatKind
                case 'gii'
                    data = NMDataIOSurfaceTools.readGiftiScalar(readFile);
                case {'mgh','mgz'}
                    data = NMDataIOSurfaceTools.readMghScalar(readFile);
                otherwise
                    % FreeSurfer native morphometry files commonly have no
                    % stable MATLAB extension, e.g. lh.thickness.subject,
                    % rh.area.subject, lh.sulc.subject. Treat unsupported
                    % extensions as native scalar candidates and let
                    % read_curv provide the authoritative read/error.
                    data = NMDataIOSurfaceTools.readCurvScalar(readFile);
                    meta.format = 'freesurfer_curv';
            end
            data = NMDataIOSurfaceTools.coerceNumericScalarData(data, filename, meta.format);
            vec = double(data(:));
            meta.nVertices = double(numel(vec));
            meta.dataSize = double(size(data));
            meta.nFinite = double(nnz(isfinite(vec)));
            meta.nNaN = double(nnz(isnan(vec)));
            finiteVec = vec(isfinite(vec));
            if isempty(finiteVec)
                meta.minValue = NaN;
                meta.maxValue = NaN;
            else
                meta.minValue = double(min(finiteVec));
                meta.maxValue = double(max(finiteVec));
            end
        end

        function data = readGiftiScalar(filename)
            % readGiftiScalar  Read a GIFTI scalar payload using gifti support when available.
            %
            % Filename -> data.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if exist('gifti','file') == 2 || exist('gifti','class') == 8 || ~isempty(which('gifti'))
                try
                    g = gifti(filename);
                catch ME
                    error('NMDataIOSurfaceTools:GiftiParseFailed', ...
                        ['GIFTI parsing failed for %s. If this is a FreeSurfer native morphometry file ' ...
                         'such as lh.thickness.subject, import it without selecting the GIFTI path so it can be read with read_curv. Original error: %s'], ...
                         filename, ME.message);
                end
            elseif exist('GIIread','file') == 2 || ~isempty(which('GIIread'))
                g = GIIread(filename);
            else
                error('NMDataIOSurfaceTools:MissingGiftiReader', ...
                    'GIFTI import requires SPM''s gifti interface or GIIread.m on the MATLAB path.');
            end
            % SPM's gifti implementation can behave like an old-style
            % MATLAB object. In that case isstruct/isobject guards may fail
            % even though dot-access and isfield(g,'cdata') work. Probe the
            % member directly instead of assuming a struct/class shape.
            if NMDataIOSurfaceTools.hasGiftiMember(g, 'cdata')
                try
                    data = g.cdata;
                catch ME
                    error('NMDataIOSurfaceTools:GiftiCDataAccessFailed', ...
                        'GIFTI file reports cdata but cdata could not be accessed for %s: %s', filename, ME.message);
                end
                return;
            end
            if NMDataIOSurfaceTools.hasGiftiMember(g, 'vertices') && NMDataIOSurfaceTools.hasGiftiMember(g, 'faces')
                error('NMDataIOSurfaceTools:GiftiGeometryNotScalar', ...
                    ['Selected GIFTI file is a surface geometry/mesh file, not a vertexwise scalar map: %s. ' ...
                     'It contains vertices/faces but no cdata. Use it later as a surface geometry/template for visualization, not as subject scalar data.'], filename);
            end
            error('NMDataIOSurfaceTools:MissingGiftiCData', ...
                'No cdata field/property found in GIFTI surface scalar file: %s. Select a vertexwise scalar GIFTI map.', filename);
        end

        function data = readCurvScalar(filename)
            % readCurvScalar  Read a FreeSurfer curv scalar file into a numeric vector.
            %
            % Filename -> data.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % Throws on invalid preconditions instead of returning an ambiguous partial result; diagnostics are returned as structured messages for explicit UI/API handling.
            if exist('read_curv','file') ~= 2 && isempty(which('read_curv'))
                error('NMDataIOSurfaceTools:MissingFreeSurferCurvReader', ...
                    ['FreeSurfer native surface scalar import requires read_curv.m on the MATLAB path. ' ...
                     'Supported native examples include lh.thickness.*, rh.thickness.*, lh.area.*, rh.area.*, lh.sulc.*, and lh.curv.*.']);
            end
            try
                [data, ~] = read_curv(filename);
            catch ME
                [~,~,ext0] = fileparts(filename);
                error('NMDataIOSurfaceTools:UnsupportedFormat', ...
                    ['Unsupported surface scalar file or read_curv failed for ''%s''. ' ...
                     'Supported formats are scalar .gii, .mgh/.mgz, and FreeSurfer native scalar files readable by read_curv. ' ...
                     'File extension was ''%s''. Original error: %s'], filename, ext0, ME.message);
            end
        end

        function data = readMghScalar(filename)
            % readMghScalar  Read an MGH/MGZ scalar file into a numeric vector.
            %
            % Filename -> data.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % Throws on invalid preconditions instead of returning an ambiguous partial result.
            if exist('MRIread','file') == 2 || ~isempty(which('MRIread'))
                s = MRIread(filename);
                if isstruct(s) && isfield(s,'vol')
                    data = s.vol;
                else
                    error('NMDataIOSurfaceTools:MRIreadNoVol', 'MRIread did not return a structure with field vol for %s.', filename);
                end
            elseif exist('load_mgh','file') == 2 || ~isempty(which('load_mgh'))
                data = load_mgh(filename);
            else
                error('NMDataIOSurfaceTools:MissingFreeSurferReader', ...
                    'MGH/MGZ import requires FreeSurfer MATLAB helper functions MRIread.m or load_mgh.m on the MATLAB path.');
            end
        end

        function writeSurfaceScalar(values, filename, formatKind)
            % writeSurfaceScalar  Write one vertexwise scalar vector in an explicit surface format.
            %
            % Purpose
            %   Persist one already-resolved vertex vector as GIFTI, MGH, or MGZ without
            %   reading a source scalar file or altering vertex order.
            %
            % Syntax
            %   NMDataIOSurfaceTools.writeSurfaceScalar(values,filename,formatKind)
            %
            % Inputs
            %   values     Numeric/logical vertex vector in authoritative DataIO order.
            %   filename   Explicit output path including extension.
            %   formatKind gii|mgh|mgz.
            %
            % Authority and flow
            %   The caller owns scientific payload selection. This method owns only surface
            %   scalar file-format materialization. GIFTI uses the SPM/CAT gifti writer;
            %   MGH/MGZ use FreeSurfer save_mgh directly and never call MRIread/MRIwrite.
            %
            % Scientific/state contract
            %   Vertex count and order are preserved exactly. No geometry, annotation,
            %   hemisphere, atlas, smoothing, resampling, or scalar normalization occurs.
            %
            % Materialization and performance
            %   O(N) time and one O(N) single-precision output buffer for N vertices.
            %
            % Failure semantics
            %   Invalid vectors, unsupported formats, missing format writers, and failed
            %   file creation throw explicit errors. No MAT fallback or format substitution.
            %
            % Side effects
            %   Writes exactly one requested surface scalar file.
            %
            % Consumers and dependencies
            %   NMMLIMapExportTools and future explicit DataIO surface-export consumers.
            if nargin < 3, formatKind = ''; end
            if ~(isnumeric(values) || islogical(values)) || ~isvector(values) || ~isreal(values)
                error('NMDataIOSurfaceTools:InvalidSurfaceWriteVector', ...
                    'Surface scalar export requires one real numeric/logical vector.');
            end
            filename = char(string(filename));
            if isempty(filename)
                error('NMDataIOSurfaceTools:MissingSurfaceWritePath','Surface scalar export requires an output filename.');
            end
            formatKind = lower(strtrim(char(string(formatKind))));
            if isempty(formatKind)
                [formatKind,~] = NMDataIOSurfaceTools.resolveSurfaceStorageFile(filename);
            end
            if ~any(strcmp(formatKind,{'gii','mgh','mgz'}))
                error('NMDataIOSurfaceTools:UnsupportedSurfaceWriteFormat', ...
                    'Surface scalar export supports only GIFTI, MGH, and MGZ; requested "%s".',formatKind);
            end
            parent = fileparts(filename);
            if ~isempty(parent) && exist(parent,'dir') ~= 7, mkdir(parent); end
            data = single(values(:));
            switch formatKind
                case 'gii'
                    if ~(exist('gifti','file') == 2 || exist('gifti','class') == 8 || ~isempty(which('gifti')))
                        error('NMDataIOSurfaceTools:MissingGiftiWriter', ...
                            'GIFTI export requires the SPM/CAT gifti interface on the MATLAB path.');
                    end
                    g = gifti;
                    g.cdata = data;
                    save(g,filename);
                case {'mgh','mgz'}
                    if exist('save_mgh','file') ~= 2 && isempty(which('save_mgh'))
                        error('NMDataIOSurfaceTools:MissingFreeSurferWriter', ...
                            ['MGH/MGZ export requires FreeSurfer save_mgh.m on the MATLAB path. ' ...
                             'MRIread/MRIwrite are deliberately not used by this writer.']);
                    end
                    vol = reshape(data,[numel(data) 1 1 1]);
                    save_mgh(vol,filename,eye(4));
            end
            if exist(filename,'file') ~= 2
                error('NMDataIOSurfaceTools:SurfaceWriteFailed', ...
                    'Surface scalar writer returned without creating the requested file: %s',filename);
            end
        end

        function formats = surfaceFormats(files)
            % surfaceFormats  Summarize the surface scalar file formats present in a file list.
            %
            % Files -> formats.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            files = NMDataIOSurfaceTools.asCellstr(files);
            formats = cell(numel(files),1);
            for i = 1:numel(files)
                if ~isempty(regexpi(files{i}, '\.gii\.gz$', 'once'))
                    formats{i} = 'gii';
                else
                    [~,~,ext] = fileparts(files{i});
                    formats{i} = lower(strrep(ext, '.', ''));
                end
            end
        end

        function out = prepareSurfaceViewerMesh(surfaceFile, geometryFile, opts)
            % prepareSurfaceViewerMesh  Prepare mesh geometry and scalar payload references for the surface viewer.
            %
            % Consumes surfaceFile, geometryFile, opts; returns out.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % Performs explicit file-system IO; throws on invalid preconditions instead of returning an ambiguous partial result; diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            %
            % opts.groupQCMode: configures optional group qcmode behavior for this call.
            % opts.rowIndex: configures optional row index behavior for this call.
            % opts.tmpDir: sets the temporary directory for generated scripts or runtime sidecar files.
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = struct('ok',false,'message','Surface viewer mesh not prepared.', ...
                'viewerMode','surface_webgl','verticesUrl','','facesUrl','','valuesUrl','', ...
                'dataType','float32','faceIndexDataType','uint32','nVertices',NaN,'nFaces',NaN, ...
                'valueWindow',[],'scalarFile','','geometryFile','','token','','warning','');
            surfaceFile = NMDataIOSurfaceTools.asChar(surfaceFile);
            geometryFile = NMDataIOSurfaceTools.asChar(geometryFile);
            tmpDir = NMDataIOSurfaceTools.asChar(NMDataIOSurfaceTools.fieldOr(opts, 'tmpDir', ''));
            rowIndex = double(NMDataIOSurfaceTools.fieldOr(opts, 'rowIndex', NaN));
            groupQCMode = logical(double(NMDataIOSurfaceTools.fieldOr(opts, 'groupQCMode', 0)) ~= 0);
            try
                if groupQCMode
                    if isempty(geometryFile) || exist(geometryFile,'file') ~= 2
                        error('NMDataIOSurfaceTools:MissingSurfaceGeometry', 'Group-level surface QC viewing requires a valid Surface display mesh file.');
                    end
                    geomFile = geometryFile;
                    [vertices, faces, geomMeta] = NMDataIOSurfaceTools.readSurfaceGeometry(geomFile);
                    values = single(zeros(size(vertices,1), 1));
                    scalarMeta = struct('format','group_qc_placeholder');
                    lo = 0;
                    hi = 1;
                else
                    if isempty(surfaceFile) || exist(surfaceFile,'file') ~= 2
                        error('NMDataIOSurfaceTools:MissingSurfaceScalar', 'Surface scalar file does not exist: %s', surfaceFile);
                    end
                    [values, scalarMeta] = NMDataIOSurfaceTools.readSurfaceScalar(surfaceFile);
                    values = single(values(:));
                    geomFile = NMDataIOSurfaceTools.surfaceViewerGeometryFile(surfaceFile, geometryFile, rowIndex);
                    [vertices, faces, geomMeta] = NMDataIOSurfaceTools.readSurfaceGeometry(geomFile);
                    if size(vertices,1) ~= numel(values)
                        error('NMDataIOSurfaceTools:SurfaceViewerVertexMismatch', ...
                            ['Surface viewer vertex-count mismatch: scalar file has %g values (%s), but display mesh has %g vertices (%s). ', ...
                             'Use a subject/template mesh that matches the selected surface scalar vector.'], ...
                             numel(values), surfaceFile, size(vertices,1), geomFile);
                    end
                    finiteVals = double(values(isfinite(values)));
                    if isempty(finiteVals)
                        error('NMDataIOSurfaceTools:SurfaceViewerNoFiniteValues', 'Selected surface scalar file contains no finite values: %s', surfaceFile);
                    end
                    lo = prctile(finiteVals(:), 1);
                    hi = prctile(finiteVals(:), 99);
                    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
                        lo = min(finiteVals); hi = max(finiteVals);
                    end
                    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo, hi = lo + eps; end
                end

                package = NMDataIOSurfaceTools.prepareSurfaceViewerArrays(vertices, faces, values, tmpDir, struct('valueWindow',[lo hi]));
                if ~package.ok
                    out.message = package.message;
                    return;
                end
                out = package;
                out.scalarFile = surfaceFile;
                out.geometryFile = geomFile;
                out.scalarFormat = scalarMeta.format;
                out.geometryFormat = geomMeta.format;
                out.groupQCMode = groupQCMode;
                if groupQCMode
                    out.message = sprintf('Prepared WebGL group-level surface QC mesh (%g vertices, %g triangles; geometry format=%s).', ...
                        out.nVertices, out.nFaces, geomMeta.format);
                else
                    out.message = sprintf('Prepared WebGL surface viewer mesh (%g vertices, %g triangles; scalar format=%s; geometry format=%s).', ...
                        out.nVertices, out.nFaces, scalarMeta.format, geomMeta.format);
                end
            catch ME
                out.ok = false;
                out.message = sprintf('%s: %s', ME.identifier, ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
            end
        end

        function out = prepareSurfaceViewerArrays(vertices, faces, values, tmpDir, opts)
            % prepareSurfaceViewerArrays  Package already-resident surface arrays for the existing WebGL viewer.
            %
            % Purpose:
            %   Provide the single browser-transport authority for surface geometry plus one scalar
            %   value per vertex. It is shared by ordinary surface viewing and ROI parcel expansion.
            %
            % Inputs/outputs:
            %   vertices/faces are the validated zero-based mesh arrays; values contains one value per
            %   vertex; tmpDir is the browser-session directory. Returns the established surface_webgl
            %   URL/dimension contract consumed by DataIO and Results Viewer renderers.
            %
            % Authority and invariants:
            %   This function packages arrays only. It does not infer hemisphere, annotation identity,
            %   ROI membership, or scientific semantics. Callers must establish those facts first.
            %
            % Materialization and performance:
            %   Interactive-safe for resident arrays. Performs O(V+F) binary serialization and writes
            %   ephemeral browser assets; it performs no source-file reads or annotation parsing.
            %
            % Failure semantics / side effects:
            %   Shape or vertex-count mismatches fail explicitly. Writes only temporary transport files.
            if nargin < 5 || isempty(opts), opts = struct(); end
            out = struct('ok',false,'message','Surface viewer arrays were not packaged.', ...
                'viewerMode','surface_webgl','verticesUrl','','facesUrl','','valuesUrl','', ...
                'dataType','float32','faceIndexDataType','uint32','nVertices',NaN,'nFaces',NaN, ...
                'valueWindow',[],'token','','warning','');
            try
                vertices = single(vertices);
                faces = uint32(faces);
                values = single(values(:));
                if ndims(vertices) ~= 2 || size(vertices,2) ~= 3 || isempty(vertices)
                    error('NMDataIOSurfaceTools:SurfaceViewerVertices','Surface viewer vertices must be a non-empty N-by-3 array.');
                end
                if ndims(faces) ~= 2 || size(faces,2) ~= 3 || isempty(faces)
                    error('NMDataIOSurfaceTools:SurfaceViewerFaces','Surface viewer faces must be a non-empty M-by-3 zero-based array.');
                end
                if numel(values) ~= size(vertices,1)
                    error('NMDataIOSurfaceTools:SurfaceViewerValueCount','Surface viewer values=%g but vertices=%g.',numel(values),size(vertices,1));
                end
                if any(double(faces(:)) >= size(vertices,1))
                    error('NMDataIOSurfaceTools:SurfaceViewerFaceRange','The selected surface mesh contains face indices outside the available vertex range.');
                end
                finiteVals = double(values(isfinite(values)));
                if isempty(finiteVals)
                    error('NMDataIOSurfaceTools:SurfaceViewerNoFiniteValues','Surface viewer values contain no finite entries.');
                end
                window = double(NMDataIOSurfaceTools.fieldOr(opts,'valueWindow',[]));
                if numel(window) ~= 2 || any(~isfinite(window)) || window(2) <= window(1)
                    lo = prctile(finiteVals(:),1); hi = prctile(finiteVals(:),99);
                    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo, lo = min(finiteVals); hi = max(finiteVals); end
                    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo, hi = lo + eps; end
                    window = [lo hi];
                end
                [assetDir, assetUrlBase, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(NMDataIOSurfaceTools.asChar(tmpDir));
                if ~isempty(assetErr), out.message = assetErr; return; end
                if exist(assetDir,'dir') ~= 7
                    [ok,msg] = mkdir(assetDir);
                    if ~ok, out.message = sprintf('Could not create the temporary folder needed for surface viewing (%s): %s',assetDir,msg); return; end
                end
                token = ['surf_' regexprep(NMDataIOImagePreviewTools.safeToken(), '^vol_', '')];
                pkgDir = fullfile(assetDir,token);
                [ok,msg] = mkdir(pkgDir);
                if ~ok, out.message = sprintf('Could not create surface viewer package directory %s: %s',pkgDir,msg); return; end
                NMDataIOImagePreviewTools.writeBinaryFile(fullfile(pkgDir,'vertices_f32.bin'),single(reshape(vertices',[],1)),'single');
                NMDataIOImagePreviewTools.writeBinaryFile(fullfile(pkgDir,'faces_u32.bin'),uint32(reshape(faces',[],1)),'uint32');
                NMDataIOImagePreviewTools.writeBinaryFile(fullfile(pkgDir,'values_f32.bin'),values,'single');
                out.ok = true; out.token = token;
                out.verticesUrl = [assetUrlBase '/' token '/vertices_f32.bin'];
                out.facesUrl = [assetUrlBase '/' token '/faces_u32.bin'];
                out.valuesUrl = [assetUrlBase '/' token '/values_f32.bin'];
                out.nVertices = double(size(vertices,1)); out.nFaces = double(size(faces,1));
                out.valueWindow = double(window);
                out.message = sprintf('Prepared WebGL surface arrays (%g vertices, %g triangles).',out.nVertices,out.nFaces);
            catch ME
                out.ok = false; out.message = sprintf('%s: %s',ME.identifier,ME.message);
                out.identifier = ME.identifier; out.error = ME.message;
            end
        end

        function [vertices, faces, meta] = readSurfaceGeometry(filename)
            % readSurfaceGeometry  Read supported surface geometry files into vertices/faces for viewer rendering.
            %
            % Purpose:
            %   Materialize a GIFTI/compressed-GIFTI or FreeSurfer display mesh without changing
            %   vertex order or inferring parcel identity from geometry.
            %
            % Authority and flow:
            %   Uses the same compound-extension storage resolver as scalar import. A .gii.gz mesh is
            %   decompressed into the deterministic GIFTI cache before the existing GIFTI geometry
            %   reader is called; other files remain FreeSurfer geometry candidates.
            %
            % Scientific/state contract:
            %   Geometry supplies coordinates/faces only. It never defines ROI identity. Returned face
            %   indices are normalized to the viewer's zero-based uint32 convention.
            %
            % Materialization and performance:
            %   Reads and materializes the complete mesh. Compressed GIFTI is decompressed once per
            %   source identity and then reused. This is an explicit materialization operation, not a
            %   per-frame or interactive-navigation operation.
            %
            % Failure semantics:
            %   Missing files, decompression/parse failures, unavailable readers, invalid vertices, or
            %   invalid face indices fail explicitly.
            filename = char(string(filename));
            if isempty(filename) || exist(filename,'file') ~= 2
                error('NMDataIOSurfaceTools:MissingSurfaceGeometry', 'Surface display mesh file does not exist: %s', filename);
            end
            [formatKind, readFile] = NMDataIOSurfaceTools.resolveSurfaceStorageFile(filename);
            meta = struct('file',filename,'format','','nVertices',NaN,'nFaces',NaN);
            switch formatKind
                case 'gii'
                    [vertices, faces] = NMDataIOSurfaceTools.readGiftiGeometry(readFile);
                    meta.format = 'gii_geometry';
                otherwise
                    [vertices, faces] = NMDataIOSurfaceTools.readFreeSurferGeometry(readFile);
                    meta.format = 'freesurfer_surface';
            end
            [vertices, faces] = NMDataIOSurfaceTools.coerceSurfaceGeometry(vertices, faces, filename);
            meta.nVertices = double(size(vertices,1));
            meta.nFaces = double(size(faces,1));
        end

        function [Y, roiInfo, metas, messages] = readNativeSurfaceROIMatrix(spec)
            % readNativeSurfaceROIMatrix  Collapse native surface scalar/annotation pairs into canonical ROI columns.
            %
            % Purpose:
            %   Aggregate each subject's surface scalar values within annotation parcels while retaining
            %   explicit hemisphere + source annotation-ID provenance for downstream ROI consumers.
            %
            % Authority and flow:
            %   scalarFiles{i} + annotFiles{i} -> exact annotation-ID collapse. The first annotation in
            %   each used hemisphere defines the canonical ROI identity set. Optional lh/rhGeometryFile
            %   supplies display geometry only and is validated against that canonical annotation vertex order.
            %
            % Scientific/state contract:
            %   ROI identity is never inferred from mesh geometry or anatomical names. Bilateral output
            %   concatenates the canonical LH and RH ROI sets in deterministic hemisphere/annotation order.
            %
            % Materialization and performance:
            %   Reads subject scalar and annotation files during explicit import/QC materialization. If a
            %   QC reference mesh is supplied, it is read once for vertex-count validation. This function is
            %   not permitted on interactive viewer navigation or teardown paths.
            %
            % Failure semantics:
            %   Scalar/annotation list mismatches, subject-order mismatches, unsupported ROI sets, or a
            %   reference mesh whose vertex count differs from the canonical annotation fail explicitly.
            %
            % spec.annotFiles: supplies the annot files value in the public API/import specification.
            % spec.collapseMethod: supplies the collapse method value in the public API/import specification.
            % spec.hemisphereMode: supplies the hemisphere mode value in the public API/import specification.
            % spec.lhAnnotFiles: supplies the lh annot files value in the public API/import specification.
            % spec.lhScalarFiles: supplies the lh scalar files value in the public API/import specification.
            % spec.rhAnnotFiles: supplies the rh annot files value in the public API/import specification.
            % spec.rhScalarFiles: supplies the rh scalar files value in the public API/import specification.
            % spec.scalarFiles: supplies the scalar files value in the public API/import specification.
            if nargin < 1 || ~isstruct(spec), spec = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            method = lower(NMDataIOSurfaceTools.fieldOr(spec, 'collapseMethod', 'mean'));
            if ~ismember(method, {'mean','median'})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.method', ...
                    sprintf('Unsupported native surface ROI collapse method: %s.', method), 1, 'red*')];
                Y = []; roiInfo = struct(); metas = struct([]); return;
            end
            hemiMode = lower(NMDataIOSurfaceTools.fieldOr(spec, 'hemisphereMode', 'auto'));
            lhScalars = NMDataIOSurfaceTools.asCellstr(NMDataIOSurfaceTools.fieldOr(spec, 'lhScalarFiles', {}));
            lhAnnots  = NMDataIOSurfaceTools.asCellstr(NMDataIOSurfaceTools.fieldOr(spec, 'lhAnnotFiles', {}));
            rhScalars = NMDataIOSurfaceTools.asCellstr(NMDataIOSurfaceTools.fieldOr(spec, 'rhScalarFiles', {}));
            rhAnnots  = NMDataIOSurfaceTools.asCellstr(NMDataIOSurfaceTools.fieldOr(spec, 'rhAnnotFiles', {}));
            lhGeometry = NMDataIOSurfaceTools.asChar(NMDataIOSurfaceTools.fieldOr(spec, 'lhGeometryFile', ''));
            rhGeometry = NMDataIOSurfaceTools.asChar(NMDataIOSurfaceTools.fieldOr(spec, 'rhGeometryFile', ''));
            scalarFiles = NMDataIOSurfaceTools.asCellstr(NMDataIOSurfaceTools.fieldOr(spec, 'scalarFiles', {}));
            annotFiles  = NMDataIOSurfaceTools.asCellstr(NMDataIOSurfaceTools.fieldOr(spec, 'annotFiles', {}));
            if isempty(lhScalars) && isempty(rhScalars) && ~isempty(scalarFiles)
                hemi = NMDataIOSurfaceTools.inferHemisphereList(scalarFiles, '');
                if strcmp(hemi,'right')
                    rhScalars = scalarFiles; rhAnnots = annotFiles;
                else
                    lhScalars = scalarFiles; lhAnnots = annotFiles;
                end
            end
            useLH = ~isempty(lhScalars) || ~isempty(lhAnnots);
            useRH = ~isempty(rhScalars) || ~isempty(rhAnnots);
            if strcmp(hemiMode,'left'), useRH = false; end
            if strcmp(hemiMode,'right'), useLH = false; end
            if ~useLH && ~useRH
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.files', ...
                    'No native surface ROI scalar/annotation files were supplied.', 1, 'red*')];
                Y = []; roiInfo = struct(); metas = struct([]); return;
            end
            parts = {};
            if useLH
                [Ylh, ilh, mlh, msg] = NMDataIOSurfaceTools.readOneHemisphereROIMatrix(lhScalars, lhAnnots, 'lh', method);
                messages = [messages; msg];
                if NMDataIOMessageTools.hasFatal(messages), Y = []; roiInfo = struct(); metas = mlh; return; end
                parts{end+1} = struct('Y',Ylh,'info',ilh,'meta',mlh,'hemi','lh'); %#ok<AGROW>
            end
            if useRH
                [Yrh, irh, mrh, msg] = NMDataIOSurfaceTools.readOneHemisphereROIMatrix(rhScalars, rhAnnots, 'rh', method);
                messages = [messages; msg];
                if NMDataIOMessageTools.hasFatal(messages), Y = []; roiInfo = struct(); metas = mrh; return; end
                parts{end+1} = struct('Y',Yrh,'info',irh,'meta',mrh,'hemi','rh'); %#ok<AGROW>
            end
            displayGeometry = struct('lh',lhGeometry,'rh',rhGeometry);
            for pi=1:numel(parts)
                token=parts{pi}.hemi; geomFile=displayGeometry.(token);
                parts{pi}.geometryFile='';
                if isempty(geomFile), continue; end
                try
                    [vertices,~,~]=NMDataIOSurfaceTools.readSurfaceGeometry(geomFile);
                catch ME
                    messages=[messages;NMDataIOMessageTools.fromException(ME,['surfaceRoi.' token '.geometry'])];
                    Y=[]; roiInfo=struct(); metas=parts{pi}.meta; return;
                end
                nLabels=numel(parts{pi}.info.firstLabelVector);
                if size(vertices,1)~=nLabels
                    messages=[messages;NMDataIOMessageTools.make('danger',true,['surfaceRoi.' token '.geometryVertexCount'], ...
                        sprintf('%s surface ROI display mesh has %g vertices, but the selected annotation has %g vertex labels. Select the mesh that matches this annotation''s vertex order.',upper(token),size(vertices,1),nLabels),1,'red*')];
                    Y=[]; roiInfo=struct(); metas=parts{pi}.meta; return;
                end
                parts{pi}.geometryFile=geomFile;
            end
            if numel(parts) == 2
                n1 = size(parts{1}.Y,1); n2 = size(parts{2}.Y,1);
                if n1 ~= n2
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.bilateral.nSubjects', ...
                        sprintf('Bilateral native surface ROI import requires equal subject counts: LH=%g, RH=%g.', n1, n2), 1, 'red*')];
                    Y = []; roiInfo = struct(); metas = [parts{1}.meta; parts{2}.meta]; return;
                end
                lk = NMDataIOSurfaceTools.subjectKeysFromFiles(parts{1}.info.scalarFiles);
                rk = NMDataIOSurfaceTools.subjectKeysFromFiles(parts{2}.info.scalarFiles);
                bad = find(~strcmp(lk(:), rk(:)) & ~cellfun(@isempty, lk(:)) & ~cellfun(@isempty, rk(:)), 1);
                if ~isempty(bad)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.bilateral.subjectOrder', ...
                        sprintf('LH/RH scalar lists are not subject-order matched at row %g: LH key=%s, RH key=%s.', bad, lk{bad}, rk{bad}), 1, 'red*')];
                    Y = []; roiInfo = struct(); metas = [parts{1}.meta; parts{2}.meta]; return;
                end
            end
            Y = [];
            roiIDs = []; roiNames = {}; hemi = {}; roiSourceIDs = [];
            scalarFilesOut = {};
            annotFilesOut = {};
            metas = struct([]);
            for pi = 1:numel(parts)
                Y = [Y, parts{pi}.Y]; %#ok<AGROW>
                roiIDs = [roiIDs; parts{pi}.info.roiIDs(:)]; %#ok<AGROW>
                roiNames = [roiNames; parts{pi}.info.roiNames(:)]; %#ok<AGROW>
                hemi = [hemi; repmat({parts{pi}.hemi}, numel(parts{pi}.info.roiNames), 1)]; %#ok<AGROW>
                roiSourceIDs = [roiSourceIDs; parts{pi}.info.roiSourceIDs(:)]; %#ok<AGROW>
                if isempty(scalarFilesOut), scalarFilesOut = parts{pi}.info.scalarFiles(:); end
                annotFilesOut = [annotFilesOut; parts{pi}.info.annotFiles(:)]; %#ok<AGROW>
                metas = [metas; parts{pi}.meta]; %#ok<AGROW>
            end
            roiInfo = struct();
            roiInfo.mode = 'native_annotation_collapse';
            roiInfo.collapseMethod = method;
            roiInfo.roiIDs = roiIDs(:)';
            roiInfo.roiSourceIDs = roiSourceIDs(:)';
            roiInfo.roiNames = roiNames(:)';
            roiInfo.hemisphere = hemi(:)';
            roiInfo.scalarFiles = scalarFilesOut(:)';
            roiInfo.annotationFiles = annotFilesOut(:)';
            byHemi = struct('lh',{{}},'rh',{{}});
            geometryByHemi = struct('lh',{{}},'rh',{{}});
            for pi = 1:numel(parts)
                % The first annotation is the canonical ROI-set authority used by readOneHemisphereROIMatrix.
                byHemi.(parts{pi}.hemi) = parts{pi}.info.annotFiles(1);
                if ~isempty(parts{pi}.geometryFile), geometryByHemi.(parts{pi}.hemi) = {parts{pi}.geometryFile}; end
            end
            roiInfo.annotationFilesByHemisphere = byHemi;
            roiInfo.surfaceGeometryFilesByHemisphere = geometryByHemi;
            roiInfo.nSubjects = double(size(Y,1));
            roiInfo.nROIs = double(size(Y,2));
        end

        function [Y, info, metas, messages] = readOneHemisphereROIMatrix(scalarFiles, annotFiles, hemi, method)
            % readOneHemisphereROIMatrix  Read and collapse one hemisphere of surface scalar/annotation pairs.
            %
            % Consumes scalarFiles, annotFiles, hemi, method; returns Y, info, metas, messages.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            scalarFiles = NMDataIOSurfaceTools.asCellstr(scalarFiles);
            annotFiles = NMDataIOSurfaceTools.asCellstr(annotFiles);
            metas = repmat(NMDataIOSurfaceTools.emptyMeta(), numel(scalarFiles), 1);
            Y = []; info = struct();
            if isempty(scalarFiles) || isempty(annotFiles)
                messages = [messages; NMDataIOMessageTools.make('danger', true, ['surfaceRoi.' hemi '.files'], ...
                    sprintf('Native surface ROI import requires both %s scalar files and %s annotation files.', upper(hemi), upper(hemi)), 1, 'red*')];
                return;
            end
            if numel(scalarFiles) ~= numel(annotFiles)
                messages = [messages; NMDataIOMessageTools.make('danger', true, ['surfaceRoi.' hemi '.length'], ...
                    sprintf('%s scalar/annotation lists must have the same length: scalar=%g, annotation=%g.', upper(hemi), numel(scalarFiles), numel(annotFiles)), 1, 'red*')];
                return;
            end
            badHemi = NMDataIOSurfaceTools.findHemisphereMismatch(scalarFiles, annotFiles, hemi);
            if ~isempty(badHemi)
                messages = [messages; NMDataIOMessageTools.make('danger', true, ['surfaceRoi.' hemi '.hemisphere'], badHemi, 1, 'red*')];
                return;
            end
            sk = NMDataIOSurfaceTools.subjectKeysFromFiles(scalarFiles);
            ak = NMDataIOSurfaceTools.subjectKeysFromFiles(annotFiles);
            badKey = find(~strcmp(sk(:), ak(:)) & ~cellfun(@isempty, sk(:)) & ~cellfun(@isempty, ak(:)), 1);
            if ~isempty(badKey)
                messages = [messages; NMDataIOMessageTools.make('danger', true, ['surfaceRoi.' hemi '.subjectOrder'], ...
                    sprintf('%s scalar/annotation lists are not order-matched at row %g: scalar key=%s, annotation key=%s.', upper(hemi), badKey, sk{badKey}, ak{badKey}), 1, 'red*')];
                return;
            end
            firstLabels = []; roiIDs = []; roiNames = {};
            for i = 1:numel(scalarFiles)
                try
                    [vec, meta] = NMDataIOSurfaceTools.readSurfaceScalar(scalarFiles{i});
                    [labels, annotInfo] = NMDataIOSurfaceTools.readAnnotationLabels(annotFiles{i});
                    metas(i) = meta;
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, sprintf('surfaceRoi.%s.read[%g]', hemi, i))]; %#ok<AGROW>
                    return;
                end
                if numel(vec) ~= numel(labels)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, ['surfaceRoi.' hemi '.vertexCount'], ...
                        sprintf('%s row %g scalar/annotation vertex counts differ: scalar=%g, annotation=%g.', upper(hemi), i, numel(vec), numel(labels)), 1, 'red*')]; %#ok<AGROW>
                    return;
                end
                if i == 1
                    firstLabels = labels(:);
                    [roiIDs, roiNames] = NMDataIOSurfaceTools.roiSetFromAnnotation(labels, annotInfo, hemi);
                    Y = nan(numel(scalarFiles), numel(roiIDs));
                else
                    present = unique(labels(isfinite(labels) & labels~=0));
                    missing = setdiff(roiIDs(:), present(:));
                    if numel(missing) == numel(roiIDs)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, ['surfaceRoi.' hemi '.roiOverlap'], ...
                            sprintf('%s row %g annotation has no ROI overlap with the first annotation ROI set.', upper(hemi), i), 1, 'red*')]; %#ok<AGROW>
                        return;
                    end
                end
                Y(i,:) = NMDataIOSurfaceTools.collapseVectorByLabels(vec(:), labels(:), roiIDs(:), method);
            end
            info = struct('hemi',hemi,'roiIDs',1:numel(roiIDs),'roiSourceIDs',roiIDs(:)', ...
                'roiNames',{roiNames(:)'},'scalarFiles',{scalarFiles(:)},'annotFiles',{annotFiles(:)}, ...
                'firstLabelVector',firstLabels(:));
        end

        function values = collapseVectorByLabels(vec, labels, roiIDs, method)
            % collapseVectorByLabels  Aggregate vertex values by ROI labels using mean/median style reducers.
            %
            % Consumes vec, labels, roiIDs, method; returns values.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            values = nan(1, numel(roiIDs));
            vec = double(vec(:)); labels = double(labels(:));
            for r = 1:numel(roiIDs)
                idx = labels == double(roiIDs(r)) & isfinite(vec);
                if any(idx)
                    switch method
                        case 'median'
                            values(r) = median(vec(idx), 'omitnan');
                        otherwise
                            values(r) = mean(vec(idx), 'omitnan');
                    end
                end
            end
        end

        function [labels, info] = readAnnotationLabels(filename)
            % readAnnotationLabels  Read FreeSurfer annotation labels and color/name metadata.
            %
            % Filename -> labels, info.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % Throws on invalid preconditions instead of returning an ambiguous partial result; diagnostics are returned as structured messages for explicit UI/API handling.
            filename = char(string(filename));
            if isempty(filename) || exist(filename,'file') ~= 2
                error('NMDataIOSurfaceTools:MissingAnnotationFile', 'Surface annotation file does not exist: %s', filename);
            end
            if exist('read_annotation','file') == 2 || ~isempty(which('read_annotation'))
                try
                    [~, labels, ct] = read_annotation(filename);
                catch ME1
                    if exist('Read_Brain_Annotation','file') == 2 || ~isempty(which('Read_Brain_Annotation'))
                        try
                            [~, labels, ct] = Read_Brain_Annotation(filename);
                        catch ME2
                            error('NMDataIOSurfaceTools:AnnotationReadFailed', ...
                                'Could not read annotation file %s. read_annotation: %s | Read_Brain_Annotation: %s', filename, ME1.message, ME2.message);
                        end
                    else
                        error('NMDataIOSurfaceTools:AnnotationReadFailed', ...
                            'Could not read annotation file %s using read_annotation: %s', filename, ME1.message);
                    end
                end
            elseif exist('Read_Brain_Annotation','file') == 2 || ~isempty(which('Read_Brain_Annotation'))
                [~, labels, ct] = Read_Brain_Annotation(filename);
            else
                error('NMDataIOSurfaceTools:MissingAnnotationReader', 'Native surface ROI import requires FreeSurfer read_annotation.m or Read_Brain_Annotation.m on the MATLAB path.');
            end
            labels = double(labels(:));
            info = struct();
            info.file = filename;
            info.colortable = ct;
        end

        function [roiIDs, roiNames] = roiSetFromAnnotation(labels, annotInfo, hemi)
            % roiSetFromAnnotation  Build ROI IDs and display names from annotation labels and hemisphere information.
            %
            % Consumes labels, annotInfo, hemi; returns roiIDs, roiNames.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            vals = unique(double(labels(isfinite(labels) & labels ~= 0)));
            vals = vals(:)';
            roiIDs = vals;
            roiNames = arrayfun(@(v) sprintf('%s_ROI_%g', hemi, v), vals, 'UniformOutput', false);
            if isstruct(annotInfo) && isfield(annotInfo,'colortable') && isstruct(annotInfo.colortable) && ...
                    isfield(annotInfo.colortable,'table') && isfield(annotInfo.colortable,'struct_names') && ~isempty(annotInfo.colortable.table)
                tableIDs = double(annotInfo.colortable.table(:,5));
                names = annotInfo.colortable.struct_names;
                for r = 1:numel(vals)
                    hit = find(tableIDs == vals(r), 1);
                    if ~isempty(hit) && hit <= numel(names) && ~isempty(names{hit})
                        roiNames{r} = sprintf('%s_%s', hemi, char(string(names{hit})));
                    end
                end
            end
        end

        function keys = subjectKeysFromFiles(files)
            % subjectKeysFromFiles  Infer subject keys from surface filenames for case matching.
            %
            % Files -> keys.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            files = NMDataIOSurfaceTools.asCellstr(files);
            keys = cell(numel(files),1);
            for i = 1:numel(files)
                [~,nm,ext] = fileparts(files{i});
                base = [nm ext];
                base = regexprep(base, '\.(gii|mgh|mgz|annot)$', '', 'ignorecase');
                base = regexprep(base, '^(lh|rh)\.', '', 'ignorecase');
                base = regexprep(base, '^(aparc|aparc_[^\.]+|Schaefer[^\.]+)\.', '', 'ignorecase');
                base = regexprep(base, '^mesh\.[^\.]+\.', '', 'ignorecase');
                tok = regexp(base, '([A-Za-z0-9]+-[A-Za-z0-9_]+_[A-Za-z0-9_]+|sub[-_A-Za-z0-9]+|[A-Za-z]+-[A-Za-z0-9_]+)', 'match', 'once');
                if isempty(tok), tok = base; end
                keys{i} = char(tok);
            end
        end

        function hemi = inferHemisphereList(files, fallback)
            % inferHemisphereList  Infer per-file hemisphere labels from filenames with a fallback value.
            %
            % Files, fallback -> hemi.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            files = NMDataIOSurfaceTools.asCellstr(files);
            hemi = fallback;
            if isempty(files), return; end
            vals = cellfun(@(f) NMDataIOSurfaceTools.inferHemisphereFromFile(f), files, 'UniformOutput', false);
            u = unique(vals(~cellfun(@isempty, vals)));
            if numel(u) == 1, hemi = u{1}; end
        end

        function hemi = inferHemisphereFromFile(file)
            % inferHemisphereFromFile  Infer a single hemisphere code from a surface or annotation filename.
            %
            % File -> hemi.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            [~,nm,ext] = fileparts(char(string(file))); %#ok<ASGLU>
            base = lower([nm ext]);
            if startsWith(base,'lh.'), hemi = 'left'; return; end
            if startsWith(base,'rh.'), hemi = 'right'; return; end
            if contains(base,'_lh') || contains(base,'.lh.') || contains(base,'left'), hemi = 'left'; return; end
            if contains(base,'_rh') || contains(base,'.rh.') || contains(base,'right'), hemi = 'right'; return; end
            hemi = '';
        end

        function contract = validateSurfaceGeometryContract(nativeGeometryFile, inflatedGeometryFile, expectedVertexCount, options)
            % validateSurfaceGeometryContract  Validate authoritative native and optional inflated surface geometry.
            %
            % contract = NMDataIOSurfaceTools.validateSurfaceGeometryContract(nativeGeometryFile,
            % inflatedGeometryFile, expectedVertexCount, options) reads the configured native
            % geometry, validates its vertex count against the imported vertexwise feature
            % space, and—when supplied—requires the inflated geometry to have exactly the same
            % indexed triangle arrays.  Equal vertex counts alone never establish correspondence.
            %
            % nativeGeometryFile and inflatedGeometryFile accept the same single-file or
            % semicolon/newline-delimited list representation already used by DataIO surface
            % display meshes.  Multiple parts are validated pairwise and their vertex counts
            % are summed for the feature-space check.
            %
            % options.surfaceTemplate and options.surfaceHemisphere are persisted as declared
            % provenance.  Filename-derived hemisphere evidence is used only to reject explicit
            % contradictions; it is not used to invent missing scientific metadata.
            if nargin < 2, inflatedGeometryFile = ''; end
            if nargin < 3 || isempty(expectedVertexCount), expectedVertexCount = NaN; end
            if nargin < 4 || isempty(options), options = struct(); end
            nativeFiles = NMDataIOSurfaceTools.splitSurfaceFileList(nativeGeometryFile);
            inflatedFiles = NMDataIOSurfaceTools.splitSurfaceFileList(inflatedGeometryFile);
            surfaceTemplate = NMDataIOSurfaceTools.asChar(NMDataIOSurfaceTools.fieldOr(options,'surfaceTemplate','unknown'));
            surfaceHemisphere = lower(NMDataIOSurfaceTools.asChar(NMDataIOSurfaceTools.fieldOr(options,'surfaceHemisphere','auto')));
            contract = struct('schema','NMDataIOSurfaceGeometryContract','schemaVersion',1, ...
                'validationVersion','NM-DATAIO-SURFACE-GEOMETRY-V1', ...
                'nativeAvailable',false,'inflatedAvailable',false,'inflatedValidated',false, ...
                'nativeFiles',{nativeFiles(:)'},'inflatedFiles',{inflatedFiles(:)'}, ...
                'surfaceTemplate',surfaceTemplate,'surfaceHemisphere',surfaceHemisphere, ...
                'vertexCount',0,'faceCount',0,'partCount',0, ...
                'nativeGeometryIdentity','','inflatedGeometryIdentity','', ...
                'topologyIdentity','','vertexOrderIdentity','', ...
                'correspondenceMethod','none','parts',struct([]));
            if isempty(nativeFiles)
                if ~isempty(inflatedFiles)
                    error('NMDataIOSurfaceTools:InflatedGeometryNeedsNative', ...
                        ['An inflated surface template was supplied without an authoritative native surface geometry. ', ...
                         'Configure surfaceGeometryFile before surfaceInflatedGeometryFile.']);
                end
                error('NMDataIOSurfaceTools:MissingSurfaceGeometry', ...
                    'Vertexwise surface import requires a non-inflated geometry file.');
            end
            if ~isempty(inflatedFiles) && numel(inflatedFiles) ~= numel(nativeFiles)
                error('NMDataIOSurfaceTools:SurfaceGeometryPartCountMismatch', ...
                    'Native and inflated surface geometry lists must contain the same number of parts: native=%g, inflated=%g.', ...
                    numel(nativeFiles),numel(inflatedFiles));
            end
            partTemplate = struct('partIndex',0,'nativeFile','','inflatedFile','', ...
                'nativeFormat','','inflatedFormat','','hemisphere','', ...
                'vertexCount',0,'faceCount',0,'nativeGeometryHash','', ...
                'inflatedGeometryHash','','topologyHash','', ...
                'correspondenceValidated',false,'correspondenceMethod','none');
            parts = repmat(partTemplate,numel(nativeFiles),1);
            totalVertices = 0;
            totalFaces = 0;
            topologyParts = cell(numel(nativeFiles),1);
            nativeParts = cell(numel(nativeFiles),1);
            inflatedParts = cell(numel(nativeFiles),1);
            inferredHemispheres = cell(numel(nativeFiles),1);
            for i = 1:numel(nativeFiles)
                [nativeVertices,nativeFaces,nativeMeta] = NMDataIOSurfaceTools.readSurfaceGeometry(nativeFiles{i});
                nativeHemi = NMDataIOSurfaceTools.inferHemisphereFromFile(nativeFiles{i});
                inflatedVertices = [];
                inflatedFaces = [];
                inflatedMeta = struct('format','');
                inflatedHemi = '';
                if ~isempty(inflatedFiles)
                    [inflatedVertices,inflatedFaces,inflatedMeta] = NMDataIOSurfaceTools.readSurfaceGeometry(inflatedFiles{i});
                    inflatedHemi = NMDataIOSurfaceTools.inferHemisphereFromFile(inflatedFiles{i});
                    if size(nativeVertices,1) ~= size(inflatedVertices,1)
                        error('NMDataIOSurfaceTools:SurfaceInflatedVertexCountMismatch', ...
                            ['Native and inflated surface part %g have different vertex counts: native=%g (%s), ', ...
                             'inflated=%g (%s).'],i,size(nativeVertices,1),nativeFiles{i},size(inflatedVertices,1),inflatedFiles{i});
                    end
                    if size(nativeFaces,1) ~= size(inflatedFaces,1) || ~isequal(nativeFaces,inflatedFaces)
                        error('NMDataIOSurfaceTools:SurfaceInflatedTopologyMismatch', ...
                            ['Native and inflated surface part %g do not have identical indexed triangle arrays. ', ...
                             'Inflation is permitted only when vertex ordering and face indexing are authoritative matches. ', ...
                             'Native: %s | Inflated: %s'],i,nativeFiles{i},inflatedFiles{i});
                    end
                    if ~isempty(nativeHemi) && ~isempty(inflatedHemi) && ~strcmp(nativeHemi,inflatedHemi)
                        error('NMDataIOSurfaceTools:SurfaceInflatedHemisphereMismatch', ...
                            'Native and inflated surface part %g encode different hemispheres: %s versus %s.',i,nativeHemi,inflatedHemi);
                    end
                end
                inferred = nativeHemi;
                if isempty(inferred), inferred = inflatedHemi; end
                NMDataIOSurfaceTools.assertDeclaredHemisphere(surfaceHemisphere,inferred,nativeFiles{i});
                inferredHemispheres{i} = inferred;
                topologyHash = NMDataIOSurfaceTools.hashSurfaceArrays([],nativeFaces,'topology_v1');
                nativeHash = NMDataIOSurfaceTools.hashSurfaceArrays(nativeVertices,nativeFaces,'geometry_v1');
                inflatedHash = '';
                if ~isempty(inflatedFiles)
                    inflatedHash = NMDataIOSurfaceTools.hashSurfaceArrays(inflatedVertices,inflatedFaces,'geometry_v1');
                end
                parts(i).partIndex = i;
                parts(i).nativeFile = nativeFiles{i};
                if ~isempty(inflatedFiles), parts(i).inflatedFile = inflatedFiles{i}; end
                parts(i).nativeFormat = nativeMeta.format;
                parts(i).inflatedFormat = inflatedMeta.format;
                parts(i).hemisphere = inferred;
                parts(i).vertexCount = double(size(nativeVertices,1));
                parts(i).faceCount = double(size(nativeFaces,1));
                parts(i).nativeGeometryHash = nativeHash;
                parts(i).inflatedGeometryHash = inflatedHash;
                parts(i).topologyHash = topologyHash;
                parts(i).correspondenceValidated = ~isempty(inflatedFiles);
                if ~isempty(inflatedFiles), parts(i).correspondenceMethod = 'exact_indexed_faces'; end
                totalVertices = totalVertices + size(nativeVertices,1);
                totalFaces = totalFaces + size(nativeFaces,1);
                topologyParts{i} = topologyHash;
                nativeParts{i} = nativeHash;
                inflatedParts{i} = inflatedHash;
            end
            if isfinite(double(expectedVertexCount)) && double(expectedVertexCount) > 0 && totalVertices ~= double(expectedVertexCount)
                error('NMDataIOSurfaceTools:SurfaceGeometryFeatureCountMismatch', ...
                    ['Authoritative native surface geometry has %g total vertices, but the imported vertexwise feature ', ...
                     'space has %g values. Select the exact template mesh used for surface-data import.'], ...
                    totalVertices,double(expectedVertexCount));
            end
            if strcmp(surfaceHemisphere,'bilateral') && numel(nativeFiles) == 2
                detectedParts = inferredHemispheres(~cellfun(@isempty,inferredHemispheres));
                if numel(detectedParts) == 2
                    detected = sort(detectedParts(:));
                    if ~isequal(detected,{'left';'right'})
                        error('NMDataIOSurfaceTools:SurfaceBilateralHemisphereMismatch', ...
                            'Bilateral two-part surface geometry must contain one left and one right hemisphere.');
                    end
                end
            end
            contract.nativeAvailable = true;
            contract.inflatedAvailable = ~isempty(inflatedFiles);
            contract.inflatedValidated = ~isempty(inflatedFiles);
            contract.vertexCount = double(totalVertices);
            contract.faceCount = double(totalFaces);
            contract.partCount = double(numel(parts));
            contract.parts = parts;
            contract.nativeGeometryIdentity = NMDataIOSurfaceTools.hashText(strjoin(nativeParts,'|'));
            contract.topologyIdentity = NMDataIOSurfaceTools.hashText(strjoin(topologyParts,'|'));
            contract.vertexOrderIdentity = ['indexed_faces_sha256:' contract.topologyIdentity];
            if ~isempty(inflatedFiles)
                contract.inflatedGeometryIdentity = NMDataIOSurfaceTools.hashText(strjoin(inflatedParts,'|'));
                contract.correspondenceMethod = 'exact_indexed_faces';
            else
                contract.correspondenceMethod = 'native_only';
            end
        end

        function msg = findHemisphereMismatch(scalarFiles, annotFiles, hemi)
            % findHemisphereMismatch  Report scalar/annotation hemisphere mismatches before ROI collapse.
            %
            % Consumes scalarFiles, annotFiles, hemi; returns msg.
            % It normalizes surface scalar/annotation data before those features enter the generic matrix-style import path.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            msg = '';
            want = 'left'; if strcmpi(hemi,'rh'), want = 'right'; end
            files = [NMDataIOSurfaceTools.asCellstr(scalarFiles); NMDataIOSurfaceTools.asCellstr(annotFiles)];
            for i = 1:numel(files)
                h = NMDataIOSurfaceTools.inferHemisphereFromFile(files{i});
                if ~isempty(h) && ~strcmp(h, want)
                    msg = sprintf('Expected %s hemisphere files but found %s-hemisphere pattern in: %s.', upper(hemi), h, files{i});
                    return;
                end
            end
        end
    end

    methods (Static)
        function files = splitSurfaceFileList(txt)
            txt = NMDataIOSurfaceTools.asChar(txt);
            if isempty(txt), files = {}; return; end
            raw = regexp(txt, '[\r\n;]+', 'split');
            files = cellfun(@strtrim, raw(:), 'UniformOutput', false);
            files = files(~cellfun(@isempty, files));
        end
    end

    methods (Static, Access = private)
        function [formatKind, readFile] = resolveSurfaceStorageFile(filename, materialize)
            % resolveSurfaceStorageFile  Classify surface storage format and resolve compressed GIFTI for readers.
            %
            % Purpose:
            %   Own compound-extension dispatch for surface scalar and geometry files.
            %
            % Inputs/outputs:
            %   filename is the original source path. formatKind is one of gii, mgh, mgz, or
            %   freesurfer_curv. readFile is the concrete reader path; with materialize=false no
            %   decompression is performed and readFile remains filename.
            %
            % Authority and flow:
            %   .gii.gz is recognized before fileparts-style last-suffix dispatch. Compression never
            %   changes scientific format. GIFTI decompression is delegated to resolveGzippedGifti.
            %
            % Materialization and performance:
            %   With materialize=true this may perform file IO and one cached gunzip operation.
            %   With materialize=false it performs only string classification and is safe for metadata
            %   formatting paths.
            %
            % Failure semantics:
            %   Missing files are rejected by the public scalar/geometry readers. Decompression
            %   failures propagate explicitly from resolveGzippedGifti.
            if nargin < 2 || isempty(materialize), materialize = true; end
            filename = char(string(filename));
            readFile = filename;
            lowerName = lower(filename);
            if ~isempty(regexpi(lowerName, '\.gii\.gz$', 'once'))
                formatKind = 'gii';
                if materialize
                    readFile = NMDataIOSurfaceTools.resolveGzippedGifti(filename);
                end
                return;
            end
            [~,~,ext] = fileparts(lowerName);
            switch ext
                case '.gii'
                    formatKind = 'gii';
                case '.mgh'
                    formatKind = 'mgh';
                case '.mgz'
                    formatKind = 'mgz';
                otherwise
                    formatKind = 'freesurfer_curv';
            end
        end

        function resolvedFile = resolveGzippedGifti(filename)
            % resolveGzippedGifti  Resolve one .gii.gz source to a cached uncompressed .gii reader path.
            %
            % Purpose:
            %   Permit SPM/GIIread GIFTI readers to consume compressed CAT12/CAT surface files while
            %   preserving the original .gii.gz path as provenance.
            %
            % Authority and flow:
            %   The cache identity is derived from absolute source path, byte size, and modification
            %   time. gunzip output is materialization only and never becomes the scientific source.
            %   Relative ExternalFileBinary payloads declared by the GIFTI XML are staged beside the
            %   cached .gii so reader-relative file_array references remain valid after decompression.
            %
            % Materialization and performance:
            %   Reads source metadata and may gunzip the complete file once. Repeated Probe/import/QC
            %   reads reuse the cached file for the same source identity. It parses only ExternalFileName
            %   attributes needed to stage companion payloads; it does not decode or scan vertex data.
            %
            % Failure semantics:
            %   Missing sources, cache-directory failures, gunzip errors, missing decompressed GIFTI
            %   output, or missing referenced ExternalFileBinary payloads fail explicitly.
            filename = char(string(filename));
            if isempty(filename) || exist(filename,'file') ~= 2
                error('NMDataIOSurfaceTools:MissingFile', 'Compressed GIFTI file does not exist: %s', filename);
            end
            info = dir(filename);
            if isempty(info)
                error('NMDataIOSurfaceTools:MissingFile', 'Could not stat compressed GIFTI file: %s', filename);
            end
            sourceKey = sprintf('%s|%0.0f|%.17g', filename, double(info(1).bytes), double(info(1).datenum));
            key = NMDataIOSurfaceTools.hashText(sourceKey);
            cacheRoot = NMUISessionTools.privateProcessTempRoot('gifti');
            cacheDir = fullfile(cacheRoot, key(1:min(24,numel(key))));
            uncompressedSource = regexprep(filename, '\.gz$', '', 'ignorecase');
            [~,baseName,baseExt] = fileparts(uncompressedSource);
            resolvedFile = fullfile(cacheDir, [baseName baseExt]);
            if exist(resolvedFile,'file') == 2
                NMDataIOSurfaceTools.stageGiftiExternalPayloads(resolvedFile, fileparts(filename), cacheDir, filename);
                return;
            end
            stageDir = tempname(cacheRoot);
            [ok,msg] = mkdir(stageDir);
            if ~ok
                error('NMDataIOSurfaceTools:GiftiCacheCreateFailed', ...
                    'Could not create the temporary folder for compressed GIFTI data %s: %s', stageDir, msg);
            end
            stageCleanup = onCleanup(@() NMUISessionTools.cleanupMaterializationStage(stageDir)); %#ok<NASGU>
            try
                outFiles = gunzip(filename, stageDir);
            catch ME
                cause = MException('NMDataIOSurfaceTools:GiftiGunzipFailed', ...
                    'Could not decompress GIFTI file %s.', filename);
                cause = addCause(cause, ME);
                throw(cause);
            end
            outFiles = NMDataIOSurfaceTools.asCellstr(outFiles);
            stagedFile = fullfile(stageDir, [baseName baseExt]);
            if exist(stagedFile,'file') ~= 2
                error('NMDataIOSurfaceTools:GiftiGunzipOutputMissing', ...
                    'gunzip did not create a readable .gii file for %s (returned %d path(s)).', filename, numel(outFiles));
            end
            NMDataIOSurfaceTools.stageGiftiExternalPayloads(stagedFile, fileparts(filename), stageDir, filename);
            [ok,msg] = movefile(stageDir, cacheDir);
            if ~ok
                error('NMDataIOSurfaceTools:GiftiCacheMoveFailed', ...
                    'Could not publish the complete decompressed GIFTI bundle to %s: %s', cacheDir, msg);
            end
            clear stageCleanup;
        end

        function stageGiftiExternalPayloads(giiFile, sourceDir, cacheDir, provenanceFile)
            % stageGiftiExternalPayloads  Materialize relative ExternalFileBinary payloads beside cached GIFTI XML.
            %
            % Purpose:
            %   Preserve CAT/SPM GIFTI ExternalFileBinary semantics when a compressed .gii.gz source is
            %   decompressed outside its source directory. CAT12 may store the XML header as .gii.gz and
            %   the externally referenced numerical payload as either the logical .dat file or a storage-
            %   compressed .dat.gz file while ExternalFileName continues to name the logical .dat object.
            %
            % Inputs/outputs:
            %   giiFile is the cached uncompressed GIFTI XML. sourceDir contains the scientific .gii.gz
            %   source and its external storage payloads. cacheDir is the reader cache beside giiFile.
            %   provenanceFile is used only for actionable diagnostics. No scientific state is mutated.
            %
            % Authority and flow:
            %   The GIFTI ExternalFileName is the sole authority for the logical payload name. For a
            %   relative logical reference X, storage resolution permits exactly X or X.gz, in that order.
            %   X is copied byte-for-byte; X.gz is gunzipped so the cache contains the exact logical X path
            %   expected by SPM/GIIread. No alternative basename, extension, or neighbouring payload is
            %   inferred. Absolute references remain direct reader paths and therefore must exist exactly.
            %
            % Scientific/state contract:
            %   Compression is storage metadata only. Materialization must not change vertex order,
            %   numerical payload bytes after decompression, ExternalFileOffset semantics, or source
            %   identity. No decoding, resampling, interpolation, or surface-space inference occurs here.
            %
            % Materialization and performance:
            %   Reads the cached GIFTI XML once and performs O(K) source checks for K distinct external
            %   payloads. Uncompressed payloads are copied and compressed payloads are gunzipped only when
            %   their source path/size/mtime identity differs from the cache marker. Probe -> Import -> QC
            %   therefore reuses the same materialization. This performs file IO and is not an interactive
            %   viewer-navigation operation.
            %
            % Failure semantics:
            %   Missing/unreadable exact logical or exact .gz storage variants, unsafe parent-directory
            %   references, ambiguous Windows case reconciliation, cache creation, gunzip/copy, or marker
            %   failures are explicit and identify the original compressed GIFTI source.
            giiFile = char(string(giiFile));
            sourceDir = char(string(sourceDir));
            cacheDir = char(string(cacheDir));
            provenanceFile = char(string(provenanceFile));
            fid = fopen(giiFile, 'rt');
            if fid < 0
                error('NMDataIOSurfaceTools:GiftiCacheReadFailed', ...
                    'Could not open the temporary uncompressed GIFTI file for %s: %s', provenanceFile, giiFile);
            end
            cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
            xmlText = fread(fid, inf, '*char')';
            refs = regexp(xmlText, 'ExternalFileName\s*=\s*["'']([^"'']*)["'']', 'tokens');
            if isempty(refs), return; end
            names = cell(numel(refs),1);
            for i = 1:numel(refs)
                names{i} = NMDataIOSurfaceTools.decodeXmlAttribute(refs{i}{1});
            end
            names = unique(names(~cellfun(@isempty,names)), 'stable');
            for i = 1:numel(names)
                ref = strtrim(names{i});
                if isempty(ref), continue; end
                if ~isempty(regexp(ref, '^[A-Za-z]:[\\/]|^\\\\|^/', 'once'))
                    % An absolute XML reference is itself the reader path; do not rewrite its identity.
                    [fidAbs, openMsgAbs] = fopen(ref, 'rb');
                    if fidAbs < 0
                        error('NMDataIOSurfaceTools:GiftiExternalPayloadUnreadable', ...
                            ['GIFTI %s references absolute external payload %s, but that exact logical ' ...
                             'file cannot be opened: %s'], provenanceFile, ref, openMsgAbs);
                    end
                    fclose(fidAbs);
                    continue;
                end
                rel = strrep(strrep(ref, '/', filesep), '\', filesep);
                parts = strsplit(rel, filesep);
                if any(strcmp(parts, '..'))
                    error('NMDataIOSurfaceTools:GiftiExternalPayloadUnsafePath', ...
                        'GIFTI %s contains an external data-file path that moves outside its source folder: %s.', provenanceFile, ref);
                end
                [sourceFile, sourceIdentity, storageKind] = NMDataIOSurfaceTools.resolveGiftiExternalPayloadSource( ...
                    sourceDir, rel, provenanceFile, ref);
                destinationFile = fullfile(cacheDir, rel);
                destinationDir = fileparts(destinationFile);
                if exist(destinationDir,'dir') ~= 7
                    [ok,msg] = mkdir(destinationDir);
                    if ~ok
                        error('NMDataIOSurfaceTools:GiftiExternalCacheCreateFailed', ...
                            'Could not create the temporary folder needed for external GIFTI data (%s): %s', destinationDir, msg);
                    end
                end
                markerFile = [destinationFile '.nm_source_identity'];
                cachedIdentity = '';
                if exist(markerFile,'file') == 2
                    try, cachedIdentity = strtrim(fileread(markerFile)); catch, cachedIdentity = ''; end
                end
                needsMaterialize = exist(destinationFile,'file') ~= 2 || isempty(sourceIdentity) || ...
                    ~strcmp(cachedIdentity, sourceIdentity);
                if needsMaterialize
                    NMDataIOSurfaceTools.materializeGiftiExternalPayload( ...
                        sourceFile, destinationFile, storageKind, provenanceFile);
                    fidMarker = fopen(markerFile, 'wt');
                    if fidMarker < 0
                        error('NMDataIOSurfaceTools:GiftiExternalMarkerWriteFailed', ...
                            'Could not record the temporary GIFTI data-file identity in %s for %s.', markerFile, provenanceFile);
                    end
                    markerCleanup = onCleanup(@() fclose(fidMarker)); %#ok<NASGU>
                    fprintf(fidMarker, '%s\n', sourceIdentity);
                    clear markerCleanup;
                end
            end
        end

        function [sourceFile, sourceIdentity, storageKind] = resolveGiftiExternalPayloadSource(sourceDir, rel, provenanceFile, ref)
            % resolveGiftiExternalPayloadSource  Resolve one logical GIFTI ExternalFileName to concrete storage.
            %
            % Purpose:
            %   Resolve the exact logical payload named by a relative GIFTI ExternalFileName while allowing
            %   CAT12's deterministic gzip storage variant of that same object.
            %
            % Inputs/outputs:
            %   sourceDir is the scientific source directory and rel is the normalized logical XML name.
            %   sourceFile is the readable concrete storage path; sourceIdentity is path/size/mtime when
            %   stat metadata are available; storageKind is 'plain' or 'gzip'.
            %
            % Authority and flow:
            %   Candidate order is exact logical path X, then the compression-only storage variant X.gz.
            %   Direct binary open is authoritative. Directory reconciliation occurs only after direct-open
            %   failure and may recover only those same two names (case-insensitively on Windows). This is
            %   not basename inference: removing gzip restores exactly the ExternalFileName declared in XML.
            %
            % Scientific/state contract:
            %   The logical payload identity remains X regardless of storage compression. No alternative
            %   extension, subject identifier, hemisphere, or adjacent file is inferred.
            %
            % Materialization and performance:
            %   Normal execution performs at most two fopen/fclose operations and one stat. Directory
            %   enumeration is failure-path only. Vertex data are not decoded here.
            %
            % Failure semantics:
            %   If neither X nor X.gz resolves to exactly one readable file, fail explicitly with both
            %   attempted storage paths. Ambiguous Windows case matches fail rather than choosing one.
            sourceDir = char(string(sourceDir));
            rel = char(string(rel));
            provenanceFile = char(string(provenanceFile));
            ref = char(string(ref));
            candidatePlain = fullfile(sourceDir, rel);
            candidateGzip = [candidatePlain '.gz'];
            [sourceFile, sourceIdentity, storageKind, plainMsg, gzipMsg] = ...
                NMDataIOSurfaceTools.tryGiftiExternalStorageCandidates(candidatePlain, candidateGzip);
            if ~isempty(sourceFile), return; end

            [relDir, relName, relExt] = fileparts(rel);
            lookupDir = fullfile(sourceDir, relDir);
            entries = dir(lookupDir);
            entries = entries(~[entries.isdir]);
            names = {entries.name};
            wanted = {[relName relExt], [relName relExt '.gz']};
            kinds = {'plain','gzip'};
            for k = 1:2
                idx = find(strcmp(names, wanted{k}));
                if isempty(idx) && ispc
                    idx = find(strcmpi(names, wanted{k}));
                end
                if numel(idx) > 1
                    error('NMDataIOSurfaceTools:GiftiExternalPayloadAmbiguous', ...
                        'GIFTI %s external data-file reference %s matches %d files named %s in %s.', ...
                        provenanceFile, ref, numel(idx), wanted{k}, lookupDir);
                end
                if numel(idx) == 1
                    candidate = fullfile(lookupDir, entries(idx).name);
                    [fid, openMsg] = fopen(candidate, 'rb');
                    if fid >= 0
                        fclose(fid);
                        sourceFile = candidate;
                        storageKind = kinds{k};
                        info = dir(sourceFile);
                        if isempty(info)
                            sourceIdentity = '';
                        else
                            sourceIdentity = sprintf('%s|%0.0f|%.17g', sourceFile, ...
                                double(info(1).bytes), double(info(1).datenum));
                        end
                        return;
                    end
                    if k == 1, plainMsg = openMsg; else, gzipMsg = openMsg; end
                end
            end
            error('NMDataIOSurfaceTools:GiftiExternalPayloadMissing', ...
                ['Compressed GIFTI %s references external data file %s. Neither %s ' ...
                 'nor its compressed form %s could be opened or located. File diagnostics: ' ...
                 'plain="%s"; gzip="%s"'], ...
                provenanceFile, ref, candidatePlain, candidateGzip, plainMsg, gzipMsg);
        end

        function [sourceFile, sourceIdentity, storageKind, plainMsg, gzipMsg] = tryGiftiExternalStorageCandidates(candidatePlain, candidateGzip)
            % tryGiftiExternalStorageCandidates  Open exact logical and exact gzip storage candidates in order.
            sourceFile = '';
            sourceIdentity = '';
            storageKind = '';
            plainMsg = '';
            gzipMsg = '';
            candidates = {candidatePlain, candidateGzip};
            kinds = {'plain','gzip'};
            for k = 1:2
                [fid, openMsg] = fopen(candidates{k}, 'rb');
                if fid >= 0
                    fclose(fid);
                    sourceFile = candidates{k};
                    storageKind = kinds{k};
                    info = dir(sourceFile);
                    if ~isempty(info)
                        sourceIdentity = sprintf('%s|%0.0f|%.17g', sourceFile, ...
                            double(info(1).bytes), double(info(1).datenum));
                    end
                    return;
                end
                if k == 1, plainMsg = openMsg; else, gzipMsg = openMsg; end
            end
        end

        function materializeGiftiExternalPayload(sourceFile, destinationFile, storageKind, provenanceFile)
            % materializeGiftiExternalPayload  Materialize one external payload under its exact logical XML name.
            %
            % Purpose and contract:
            %   Plain storage is copied unchanged. Gzip storage is decompressed and placed at
            %   destinationFile, whose relative name is exactly ExternalFileName. This operation changes
            %   storage representation only; payload bytes after decompression and ExternalFileOffset
            %   semantics are preserved.
            %
            % Materialization and performance:
            %   Performs one copy or one gunzip only when the source identity changed. It is an explicit
            %   Probe/import materialization operation and is not safe for interactive navigation paths.
            %
            % Failure semantics:
            %   Copy, decompression, missing gunzip output, replacement, or cache-placement failures are
            %   explicit and identify the original GIFTI provenance source.
            sourceFile = char(string(sourceFile));
            destinationFile = char(string(destinationFile));
            storageKind = char(string(storageKind));
            provenanceFile = char(string(provenanceFile));
            destinationDir = fileparts(destinationFile);
            if strcmp(storageKind,'plain')
                [ok,msg] = copyfile(sourceFile, destinationFile, 'f');
                if ~ok
                    error('NMDataIOSurfaceTools:GiftiExternalPayloadCopyFailed', ...
                        'Could not copy GIFTI external data file %s to the temporary working file %s: %s', sourceFile, destinationFile, msg);
                end
                return;
            end
            if ~strcmp(storageKind,'gzip')
                error('NMDataIOSurfaceTools:GiftiExternalStorageKindInvalid', ...
                    'GIFTI %s uses unsupported external data-file storage type %s.', provenanceFile, storageKind);
            end
            if exist(destinationFile,'file') == 2
                delete(destinationFile);
            end
            try
                outFiles = gunzip(sourceFile, destinationDir);
            catch ME
                cause = MException('NMDataIOSurfaceTools:GiftiExternalPayloadGunzipFailed', ...
                    'Could not decompress external GIFTI data file %s for %s.', sourceFile, provenanceFile);
                cause = addCause(cause, ME);
                throw(cause);
            end
            outFiles = NMDataIOSurfaceTools.asCellstr(outFiles);
            if exist(destinationFile,'file') == 2
                return;
            end
            resolvedOutput = '';
            logicalLeaf = regexprep(sourceFile, '\.gz$', '', 'ignorecase');
            [~,logicalName,logicalExt] = fileparts(logicalLeaf);
            wantedLeaf = [logicalName logicalExt];
            for i = 1:numel(outFiles)
                [~,outName,outExt] = fileparts(outFiles{i});
                if strcmp([outName outExt], wantedLeaf) && exist(outFiles{i},'file') == 2
                    resolvedOutput = outFiles{i};
                    break;
                end
            end
            if isempty(resolvedOutput)
                error('NMDataIOSurfaceTools:GiftiExternalPayloadGunzipOutputMissing', ...
                    'gunzip did not create the expected external GIFTI data file %s for %s.', ...
                    destinationFile, provenanceFile);
            end
            [ok,msg] = movefile(resolvedOutput, destinationFile, 'f');
            if ~ok
                error('NMDataIOSurfaceTools:GiftiExternalPayloadCacheMoveFailed', ...
                    'Could not move the decompressed external GIFTI data into the temporary file %s: %s', destinationFile, msg);
            end
        end

        function txt = decodeXmlAttribute(txt)
            txt = char(string(txt));
            txt = strrep(txt, '&quot;', '"');
            txt = strrep(txt, '&apos;', '''');
            txt = strrep(txt, '&lt;', '<');
            txt = strrep(txt, '&gt;', '>');
            txt = strrep(txt, '&amp;', '&');
        end

        function assertDeclaredHemisphere(declared,inferred,filename)
            if isempty(inferred) || isempty(declared) || any(strcmp(declared,{'auto','unknown','bilateral'})), return; end
            if any(strcmp(declared,{'lh','left'})), wanted = 'left';
            elseif any(strcmp(declared,{'rh','right'})), wanted = 'right';
            else, return;
            end
            if ~strcmp(inferred,wanted)
                error('NMDataIOSurfaceTools:SurfaceGeometryHemisphereMismatch', ...
                    'Configured hemisphere is %s, but the surface filename indicates %s: %s',wanted,inferred,filename);
            end
        end

        function h = hashSurfaceArrays(vertices,faces,scope)
            try
                md = java.security.MessageDigest.getInstance('SHA-256');
                md.update(uint8(char(string(scope))));
                md.update(typecast(uint64(size(vertices,1)),'uint8'));
                md.update(typecast(uint64(size(faces,1)),'uint8'));
                if ~isempty(vertices), md.update(typecast(single(vertices(:)),'uint8')); end
                md.update(typecast(uint32(faces(:)),'uint8'));
                raw = typecast(md.digest(),'uint8');
                h = lower(reshape(dec2hex(raw)',1,[]));
            catch ME
                error('NMDataIOSurfaceTools:SurfaceGeometryHashUnavailable', ...
                    'Could not compute surface geometry SHA-256 identity: %s (%s)',ME.message,ME.identifier);
            end
        end

        function h = hashText(txt)
            try
                md = java.security.MessageDigest.getInstance('SHA-256');
                md.update(uint8(char(string(txt))));
                raw = typecast(md.digest(),'uint8');
                h = lower(reshape(dec2hex(raw)',1,[]));
            catch ME
                error('NMDataIOSurfaceTools:SurfaceGeometryHashUnavailable', ...
                    'Could not compute the surface geometry identity: %s (%s)',ME.message,ME.identifier);
            end
        end

        function tf = hasGiftiMember(g, name)
            % Robustly detect fields/properties on SPM gifti outputs. Some
            % SPM/MATLAB combinations expose gifti data as old-style objects
            % where isstruct/isobject is not informative, but isfield or
            % dot-access still works. This avoids false missing-cdata errors
            % for valid CAT/SPM scalar GIFTI files with file_array payloads.
            tf = false;
            try
                tf = isfield(g, name);
            catch
                tf = false;
            end
            if ~tf
                try
                    tf = isprop(g, name);
                catch
                    tf = false;
                end
            end
            if ~tf
                try
                    g.(name); %#ok<VUNUS>
                    tf = true;
                catch
                    tf = false;
                end
            end
        end

        function data = coerceNumericScalarData(data, filename, formatLabel)
            % SPM's gifti interface can expose scalar payloads as file_array
            % objects when the numerical data are stored in an adjacent .dat
            % file. These are valid scalar maps and must be materialized before
            % vertex-count inspection. Do not treat geometry vertices as scalar
            % data; readGiftiScalar rejects geometry-only GIFTI files earlier.
            if nargin < 3 || isempty(formatLabel), formatLabel = 'surface'; end
            if isnumeric(data)
                data = double(data);
                return;
            end
            try
                data = double(data);
            catch ME1
                try
                    data = double(data(:));
                catch ME2
                    error('NMDataIOSurfaceTools:NonNumericScalar', ...
                        ['Surface scalar data from %s could not be read as numeric values ', ...
                         '(format=%s). Original conversion errors: %s | %s'], ...
                        filename, char(string(formatLabel)), ME1.message, ME2.message);
                end
            end
            if ~isnumeric(data)
                error('NMDataIOSurfaceTools:NonNumericScalar', ...
                    'Surface scalar file did not return numeric data after conversion: %s', filename);
            end
        end

        function txt = asChar(v)
            if isempty(v), txt = ''; return; end
            if ischar(v), txt = strtrim(v); return; end
            if isstring(v), txt = strtrim(char(v)); return; end
            if iscell(v)
                c = NMDataIOSurfaceTools.asCellstr(v);
                txt = strjoin(c(:)', ';');
                return;
            end
            txt = strtrim(char(string(v)));
        end

        function geomFile = surfaceViewerGeometryFile(surfaceFile, geometryFile, rowIndex)
            files = NMDataIOSurfaceTools.splitSurfaceFileList(geometryFile);
            if isempty(files)
                geomFile = surfaceFile;
                return;
            end
            if numel(files) == 1
                geomFile = files{1};
                return;
            end
            if ~isfinite(rowIndex) || rowIndex < 1
                error('NMDataIOSurfaceTools:SurfaceViewerGeometryListNeedsRow', ...
                    'A list of %g surface display meshes was supplied, but the viewer request did not include a valid row index.', numel(files));
            end
            idx = round(rowIndex);
            if idx > numel(files)
                error('NMDataIOSurfaceTools:SurfaceViewerGeometryListTooShort', ...
                    'Surface display mesh list has %g entries, but preview row %g was requested.', numel(files), idx);
            end
            geomFile = files{idx};
        end

        function [vertices, faces] = readGiftiGeometry(filename)
            if exist('gifti','file') == 2 || exist('gifti','class') == 8 || ~isempty(which('gifti'))
                try
                    g = gifti(filename);
                catch ME
                    error('NMDataIOSurfaceTools:GiftiGeometryParseFailed', 'GIFTI geometry parsing failed for %s: %s', filename, ME.message);
                end
            elseif exist('GIIread','file') == 2 || ~isempty(which('GIIread'))
                try
                    g = GIIread(filename);
                catch ME
                    error('NMDataIOSurfaceTools:GiftiGeometryParseFailed', 'GIIread geometry parsing failed for %s: %s', filename, ME.message);
                end
            else
                error('NMDataIOSurfaceTools:MissingGiftiReader', 'GIFTI surface geometry import requires SPM''s gifti interface or GIIread.m on the MATLAB path.');
            end
            if ~NMDataIOSurfaceTools.hasGiftiMember(g, 'vertices') || ~NMDataIOSurfaceTools.hasGiftiMember(g, 'faces')
                error('NMDataIOSurfaceTools:GiftiMissingGeometry', ...
                    ['Selected surface viewer GIFTI file has no vertices/faces geometry: %s. ', ...
                     'Provide a GIFTI mesh or a FreeSurfer surface file such as lh.pial/lh.white/lh.inflated.'], filename);
            end
            try
                vertices = double(g.vertices);
                faces = double(g.faces);
            catch ME
                error('NMDataIOSurfaceTools:GiftiGeometryAccessFailed', 'Could not access GIFTI vertices/faces for %s: %s', filename, ME.message);
            end
        end

        function [vertices, faces] = readFreeSurferGeometry(filename)
            if exist('read_surf','file') == 2 || ~isempty(which('read_surf'))
                try
                    [vertices, faces] = read_surf(filename);
                    return;
                catch ME1
                    if exist('freesurfer_read_surf','file') == 2 || ~isempty(which('freesurfer_read_surf'))
                        try
                            [vertices, faces] = freesurfer_read_surf(filename);
                            return;
                        catch ME2
                            error('NMDataIOSurfaceTools:FreeSurferGeometryReadFailed', ...
                                'Could not read FreeSurfer surface geometry %s. read_surf: %s | freesurfer_read_surf: %s', filename, ME1.message, ME2.message);
                        end
                    end
                    error('NMDataIOSurfaceTools:FreeSurferGeometryReadFailed', 'Could not read FreeSurfer surface geometry %s using read_surf: %s', filename, ME1.message);
                end
            elseif exist('freesurfer_read_surf','file') == 2 || ~isempty(which('freesurfer_read_surf'))
                try
                    [vertices, faces] = freesurfer_read_surf(filename);
                catch ME
                    error('NMDataIOSurfaceTools:FreeSurferGeometryReadFailed', 'Could not read FreeSurfer surface geometry %s using freesurfer_read_surf: %s', filename, ME.message);
                end
            else
                error('NMDataIOSurfaceTools:MissingFreeSurferSurfaceReader', ...
                    ['Surface viewer FreeSurfer geometry requires read_surf.m or freesurfer_read_surf.m on the MATLAB path, ', ...
                     'unless the display mesh is a GIFTI file with vertices/faces.']);
            end
        end

        function [vertices, faces] = coerceSurfaceGeometry(vertices, faces, filename)
            vertices = double(vertices);
            faces = double(faces);
            if isempty(vertices) || size(vertices,2) ~= 3 || ndims(vertices) ~= 2
                error('NMDataIOSurfaceTools:InvalidSurfaceVertices', 'Surface geometry vertices must be an N x 3 numeric array: %s', filename);
            end
            if isempty(faces) || ndims(faces) ~= 2 || ~ismember(size(faces,2), [3 4])
                error('NMDataIOSurfaceTools:InvalidSurfaceFaces', 'Surface geometry faces must be an M x 3 or M x 4 numeric array: %s', filename);
            end
            if size(faces,2) == 4
                faces = [faces(:,[1 2 3]); faces(:,[1 3 4])];
            end
            if any(~isfinite(vertices(:)))
                error('NMDataIOSurfaceTools:InvalidSurfaceVertices', 'Surface geometry vertices contain non-finite coordinates: %s', filename);
            end
            if any(~isfinite(faces(:))) || any(abs(faces(:) - round(faces(:))) > 0)
                error('NMDataIOSurfaceTools:InvalidSurfaceFaces', 'Surface geometry faces contain non-integer or non-finite indices: %s', filename);
            end
            faces = round(faces);
            if isempty(faces)
                error('NMDataIOSurfaceTools:InvalidSurfaceFaces', 'Surface geometry contains no faces: %s', filename);
            end
            minFace = min(faces(:));
            maxFace = max(faces(:));
            nVert = size(vertices,1);
            if minFace >= 1 && maxFace <= nVert
                faces = faces - 1;
            elseif minFace == 0 && maxFace < nVert
                % already zero-based
            else
                error('NMDataIOSurfaceTools:SurfaceFaceIndexOutOfRange', ...
                    'Surface face indices are outside the valid vertex range for %s: min=%g, max=%g, nVertices=%g.', filename, minFace, maxFace, nVert);
            end
            faces = uint32(faces);
            vertices = single(vertices);
        end

        function v = fieldOr(s, field, defaultValue)
            if nargin < 3, defaultValue = []; end
            v = defaultValue;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                v = s.(field);
            end
        end

        function meta = emptyMeta()
            meta = struct('file','','format','','nVertices',NaN,'dataSize',[], ...
                'nFinite',NaN,'nNaN',NaN,'minValue',NaN,'maxValue',NaN);
        end

        function c = asCellstr(v)
            if isempty(v), c = {}; return; end
            if ischar(v)
                if size(v,1) > 1
                    c = cellstr(v);
                else
                    c = cellstr(string(v));
                end
            elseif isstring(v)
                c = cellstr(v(:));
            elseif iscell(v)
                c = cellfun(@(x) char(string(x)), v(:), 'UniformOutput', false);
            else
                c = cellstr(string(v(:)));
            end
            c = c(:);
            c = c(~cellfun(@(x) isempty(strtrim(x)), c));
        end
    end
end

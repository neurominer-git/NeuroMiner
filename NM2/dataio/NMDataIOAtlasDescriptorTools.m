classdef NMDataIOAtlasDescriptorTools
%NMDataIOAtlasDescriptorTools Shared atlas/sidecar descriptor parser for DataIO.
%   This class owns atlas descriptor candidate detection, delimiter/header
%   parsing, ROI/node ID matching, preview generation, and ordered descriptor
%   table extraction. Voxel, surface, and connectivity DataIO code should call
%   this class directly rather than maintaining source-specific sidecar parsers.

    methods (Static)
        function out = detectAtlasDescriptorCandidates(atlasFile)
            % detectAtlasDescriptorCandidates  Find plausible atlas descriptor sidecars near an atlas volume.
            %
            % AtlasFile -> out.
            % It gives atlas/ROI consumers a shared descriptor contract instead of duplicating sidecar parsing logic.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            atlasFile = NMDataIOAtlasDescriptorTools.asChar(atlasFile);
            out = struct('ok',true,'status','none','files',{{}},'message','No accompanying ROI description file was found. NM2 will generate ROI names from atlas IDs unless you select a description file manually.');
            if isempty(atlasFile)
                out.message = 'No atlas file was selected, so NM2 could not look for an accompanying ROI description file.';
                return;
            end
            [d, stem] = NMDataIOAtlasDescriptorTools.stripNiftiExtension(atlasFile);
            if isempty(d), d = pwd; end
            if exist(d,'dir') ~= 7
                out.message = sprintf('Atlas directory does not exist: %s', d);
                return;
            end
            suffixes = {'','_labels','_Labels','_labeltable','_LabelTable','_lut','_LUT','_regions','_Regions'};
            exts = {'.csv','.tsv','.txt','.labels'};
            files = {};
            stemVariants = {stem};
            stemNoTrailingDigits = regexprep(stem, '\d+$', '');
            if ~isempty(stemNoTrailingDigits) && ~strcmpi(stemNoTrailingDigits, stem)
                stemVariants{end+1} = stemNoTrailingDigits; %#ok<AGROW>
            end
            stemVariants = unique(stemVariants, 'stable');
            for sIdx = 1:numel(stemVariants)
                sStem = stemVariants{sIdx};
                for i = 1:numel(suffixes)
                    for j = 1:numel(exts)
                        f = fullfile(d, [sStem suffixes{i} exts{j}]);
                        if exist(f,'file') == 2, files{end+1} = f; end %#ok<AGROW>
                    end
                end
            end
            % Case-insensitive shallow scan for common descriptor sidecar names.
            % The trailing-digit fallback is intentional: CAT12 ships aal3.nii with aal.csv.
            dd = dir(d);
            lowStems = lower(stemVariants);
            for i = 1:numel(dd)
                if dd(i).isdir, continue; end
                [~,nm,ex] = fileparts(dd(i).name);
                if ~ismember(lower(ex), {'.csv','.tsv','.txt','.labels'}), continue; end
                lnm = lower(nm);
                for sIdx = 1:numel(lowStems)
                    lowStem = lowStems{sIdx};
                    if strcmp(lnm, lowStem) || startsWith(lnm, [lowStem '_label']) || startsWith(lnm, [lowStem '_lut']) || startsWith(lnm, [lowStem '_region'])
                        files{end+1} = fullfile(d, dd(i).name); %#ok<AGROW>
                        break;
                    end
                end
            end
            files = unique(files, 'stable');
            out.files = files(:)';
            if isempty(files)
                out.status = 'none';
                out.message = 'No accompanying ROI description file was found. NM2 will generate ROI names from the atlas IDs unless you select an ROI description file manually.';
            elseif numel(files) == 1
                out.status = 'single';
                out.message = sprintf('ROI description file detected automatically: %s. NM2 can inspect this file automatically.', files{1});
            else
                out.status = 'multiple';
                out.message = sprintf('NM2 found %g possible ROI description files. Select the file you want to use.', numel(files));
            end
        end

        function out = inspectAtlasDescriptor(atlasFile, descriptorFile, opts)
            % inspectAtlasDescriptor  Inspect a descriptor candidate and report whether it can label atlas ROI IDs.
            %
            % Consumes atlasFile, descriptorFile, opts; returns out.
            % It gives atlas/ROI consumers a shared descriptor contract instead of duplicating sidecar parsing logic.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 3 || isempty(opts), opts = struct(); end
            parsed = NMDataIOAtlasDescriptorTools.parseDescriptor(atlasFile, descriptorFile, opts);
            out = parsed.out;
        end

        function out = resolveDescriptorTable(atlasFile, descriptorFile, opts)
            % resolveDescriptorTable  Read, parse, and match a descriptor table against atlas ROI IDs.
            %
            % Consumes atlasFile, descriptorFile, opts; returns out.
            % It gives atlas/ROI consumers a shared descriptor contract instead of duplicating sidecar parsing logic.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 3 || isempty(opts), opts = struct(); end
            parsed = NMDataIOAtlasDescriptorTools.parseDescriptor(atlasFile, descriptorFile, opts);
            out = parsed.out;
            out.descriptorTable = parsed.table;
            out.orderedTable = table();
            out.orderedIDs = [];
            out.orderedNames = {};
            if isempty(parsed.table) || isempty(parsed.atlasIDs) || isempty(out.defaultIDColumn)
                return;
            end
            idIdx = find(strcmp(parsed.columns, out.defaultIDColumn), 1);
            if isempty(idIdx), return; end
            ids = NMDataIOAtlasDescriptorTools.columnNumeric(parsed.data(:,idIdx));
            [matched, loc] = ismember(double(parsed.atlasIDs(:)), ids);
            if any(matched)
                out.orderedTable = parsed.table(loc(matched), :);
                out.orderedIDs = double(parsed.atlasIDs(matched));
                if isfield(out,'roiNamesByAtlasOrder') && numel(out.roiNamesByAtlasOrder) == numel(parsed.atlasIDs)
                    out.orderedNames = out.roiNamesByAtlasOrder(matched);
                end
            end
        end

        function out = inspectNodeDescriptor(descriptorFile, opts)
            % inspectNodeDescriptor  Inspect an ROI/node sidecar independently of an atlas image.
            %
            % The sidecar row order is authoritative for connectivity node order.
            % Atlas images are optional localization fallbacks and are deliberately
            % excluded from this parser contract.
            if nargin < 2 || isempty(opts), opts = struct(); end
            parsed = NMDataIOAtlasDescriptorTools.parseDescriptor('', descriptorFile, opts);
            out = parsed.out;
            out.warnings = {};
            out.descriptorTable = parsed.table;
            out.nRows = height(parsed.table);
            out.nodeIDs = [];
            out.nodeNames = {};
            out.nodeCoordinates = nan(out.nRows,3);
            out.coordinateSource = repmat({''}, out.nRows, 1);
            out.candidateXColumns = NMDataIOAtlasDescriptorTools.rankCoordinateColumns(parsed.columns, 'x');
            out.candidateYColumns = NMDataIOAtlasDescriptorTools.rankCoordinateColumns(parsed.columns, 'y');
            out.candidateZColumns = NMDataIOAtlasDescriptorTools.rankCoordinateColumns(parsed.columns, 'z');
            out.defaultXColumn = NMDataIOAtlasDescriptorTools.requestedOrFirst(opts, 'xColumn', out.candidateXColumns);
            out.defaultYColumn = NMDataIOAtlasDescriptorTools.requestedOrFirst(opts, 'yColumn', out.candidateYColumns);
            out.defaultZColumn = NMDataIOAtlasDescriptorTools.requestedOrFirst(opts, 'zColumn', out.candidateZColumns);
            out.coordinateSpace = upper(NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'coordinateSpace','MNI')));
            out.coordinateUnits = lower(NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'coordinateUnits','mm')));
            out.coordinateSummary = struct('status','none','nRows',double(out.nRows),'nValid',0,'invalidRows',[], ...
                'xColumn',out.defaultXColumn,'yColumn',out.defaultYColumn,'zColumn',out.defaultZColumn, ...
                'space',out.coordinateSpace,'units',out.coordinateUnits);

            if isempty(parsed.table) || isempty(parsed.columns)
                out.ok = false;
                return;
            end
            if ~strcmp(out.coordinateSpace,'MNI') || ~strcmp(out.coordinateUnits,'mm')
                out.ok = false;
                out.message = 'Connectivity node coordinates currently require MNI space in millimetres.';
                return;
            end
            idColumn = NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'idColumn',out.defaultIDColumn));
            nameColumn = NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'nameColumn',out.defaultNameColumn));
            if isempty(idColumn), idColumn = out.defaultIDColumn; end
            if isempty(nameColumn), nameColumn = out.defaultNameColumn; end
            out.defaultIDColumn = idColumn;
            out.defaultNameColumn = nameColumn;
            idIdx = find(strcmp(parsed.columns, idColumn), 1);
            nameIdx = find(strcmp(parsed.columns, nameColumn), 1);
            if isempty(idIdx) || isempty(nameIdx)
                out.ok = false;
                out.message = 'The ROI description file requires identifiable ROI-ID and ROI-name columns.';
                return;
            end
            ids = NMDataIOAtlasDescriptorTools.columnNumeric(parsed.data(:,idIdx));
            names = NMDataIOAtlasDescriptorTools.asCellstr(parsed.data(:,nameIdx));
            names = names(:);
            if numel(ids) ~= out.nRows || any(~isfinite(ids)) || any(abs(ids-round(ids)) > 1e-6)
                out.ok = false;
                out.message = sprintf('ROI-ID column %s must contain one finite integer ID per ROI row.', idColumn);
                return;
            end
            ids = round(double(ids(:)));
            if numel(unique(ids)) ~= numel(ids)
                out.ok = false;
                out.message = sprintf('ROI-ID column %s contains duplicate IDs.', idColumn);
                return;
            end
            if numel(names) ~= out.nRows
                out.ok = false;
                out.message = sprintf('ROI-name column %s must contain one name per ROI row.', nameColumn);
                return;
            end
            emptyName = cellfun(@(x)isempty(strtrim(x)), names);
            for i = find(emptyName(:)')
                names{i} = sprintf('ROI_%g', ids(i));
            end
            out.generatedNameRows = find(emptyName)';
            normNames = lower(strtrim(string(names)));
            if numel(unique(normNames)) ~= numel(normNames)
                out.ok = false;
                out.message = sprintf('ROI-name column %s contains duplicate names after normalization.', nameColumn);
                return;
            end
            out.nodeIDs = ids(:)';
            out.nodeNames = names(:)';

            xyzColumns = {out.defaultXColumn,out.defaultYColumn,out.defaultZColumn};
            if all(~cellfun(@isempty, xyzColumns)) && numel(unique(xyzColumns)) ~= 3
                out.ok = false;
                out.message = 'MNI X, Y and Z must use three different columns in the ROI description file.';
                return;
            end
            if all(~cellfun(@isempty, xyzColumns))
                xyzIdx = zeros(1,3);
                for k = 1:3
                    hit = find(strcmp(parsed.columns, xyzColumns{k}), 1);
                    if ~isempty(hit), xyzIdx(k) = hit; end
                end
                if all(xyzIdx > 0)
                    xyz = nan(out.nRows,3);
                    for k = 1:3
                        xyz(:,k) = NMDataIOAtlasDescriptorTools.columnNumeric(parsed.data(:,xyzIdx(k)));
                    end
                    valid = all(isfinite(xyz),2) & all(abs(xyz) <= 250,2);
                    out.nodeCoordinates = xyz;
                    out.coordinateSource(valid) = repmat({'sidecar_mni'},nnz(valid),1);
                    out.coordinateSummary.nValid = double(nnz(valid));
                    out.coordinateSummary.invalidRows = find(~valid)';
                    if all(valid)
                        out.coordinateSummary.status = 'full';
                    elseif any(valid)
                        out.coordinateSummary.status = 'partial';
                    else
                        out.coordinateSummary.status = 'none';
                    end
                end
            end
            out.ok = true;
            generatedNote = '';
            if isfield(out,'generatedNameRows') && ~isempty(out.generatedNameRows)
                generatedNote = sprintf(' Empty ROI names were replaced deterministically by ROI_<ID> for %g row(s).', numel(out.generatedNameRows));
            end
            if strcmp(out.coordinateSummary.status,'full')
                out.message = [sprintf('ROI description file read successfully: %g nodes; valid MNI coordinates found for %g/%g nodes. No atlas image is required.', out.nRows, out.coordinateSummary.nValid, out.nRows) generatedNote];
            elseif strcmp(out.coordinateSummary.status,'partial')
                out.message = [sprintf('ROI description file read successfully: %g nodes; valid MNI coordinates found for %g/%g nodes. A labelled atlas image is required to locate the remaining nodes.', out.nRows, out.coordinateSummary.nValid, out.nRows) generatedNote];
            else
                out.message = [sprintf('ROI description file read successfully: %g nodes, but no complete MNI coordinates were found. A labelled atlas image is required to locate the nodes.', out.nRows) generatedNote];
            end
        end

        function out = resolveNodeDescriptorTable(descriptorFile, opts)
            % resolveNodeDescriptorTable  Resolve sidecar rows in their original node order.
            if nargin < 2 || isempty(opts), opts = struct(); end
            out = NMDataIOAtlasDescriptorTools.inspectNodeDescriptor(descriptorFile, opts);
            out.orderedTable = out.descriptorTable;
            out.orderedIDs = out.nodeIDs;
            out.orderedNames = out.nodeNames;
        end

        function out = resolveROIFeatureDescriptor(descriptorFile, opts)
            % resolveROIFeatureDescriptor  Resolve an explicit ROI-column sidecar without semantic guessing.
            %
            % idColumn and nameColumn are mandatory. hemisphereColumn is optional
            % for volumetric atlases and mandatory when duplicate numeric ROI IDs
            % are disambiguated by hemisphere. MNI coordinate columns are used
            % only when all three are explicitly named. Sidecar row order is the
            % authoritative data-column order.
            if nargin < 2 || isempty(opts), opts = struct(); end
            parsed = NMDataIOAtlasDescriptorTools.parseDescriptor('', descriptorFile, opts);
            out = struct('ok',false,'message','','descriptorFile',NMDataIOAtlasDescriptorTools.asChar(descriptorFile), ...
                'nRows',height(parsed.table),'roiIDs',[],'roiNames',{{}},'hemisphere',{{}}, ...
                'identityKeys',{{}},'mniCoordinates',nan(height(parsed.table),3),'descriptorTable',parsed.table);
            if isempty(parsed.table) || isempty(parsed.columns)
                out.message = 'The ROI description file could not be read as a non-empty table.';
                return;
            end
            idColumn = NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'idColumn',''));
            nameColumn = NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'nameColumn',''));
            if isempty(idColumn) || isempty(nameColumn)
                out.message = 'Select the ROI-ID and ROI-name columns in the ROI description file.';
                return;
            end
            idIdx = find(strcmp(parsed.columns,idColumn),1);
            nameIdx = find(strcmp(parsed.columns,nameColumn),1);
            if isempty(idIdx) || isempty(nameIdx)
                out.message = sprintf('The selected ROI description columns were not found: ID=%s, name=%s.',idColumn,nameColumn);
                return;
            end
            ids = NMDataIOAtlasDescriptorTools.columnNumeric(parsed.data(:,idIdx));
            names = NMDataIOAtlasDescriptorTools.asCellstr(parsed.data(:,nameIdx));
            if numel(ids) ~= out.nRows || any(~isfinite(ids)) || any(abs(ids-round(ids)) > 1e-6) || any(ids == 0)
                out.message = sprintf('ROI-ID column %s must contain one finite non-zero integer ID per ROI row.',idColumn);
                return;
            end
            ids = round(double(ids(:)));
            names = names(:);
            if numel(names) ~= out.nRows || any(cellfun(@(x)isempty(strtrim(x)),names))
                out.message = sprintf('ROI-name column %s must contain one non-empty name per ROI row.',nameColumn);
                return;
            end
            hemiColumn = NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'hemisphereColumn',''));
            hemi = repmat({''},out.nRows,1);
            if ~isempty(hemiColumn)
                hemiIdx = find(strcmp(parsed.columns,hemiColumn),1);
                if isempty(hemiIdx)
                    out.message = sprintf('ROI hemisphere column was not found exactly: %s.',hemiColumn);
                    return;
                end
                rawHemi = NMDataIOAtlasDescriptorTools.asCellstr(parsed.data(:,hemiIdx));
                for ii=1:numel(rawHemi)
                    token = lower(strtrim(rawHemi{ii}));
                    if any(strcmp(token,{'l','left','lh'})), hemi{ii}='lh';
                    elseif any(strcmp(token,{'r','right','rh'})), hemi{ii}='rh';
                    else
                        out.message = sprintf('ROI hemisphere row %g is not one of lh/left/l or rh/right/r.',ii);
                        return;
                    end
                end
            end
            keys = cell(out.nRows,1);
            for ii=1:out.nRows
                if isempty(hemi{ii}), keys{ii}=sprintf('volume:%0.15g',ids(ii));
                else, keys{ii}=sprintf('%s:%0.15g',hemi{ii},ids(ii)); end
            end
            if numel(unique(keys)) ~= out.nRows
                out.message = 'The ROI description file contains duplicate ROI column identities.';
                return;
            end
            xyzNames = {NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'xColumn','')), ...
                NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'yColumn','')), ...
                NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'zColumn',''))};
            if any(~cellfun(@isempty,xyzNames)) && ~all(~cellfun(@isempty,xyzNames))
                out.message = 'MNI coordinates require X, Y and Z columns to be selected together in the ROI description file.';
                return;
            end
            coords = nan(out.nRows,3);
            if all(~cellfun(@isempty,xyzNames))
                if numel(unique(xyzNames)) ~= 3
                    out.message = 'MNI X, Y and Z must use three different columns in the ROI description file.';
                    return;
                end
                for kk=1:3
                    idx = find(strcmp(parsed.columns,xyzNames{kk}),1);
                    if isempty(idx)
                        out.message = sprintf('MNI coordinate column was not found exactly: %s.',xyzNames{kk});
                        return;
                    end
                    coords(:,kk)=NMDataIOAtlasDescriptorTools.columnNumeric(parsed.data(:,idx));
                end
                if any(~isfinite(coords(:)))
                    out.message = 'Explicit MNI coordinate columns must contain finite values for every ROI row.';
                    return;
                end
            end
            out.roiIDs = ids(:)';
            out.roiNames = names(:)';
            out.hemisphere = hemi(:)';
            out.identityKeys = keys(:)';
            out.mniCoordinates = coords;
            out.ok = true;
            out.message = sprintf('Read %g ROI description row(s) in the same order as the data columns.',out.nRows);
        end

        function out = atlasNodeCoordinates(atlasFile, requestedIDs, progressTask, progressRange)
            % atlasNodeCoordinates  Validate a labelled atlas and derive world-mm ROI centroids.
            %
            % Purpose:
            %   Materialize one discrete volumetric atlas, enumerate its non-background labels, and
            %   derive centroids for requested ROI IDs. This is a source-validation/import utility,
            %   not an interactive visualization lookup.
            %
            % Authority and flow:
            %   The atlas image is the spatial-reference authority for volumetric ROI provenance.
            %   Callers consume the returned atlas IDs/centroids; interactive consumers must use
            %   already validated provenance rather than calling this method again.
            %
            % Materialization and performance:
            %   YES. Reads the complete atlas volume once, groups non-background voxels by label,
            %   and computes all label centroids in one aggregation pass. Cost is O(number of atlas
            %   voxels) plus grouped reduction and O(number of requested labels); the atlas is not
            %   rescanned once per ROI. This method must not execute during subject switching,
            %   viewer navigation, or UI teardown.
            %
            % Failure semantics:
            %   Missing files, unavailable SPM readers, non-discrete labels, and unreadable atlas
            %   geometry return out.ok=false with a specific message. No atlas identity is guessed.
            %
            % Side effects:
            %   May use the existing NIfTI resolution utility; does not mutate NM or viewer state.
            %   Optional progressTask/progressRange arguments report atlas-read and centroid progress only.
            if nargin < 2, requestedIDs = []; end
            if nargin < 3 || ~isstruct(progressTask), progressTask=NMProgressTools.emptyTaskForLocalUse(); end
            if nargin < 4 || numel(progressRange)~=2, progressRange=[progressTask.phaseStart progressTask.phaseEnd]; end
            rangeStart=double(progressRange(1)); rangeEnd=double(progressRange(2)); rangeSpan=max(0,rangeEnd-rangeStart);
            out = struct('ok',false,'atlasFile',NMDataIOAtlasDescriptorTools.asChar(atlasFile), ...
                'atlasIDs',[],'requestedIDs',double(requestedIDs(:)'),'matchedMask',false(size(requestedIDs(:)')), ...
                'coordinates',nan(numel(requestedIDs),3),'referenceDim',[],'referenceMat',[], ...
                'spatialIdentity','','message','Atlas coordinates not resolved.');
            atlasFile = out.atlasFile;
            if isempty(atlasFile) || exist(atlasFile,'file') ~= 2
                out.message = sprintf('Labelled atlas image does not exist: %s', atlasFile);
                return;
            end
            try
                progressTask=NMProgressTools.phase(progressTask,'roi_atlas_resolve',rangeStart,rangeStart+0.15*rangeSpan, ...
                    'Resolving labelled ROI atlas for SPM.');
                if ~NMDataIOAtlasDescriptorTools.isFunctionAvailable('spm_vol') || ~NMDataIOAtlasDescriptorTools.isFunctionAvailable('spm_read_vols')
                    out.message = 'SPM volume readers are required to inspect labelled atlas images.';
                    return;
                end
                [spmFiles, messages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({atlasFile}, 'connectivity.atlasFile', true);
                if NMDataIOMessageTools.hasFatal(messages)
                    out.message = 'The labelled atlas image could not be resolved for SPM.';
                    return;
                end
                progressTask=NMProgressTools.phase(progressTask,'roi_atlas_header',rangeStart+0.15*rangeSpan,rangeStart+0.25*rangeSpan, ...
                    'Reading labelled ROI atlas header.');
                V = spm_vol(spmFiles{1});
                if numel(V) ~= 1
                    out.message = 'Connectivity atlas fallback requires a single-volume discrete label image.';
                    return;
                end
                progressTask=NMProgressTools.phase(progressTask,'roi_atlas_volume',rangeStart+0.25*rangeSpan,rangeStart+0.55*rangeSpan, ...
                    'Reading labelled ROI atlas volume.');
                A = spm_read_vols(V);
                out.referenceDim = double(V.dim(1:3));
                out.referenceMat = double(V.mat);
                progressTask=NMProgressTools.phase(progressTask,'roi_atlas_labels',rangeStart+0.55*rangeSpan,rangeStart+0.65*rangeSpan, ...
                    'Enumerating labelled ROI atlas identities.');
                atlasSize = size(A);
                atlasSize(end+1:3) = 1;
                flatAtlas = double(A(:));
                supportMask = isfinite(flatAtlas) & flatAtlas ~= 0;
                supportValues = flatAtlas(supportMask);
                [rawAtlasIDs,~,supportGroup] = unique(supportValues);
                atlasIDs = rawAtlasIDs(:)';
                if any(abs(atlasIDs - round(atlasIDs)) > 1e-6)
                    out.message = 'Connectivity atlas fallback must be a discrete integer-labelled image; non-integer non-background values were found.';
                    return;
                end
                atlasIDs = round(atlasIDs);
                atlasIdentityVolume = round(double(A));
                atlasIdentityVolume(~isfinite(atlasIdentityVolume)) = 0;
                contentHash = NMImagingContentIdentity.hashArray(atlasIdentityVolume,'double');
                out.spatialIdentity = NMImagingContentIdentity.hashText(strjoin({ ...
                    ['content=' contentHash],['dim=' mat2str(out.referenceDim,17)], ...
                    ['mat=' mat2str(out.referenceMat,17)]},'|'));
                clear flatAtlas supportValues A atlasIdentityVolume;
                out.atlasIDs = atlasIDs;
                if isempty(requestedIDs), requestedIDs = atlasIDs; end
                requestedIDs = double(requestedIDs(:)');
                out.requestedIDs = requestedIDs;
                out.coordinates = nan(numel(requestedIDs),3);
                [matched,atlasLoc] = ismember(requestedIDs, atlasIDs);
                out.matchedMask = matched;
                matchedIndex=find(matched);
                progressTask=NMProgressTools.phase(progressTask,'roi_atlas_centroids',rangeStart+0.65*rangeSpan,rangeEnd, ...
                    'Computing ROI atlas centroids.');
                if ~isempty(matchedIndex)
                    supportIndex = find(supportMask);
                    clear supportMask;
                    nAtlasIDs = numel(rawAtlasIDs);
                    counts = accumarray(supportGroup,1,[nAtlasIDs 1],@sum,0);
                    voxelLinear = double(supportIndex) - 1;
                    clear supportIndex;
                    sumVX = accumarray(supportGroup,mod(voxelLinear,atlasSize(1))+1,[nAtlasIDs 1],@sum,0);
                    voxelLinear = floor(voxelLinear./atlasSize(1));
                    sumVY = accumarray(supportGroup,mod(voxelLinear,atlasSize(2))+1,[nAtlasIDs 1],@sum,0);
                    voxelLinear = floor(voxelLinear./atlasSize(2));
                    sumVZ = accumarray(supportGroup,voxelLinear+1,[nAtlasIDs 1],@sum,0);
                    centroidVoxels = [sumVX./counts sumVY./counts sumVZ./counts ones(nAtlasIDs,1)];
                    atlasWorld = (V.mat * centroidVoxels')';
                    atlasCoordinates = atlasWorld(:,1:3);
                    for kk=1:numel(matchedIndex)
                        i=matchedIndex(kk);
                        atlasRow=atlasLoc(i);
                        % Preserve the existing exact-label centroid semantics after the
                        % integer-tolerance validation above.
                        if rawAtlasIDs(atlasRow) == requestedIDs(i)
                            out.coordinates(i,:) = atlasCoordinates(atlasRow,:);
                        end
                        progressTask=NMProgressTools.step(progressTask,kk,max(1,numel(matchedIndex)), ...
                            sprintf('Computing ROI atlas centroid %g of %g.',kk,numel(matchedIndex)),true);
                    end
                end
                out.ok = any(matched);
                out.message = sprintf('Labelled atlas matched %g/%g requested ROI IDs.', nnz(matched), numel(requestedIDs));
            catch ME
                out.ok = false;
                out.message = sprintf('Could not derive labelled-atlas ROI coordinates: %s', ME.message);
            end
        end

    end

    methods (Static, Access = private)
        function parsed = parseDescriptor(atlasFile, descriptorFile, opts)
            atlasFile = NMDataIOAtlasDescriptorTools.asChar(atlasFile);
            descriptorFile = NMDataIOAtlasDescriptorTools.asChar(descriptorFile);
            out = struct('ok',false,'file',descriptorFile,'atlasFile',atlasFile,'delimiter','auto','hasHeader',false, ...
                'columns',{{}},'candidateIDColumns',{{}},'candidateNameColumns',{{}},'defaultIDColumn','', ...
                'defaultNameColumn','','previewRows',{{}},'matchSummary',[], 'roiNamesByAtlasOrder',{{}}, ...
                'roiNameSource','sidecar_file','message','ROI description file not inspected.','warnings',{{}});
            parsed = struct('out',out,'table',table(),'columns',{{}},'data',{{}},'atlasIDs',[]);
            if isempty(descriptorFile) || exist(descriptorFile,'file') ~= 2
                out.message = sprintf('ROI description file does not exist: %s', descriptorFile);
                out.matchSummary = struct('status','none','nAtlasIDs',0,'nMatched',0);
                parsed.out = out;
                return;
            end
            lines = NMDataIOAtlasDescriptorTools.readDescriptorLines(descriptorFile);
            if isempty(lines)
                out.message = sprintf('ROI description file is empty or contains only comments: %s', descriptorFile);
                out.matchSummary = struct('status','none','nAtlasIDs',0,'nMatched',0);
                parsed.out = out;
                return;
            end
            delimiter = NMDataIOAtlasDescriptorTools.normalizeDelimiter(NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'delimiter','auto')));
            if isempty(delimiter), delimiter = 'auto'; end
            if strcmpi(delimiter,'auto')
                delimiter = NMDataIOAtlasDescriptorTools.detectDescriptorDelimiter(lines);
            end
            rows = NMDataIOAtlasDescriptorTools.splitDescriptorLines(lines, delimiter);
            if isempty(rows)
                out.message = sprintf('ROI description file could not be read using delimiter ''%s''.', delimiter);
                out.matchSummary = struct('status','none','nAtlasIDs',0,'nMatched',0);
                parsed.out = out;
                return;
            end
            hasHeaderOpt = NMDataIOAtlasDescriptorTools.fieldOr(opts,'hasHeader','auto');
            hasHeader = NMDataIOAtlasDescriptorTools.inferDescriptorHeader(rows, hasHeaderOpt);
            if hasHeader
                columns = NMDataIOAtlasDescriptorTools.makeUniqueColumnNames(rows{1});
                dataRows = rows(2:end);
            else
                ncol = max(cellfun(@numel, rows));
                columns = arrayfun(@(i)sprintf('Column%d', i), 1:ncol, 'UniformOutput', false);
                dataRows = rows;
            end
            data = NMDataIOAtlasDescriptorTools.rectangularizeRows(dataRows, numel(columns));
            atlasIDs = NMDataIOAtlasDescriptorTools.numericVector(NMDataIOAtlasDescriptorTools.fieldOr(opts,'roiIDs',[]));
            if isempty(atlasIDs) && ~isempty(atlasFile)
                atlasIDs = NMDataIOAtlasDescriptorTools.atlasIDsFromFile(atlasFile);
            end
            idScores = NMDataIOAtlasDescriptorTools.rankDescriptorIDColumns(data, columns, atlasIDs);
            nameScores = NMDataIOAtlasDescriptorTools.rankDescriptorNameColumns(data, columns);
            out.delimiter = delimiter;
            out.hasHeader = logical(hasHeader);
            out.columns = columns(:)';
            out.candidateIDColumns = {idScores.name};
            out.candidateNameColumns = {nameScores.name};
            reqID = NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'idColumn',''));
            reqName = NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,'nameColumn',''));
            if isempty(reqID) && ~isempty(idScores), reqID = idScores(1).name; end
            if isempty(reqName) && ~isempty(nameScores), reqName = nameScores(1).name; end
            out.defaultIDColumn = reqID;
            out.defaultNameColumn = reqName;
            out.previewRows = NMDataIOAtlasDescriptorTools.previewDescriptorRows(data, columns, 8);
            [matchSummary, namesByOrder] = NMDataIOAtlasDescriptorTools.matchDescriptorToAtlas(data, columns, reqID, reqName, atlasIDs);
            out.matchSummary = matchSummary;
            out.roiNamesByAtlasOrder = namesByOrder(:);
            out.ok = ~strcmp(matchSummary.status,'none');
            if strcmp(matchSummary.status,'full')
                out.message = sprintf('ROI description file read successfully: delimiter=%s, header=%s, ROI-ID column=%s, ROI-name column=%s; matched %g/%g atlas labels.', ...
                    delimiter, NMDataIOAtlasDescriptorTools.yesNo(hasHeader), reqID, reqName, matchSummary.nMatched, matchSummary.nAtlasIDs);
            elseif strcmp(matchSummary.status,'partial')
                out.message = sprintf('ROI description file was read with warnings: ROI-ID column=%s, ROI-name column=%s; matched %g/%g atlas labels. Missing atlas IDs: %s.', ...
                    reqID, reqName, matchSummary.nMatched, matchSummary.nAtlasIDs, NMDataIOAtlasDescriptorTools.shortNumericList(matchSummary.missingAtlasIDs, 10));
                out.warnings = {out.message};
            else
                out.message = sprintf('ROI-ID column %s does not contain IDs present in the atlas. Select another ID column or another ROI description file.', reqID);
                out.warnings = {out.message};
            end
            parsed.out = out;
            parsed.table = NMDataIOAtlasDescriptorTools.cellDataToTable(data, columns);
            parsed.columns = columns;
            parsed.data = data;
            parsed.atlasIDs = atlasIDs;
        end

        function lines = readDescriptorLines(path)
            txt = fileread(path);
            raw = regexp(txt, '\r\n|\n|\r', 'split');
            lines = {};
            for i = 1:numel(raw)
                t = strtrim(raw{i});
                if isempty(t), continue; end
                if startsWith(t, '#') || startsWith(t, '%') || startsWith(t, '//'), continue; end
                lines{end+1} = raw{i}; %#ok<AGROW>
            end
        end

        function delim = detectDescriptorDelimiter(lines)
            candidates = {'tab','comma','semicolon','pipe','whitespace'};
            bestScore = -Inf;
            delim = 'whitespace';
            for i = 1:numel(candidates)
                rows = NMDataIOAtlasDescriptorTools.splitDescriptorLines(lines, candidates{i});
                if isempty(rows), continue; end
                n = cellfun(@numel, rows);
                score = median(double(n)) + 0.5 * sum(n > 1) - 0.1 * numel(unique(n));
                if score > bestScore
                    bestScore = score;
                    delim = candidates{i};
                end
            end
        end

        function rows = splitDescriptorLines(lines, delimiter)
            delimiter = NMDataIOAtlasDescriptorTools.normalizeDelimiter(delimiter);
            rows = cell(numel(lines),1);
            for i = 1:numel(lines)
                line = strtrim(lines{i});
                switch delimiter
                    case {'tab','\t'}
                        parts = regexp(line, '\t', 'split');
                    case {'comma',','}
                        parts = regexp(line, ',', 'split');
                    case {'semicolon',';'}
                        parts = regexp(line, ';', 'split');
                    case {'pipe','|'}
                        parts = regexp(line, '\|', 'split');
                    otherwise
                        parts = regexp(line, '\s+', 'split');
                end
                parts = cellfun(@strtrim, parts, 'UniformOutput', false);
                rows{i} = parts;
            end
            rows = rows(~cellfun(@isempty, rows));
        end

        function delimiter = normalizeDelimiter(delimiter)
            delimiter = lower(NMDataIOAtlasDescriptorTools.asChar(delimiter));
            switch delimiter
                case {'semi',';' }
                    delimiter = 'semicolon';
                case {'space','spaces','white','ws'}
                    delimiter = 'whitespace';
                case {'bar'}
                    delimiter = 'pipe';
                case {'\t'}
                    delimiter = 'tab';
                case {','}
                    delimiter = 'comma';
                case {'|'}
                    delimiter = 'pipe';
            end
        end

        function tf = inferDescriptorHeader(rows, opt)
            optTxt = lower(NMDataIOAtlasDescriptorTools.asChar(opt));
            if islogical(opt) || isnumeric(opt)
                tf = logical(opt); return;
            end
            if any(strcmp(optTxt, {'yes','true','1','header'})), tf = true; return; end
            if any(strcmp(optTxt, {'no','false','0','none'})), tf = false; return; end
            if numel(rows) < 2
                tf = false; return;
            end
            r1 = rows{1}; r2 = rows{2};
            n = min(numel(r1), numel(r2));
            if n == 0, tf = false; return; end
            n1 = sum(cellfun(@(x)isfinite(str2double(x)), r1(1:n)));
            n2 = sum(cellfun(@(x)isfinite(str2double(x)), r2(1:n)));
            tf = n1 < n2 || (n1 == 0 && n2 > 0);
        end

        function columns = makeUniqueColumnNames(raw)
            raw = NMDataIOAtlasDescriptorTools.asCellstr(raw);
            columns = cell(numel(raw),1);
            used = containers.Map('KeyType','char','ValueType','double');
            for i = 1:numel(raw)
                nm = strtrim(raw{i});
                if isempty(nm), nm = sprintf('Column%d', i); end
                nm = regexprep(nm, '[^A-Za-z0-9_]', '_');
                if isempty(regexp(nm, '^[A-Za-z]', 'once')), nm = ['Column_' nm]; end
                key = lower(nm);
                if isKey(used,key)
                    used(key) = used(key) + 1;
                    nm = sprintf('%s_%d', nm, used(key));
                else
                    used(key) = 1;
                end
                columns{i} = nm;
            end
        end

        function data = rectangularizeRows(rows, ncol)
            data = cell(numel(rows), ncol);
            data(:) = {''};
            for i = 1:numel(rows)
                r = rows{i};
                n = min(numel(r), ncol);
                if n > 0, data(i,1:n) = r(1:n); end
            end
        end

        function scores = rankDescriptorIDColumns(data, columns, atlasIDs)
            if isempty(columns), scores = struct('name',{},'score',{}); return; end
            scores = repmat(struct('name','','score',-Inf), 1, numel(columns));
            atlasIDs = double(atlasIDs(:));
            for j = 1:numel(columns)
                vals = NMDataIOAtlasDescriptorTools.columnNumeric(data(:,j));
                finite = isfinite(vals);
                integerLike = finite & abs(vals - round(vals)) < 1e-6;
                nameScore = double(~isempty(regexp(lower(columns{j}), '(^|_)(id|roi|roi_id|index|idx|label|value|number)(_|$)', 'once'))) * 10;
                numericScore = 5 * mean(integerLike | finite);
                overlapScore = 0;
                if ~isempty(atlasIDs) && any(finite)
                    overlapScore = 20 * numel(intersect(double(vals(finite)), atlasIDs)) / max(1, numel(unique(atlasIDs)));
                end
                scores(j).name = columns{j};
                scores(j).score = nameScore + numericScore + overlapScore;
            end
            [~,ord] = sort([scores.score], 'descend');
            scores = scores(ord);
        end

        function scores = rankDescriptorNameColumns(data, columns)
            if isempty(columns), scores = struct('name',{},'score',{}); return; end
            scores = repmat(struct('name','','score',-Inf), 1, numel(columns));
            for j = 1:numel(columns)
                vals = data(:,j);
                numeric = NMDataIOAtlasDescriptorTools.columnNumeric(vals);
                textFrac = mean(~cellfun(@isempty, vals) & ~isfinite(numeric));
                colLower = lower(columns{j});
                if ~isempty(regexp(colLower, '(^|_)(name|fullname|full_name|shortname|short_name)(_|$)', 'once'))
                    nameScore = 20;
                elseif ~isempty(regexp(colLower, '(^|_)(label|region|description|structure|area)(_|$)', 'once'))
                    nameScore = 15;
                elseif ~isempty(regexp(colLower, '(network|hemi|hemisphere)', 'once'))
                    nameScore = 5;
                else
                    nameScore = 0;
                end
                scores(j).name = columns{j};
                scores(j).score = nameScore + 5 * textFrac;
            end
            [~,ord] = sort([scores.score], 'descend');
            scores = scores(ord);
        end

        function vals = columnNumeric(c)
            c = NMDataIOAtlasDescriptorTools.asCellstr(c);
            vals = nan(numel(c),1);
            for i = 1:numel(c)
                vals(i) = str2double(strtrim(c{i}));
            end
        end

        function rows = previewDescriptorRows(data, columns, n)
            if nargin < 3, n = 8; end
            n = min(n, size(data,1));
            rows = cell(n,1);
            for i = 1:n
                row = struct();
                for j = 1:numel(columns)
                    row.(columns{j}) = data{i,j};
                end
                rows{i} = row;
            end
        end

        function [summary, namesByOrder] = matchDescriptorToAtlas(data, columns, idColumn, nameColumn, atlasIDs)
            atlasIDs = double(atlasIDs(:));
            namesByOrder = cell(numel(atlasIDs),1);
            for i = 1:numel(atlasIDs), namesByOrder{i} = sprintf('ROI_%g', atlasIDs(i)); end
            summary = struct('status','none','nAtlasIDs',double(numel(atlasIDs)),'nMatched',0, ...
                'missingAtlasIDs',atlasIDs(:)', 'unmatchedDescriptorIDs',[], 'idColumn',idColumn, 'nameColumn',nameColumn);
            if isempty(data) || isempty(atlasIDs) || isempty(idColumn) || isempty(nameColumn)
                return;
            end
            idIdx = find(strcmp(columns, idColumn), 1);
            nameIdx = find(strcmp(columns, nameColumn), 1);
            if isempty(idIdx) || isempty(nameIdx), return; end
            ids = NMDataIOAtlasDescriptorTools.columnNumeric(data(:,idIdx));
            names = NMDataIOAtlasDescriptorTools.asCellstr(data(:,nameIdx));
            [matched, loc] = ismember(atlasIDs, ids);
            for i = 1:numel(atlasIDs)
                if matched(i)
                    nm = strtrim(names{loc(i)});
                    if isempty(nm), nm = sprintf('ROI_%g', atlasIDs(i)); end
                    namesByOrder{i} = nm;
                end
            end
            summary.nMatched = double(nnz(matched));
            summary.missingAtlasIDs = atlasIDs(~matched)';
            finiteIDs = unique(ids(isfinite(ids)))';
            summary.unmatchedDescriptorIDs = setdiff(finiteIDs, atlasIDs(:)', 'stable');
            if summary.nMatched == numel(atlasIDs)
                summary.status = 'full';
            elseif summary.nMatched > 0
                summary.status = 'partial';
            else
                summary.status = 'none';
            end
        end

        function T = cellDataToTable(data, columns)
            if isempty(data) || isempty(columns)
                T = table(); return;
            end
            T = cell2table(data, 'VariableNames', columns);
            for j = 1:numel(columns)
                vals = NMDataIOAtlasDescriptorTools.columnNumeric(data(:,j));
                nonEmpty = ~cellfun(@isempty, data(:,j));
                if any(nonEmpty) && all(isfinite(vals(nonEmpty)))
                    T.(columns{j}) = vals;
                end
            end
        end


        function names = rankCoordinateColumns(columns, axisName)
            columns = NMDataIOAtlasDescriptorTools.asCellstr(columns);
            axisName = lower(strtrim(NMDataIOAtlasDescriptorTools.asChar(axisName)));
            scores = -inf(1,numel(columns));
            for i = 1:numel(columns)
                token = lower(regexprep(columns{i}, '[^a-z0-9]', ''));
                exact = {[axisName 'mni'], ['mni' axisName], [axisName 'mm'], ...
                    [axisName 'coord'], ['coord' axisName], [axisName 'coordinate'], ['coordinate' axisName], ...
                    [axisName 'centroid'], ['centroid' axisName], axisName};
                if any(strcmp(token, exact))
                    scores(i) = 100 - find(strcmp(token, exact),1);
                elseif contains(token, axisName) && (contains(token,'mni') || contains(token,'coord') || contains(token,'centroid'))
                    scores(i) = 50;
                end
            end
            keep = isfinite(scores);
            [~,ord] = sort(scores(keep), 'descend');
            idx = find(keep);
            names = columns(idx(ord));
        end

        function value = requestedOrFirst(opts, fieldName, candidates)
            value = NMDataIOAtlasDescriptorTools.asChar(NMDataIOAtlasDescriptorTools.fieldOr(opts,fieldName,''));
            if isempty(value) && ~isempty(candidates), value = candidates{1}; end
        end

        function ids = atlasIDsFromFile(atlasFile)
            ids = [];
            try
                if ~NMDataIOAtlasDescriptorTools.isFunctionAvailable('spm_vol') || ~NMDataIOAtlasDescriptorTools.isFunctionAvailable('spm_read_vols')
                    return;
                end
                [spmFiles, messages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({atlasFile}, 'atlasDescriptor.atlasFile', true);
                if NMDataIOMessageTools.hasFatal(messages), return; end
                V = spm_vol(spmFiles{1});
                if numel(V) > 1
                    ids = 1:numel(V);
                else
                    A = spm_read_vols(V);
                out.referenceDim = double(V.dim(1:3));
                out.referenceMat = double(V.mat);
                    vals = unique(A(:));
                    ids = double(vals(isfinite(vals) & vals ~= 0))';
                end
            catch ME
                ids = [];
                warning('NMDataIOAtlasDescriptorTools:AtlasIDsFromFile', ...
                    'Could not read atlas ROI IDs from %s while inspecting the ROI description file: %s', atlasFile, ME.message);
            end
        end

        function [d, stem] = stripNiftiExtension(path)
            [d, f, e] = fileparts(NMDataIOAtlasDescriptorTools.asChar(path));
            stem = f;
            if strcmpi(e,'.gz')
                [~, f2, e2] = fileparts(f);
                if strcmpi(e2,'.nii')
                    stem = f2;
                end
            elseif strcmpi(e,'.nii')
                stem = f;
            end
        end

        function tf = isFunctionAvailable(name)
            tf = exist(name, 'file') == 2 || exist(name, 'builtin') == 5;
        end

        function txt = shortNumericList(v, n)
            if nargin < 2, n = 10; end
            v = double(v(:)');
            if isempty(v), txt = 'none'; return; end
            take = v(1:min(numel(v), n));
            txt = strjoin(arrayfun(@(x)sprintf('%g', x), take, 'UniformOutput', false), ', ');
            if numel(v) > n, txt = [txt ', ...']; end
        end

        function v = numericVector(x)
            if isempty(x), v = []; return; end
            if isnumeric(x) || islogical(x)
                v = double(x(:)); return;
            end
            if iscell(x)
                if isempty(x), v = []; else, v = cellfun(@str2double, NMDataIOAtlasDescriptorTools.asCellstr(x)); end
                v = double(v(:)); return;
            end
            if isstring(x) || ischar(x)
                txt = NMDataIOAtlasDescriptorTools.asChar(x);
                nums = regexp(txt, '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match');
                v = str2double(nums(:)); return;
            end
            v = [];
        end

        function c = asCellstr(x)
            if isempty(x), c = {}; return; end
            if iscellstr(x), c = x(:); return; end %#ok<ISCLSTR>
            if isstring(x), c = cellstr(x(:)); return; end
            if ischar(x), c = cellstr(x); return; end
            if iscell(x)
                c = cell(numel(x),1);
                for i = 1:numel(x), c{i} = NMDataIOAtlasDescriptorTools.asChar(x{i}); end
                return;
            end
            if isnumeric(x) || islogical(x)
                c = arrayfun(@(v)sprintf('%g', v), x(:), 'UniformOutput', false); return;
            end
            c = cellstr(string(x(:)));
        end

        function txt = asChar(x)
            if isempty(x), txt = ''; return; end
            if ischar(x), txt = strtrim(x); return; end
            if isstring(x), txt = strtrim(char(x(1))); return; end
            if iscell(x)
                if isempty(x), txt = ''; else, txt = NMDataIOAtlasDescriptorTools.asChar(x{1}); end
                return;
            end
            if isnumeric(x) || islogical(x), txt = strtrim(num2str(x(1))); return; end
            txt = strtrim(char(string(x)));
        end

        function val = fieldOr(s, field, default)
            if nargin < 3, default = []; end
            val = default;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                val = s.(field);
            end
        end

        function txt = yesNo(tf)
            if logical(tf), txt = 'yes'; else, txt = 'no'; end
        end
    end
end

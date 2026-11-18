classdef NMImagingAtlasService
% NMImagingAtlasService
% -------------------------------------------------------------------------
% Deterministic atlas catalogue, world-coordinate alignment, label-table
% resolution, coordinate query, ROI-boundary source data, and ROI statistics
% for Results Viewer imaging. Two-argument catalogue calls consume one exact
% persisted atlas/descriptor resource. The third argument explicitly enables
% NM1.4 candidate/sidecar discovery only when the caller explicitly requests it.
%
% Direct one-based SPM coordinates are used throughout:
%   world = V.mat * [i j k 1]'
% The legacy subtract-one/add-one defect and duplicate pinfo scaling are not
% reproduced. No browser/report rendering or interactive dialogs occur here.
%
% Documentation: docs/NMImagingAtlasContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function catalogue = catalogue(primaryAtlasFile, primaryDescriptorFile, discoveryCandidates)
            % catalogue  Build an exact persisted-resource or caller-requested candidate catalogue.
            % Two arguments never discover neighboring atlas/descriptor/LUT files.
            % Supplying the third argument explicitly enables NM1.4 candidate discovery.
            % nm2-allow: function arity is the explicit boundary between exact DataIO resources and caller-requested NM1.4 discovery.
            legacyDiscovery = nargin >= 3;
            if ~legacyDiscovery || isempty(discoveryCandidates), discoveryCandidates = {}; end
            files = {};
            provenance = {};
            descriptors = {};
            primaryAtlasFile = NMImagingAtlasService.normalizeFile(primaryAtlasFile);
            primaryDescriptorFile = char(string(primaryDescriptorFile));
            if ~isempty(primaryAtlasFile)
                files{end+1} = primaryAtlasFile; %#ok<AGROW>
                if legacyDiscovery
                    provenance{end+1} = 'legacy_primary_descriptor'; %#ok<AGROW>
                else
                    provenance{end+1} = 'dataio_spatial_contract'; %#ok<AGROW>
                end
                descriptors{end+1} = primaryDescriptorFile; %#ok<AGROW>
            end
            for ii=1:numel(discoveryCandidates)
                f = NMImagingAtlasService.normalizeFile(discoveryCandidates{ii});
                if isempty(f) || any(strcmpi(files,f)), continue; end
                files{end+1} = f; %#ok<AGROW>
                provenance{end+1} = 'legacy_directory_discovery'; %#ok<AGROW>
                descriptors{end+1} = ''; %#ok<AGROW>
            end
            tmpl = struct('atlasId','','label','','file','','fileExists',false, ...
                'descriptorFile','','descriptorFileExists',false,'lutFile','', ...
                'lutFileExists',false,'lutProvenance','none','provenance','none', ...
                'enabled',false,'disabledReason','','descriptorOptions',struct('delimiter','auto','nameColumn',''), ...
                'descriptorCandidates',{{}});
            catalogue = repmat(tmpl,1,numel(files));
            for ii=1:numel(files)
                fileName = files{ii};
                [~,stem,ext] = fileparts(fileName);
                if strcmpi(ext,'.gz'), [~,stem,~] = fileparts(stem); end
                descriptor = descriptors{ii};
                lutFile = '';
                lutProvenance = 'none';
                if legacyDiscovery
                    detected = NMDataIOAtlasDescriptorTools.detectAtlasDescriptorCandidates(fileName);
                    catalogue(ii).descriptorCandidates = detected.files;
                    if isempty(descriptor) && strcmp(detected.status,'single')
                        descriptor = detected.files{1};
                    end
                    [lutFile,lutProvenance] = NMImagingAtlasService.findLegacyLUT(fileName);
                end
                catalogue(ii).atlasId = sprintf('atlas_%s', ...
                    NMImagingContractTools.stableId(fileName,descriptor,lutFile));
                catalogue(ii).label = strrep(stem,'_',' ');
                catalogue(ii).file = fileName;
                catalogue(ii).fileExists = NMDataIOImageFileTools.existsForSPM(fileName);
                catalogue(ii).descriptorFile = descriptor;
                catalogue(ii).descriptorFileExists = ~isempty(descriptor) && exist(descriptor,'file') == 2;
                catalogue(ii).lutFile = lutFile;
                catalogue(ii).lutFileExists = ~isempty(lutFile) && exist(lutFile,'file') == 2;
                catalogue(ii).lutProvenance = lutProvenance;
                catalogue(ii).provenance = provenance{ii};
                catalogue(ii).enabled = catalogue(ii).fileExists;
                if ~catalogue(ii).enabled
                    catalogue(ii).disabledReason = sprintf('Atlas image is unavailable: %s',fileName);
                end
            end
        end

        function atlas = prepare(entry, displayReference, profileEnabled)
            profileEnabled = logical(profileEnabled);
            tTotal = tic;
            if ~isstruct(entry) || ~isscalar(entry) || ~isfield(entry,'atlasId') || ~isfield(entry,'file')
                error('NMImagingAtlasService:InvalidCatalogueEntry','Atlas catalogue entry is invalid.');
            end
            if ~entry.enabled
                error('NMImagingAtlasService:UnavailableAtlas','%s',entry.disabledReason);
            end
            displayReference = NMImagingSpatialReference.fromVolume(displayReference);
            tStage = tic;
            atlasVolume = NMImagingVolumeAccess.read(entry.file,'atlas_labels_original');
            NMImagingAtlasService.profileLog(profileEnabled, ...
                '[nm-prof]     imaging atlas volume read:              %.3fs (atlas=%s dims=%s elements=%d)\n', ...
                toc(tStage),char(string(entry.atlasId)),mat2str(double(atlasVolume.dimensions)), ...
                double(numel(atlasVolume.data)));
            tStage = tic;
            [aligned,provenance] = NMImagingResampling.resample( ...
                atlasVolume,displayReference,'nearest',0,'atlas_labels_display');
            NMImagingAtlasService.profileLog(profileEnabled, ...
                '[nm-prof]     imaging atlas nearest resample:         %.3fs (atlas=%s displayDims=%s)\n', ...
                toc(tStage),char(string(entry.atlasId)),mat2str(double(aligned.dimensions)));
            values = double(aligned.data);
            values(~isfinite(values)) = 0;
            values = round(values);
            if any(values(:) < 0)
                error('NMImagingAtlasService:NegativeAtlasLabel', ...
                    'Discrete atlas labels must be nonnegative after nearest-neighbour sampling.');
            end
            tStage = tic;
            aligned = NMImagingVolumeAccess.withData(aligned,uint32(values),'atlas_labels_display');
            roiIds = unique(double(values(:)));
            roiIds = roiIds(roiIds > 0 & isfinite(roiIds));
            NMImagingAtlasService.profileLog(profileEnabled, ...
                '[nm-prof]     imaging atlas normalization/ROI IDs:    %.3fs (atlas=%s roiCount=%d)\n', ...
                toc(tStage),char(string(entry.atlasId)),double(numel(roiIds)));
            tStage = tic;
            [labels,labelMessage,labelProvenance,descriptorInfo] = NMImagingAtlasService.resolveLabels(entry,roiIds);
            NMImagingAtlasService.profileLog(profileEnabled, ...
                '[nm-prof]     imaging atlas LUT resolution:           %.3fs (atlas=%s provenance=%s)\n', ...
                toc(tStage),char(string(entry.atlasId)),labelProvenance);
            audit = NMImagingAtlasService.alignmentAudit(atlasVolume,aligned,displayReference);
            if ~audit.passed
                error('NMImagingAtlasService:AlignmentAuditFailed', ...
                    'Atlas/display alignment audit failed (%d mismatches across %d in-bounds landmarks).', ...
                    audit.mismatchCount,audit.inBoundsSampleCount);
            end
            atlas = struct( ...
                'schema','NMImagingPreparedAtlas', ...
                'schemaVersion',2, ...
                'atlasId',char(string(entry.atlasId)), ...
                'label',char(string(entry.label)), ...
                'file',char(string(entry.file)), ...
                'descriptorFile',char(string(entry.descriptorFile)), ...
                'lutFile',entry.lutFile, ...
                'provenance',char(string(entry.provenance)), ...
                'labelProvenance',labelProvenance, ...
                'data',aligned.data, ...
                'dimensions',aligned.dimensions, ...
                'gridId',aligned.gridId, ...
                'spatialReference',aligned.spatialReference, ...
                'sourceSpatialReference',atlasVolume.spatialReference, ...
                'roiIds',roiIds(:)', ...
                'roiLabels',labels, ...
                'descriptorInfo',descriptorInfo, ...
                'labelMessage',labelMessage, ...
                'alignmentAudit',audit, ...
                'resampling',provenance);
            NMImagingAtlasService.profileLog(profileEnabled, ...
                '[nm-prof]     imaging atlas prepare TOTAL:            %.3fs (atlas=%s)\n', ...
                toc(tTotal),char(string(entry.atlasId)));
        end

        function result = query(atlas, reference, voxel)
            reference = NMImagingSpatialReference.fromVolume(reference);
            voxel = double(voxel(:)');
            if numel(voxel) ~= 3 || any(~isfinite(voxel))
                error('NMImagingAtlasService:InvalidCoordinate','Voxel coordinate must be one finite three-vector.');
            end
            inside = NMImagingSpatialReference.containsVoxel(reference,voxel,0.5);
            code = 0;
            name = 'Outside atlas';
            if inside
                ijk = round(voxel);
                if all(ijk >= 1) && all(ijk <= double(atlas.dimensions))
                    code = double(atlas.data(ijk(1),ijk(2),ijk(3)));
                    if code > 0
                        name = NMImagingAtlasService.labelForCode(atlas.roiLabels,code);
                    else
                        name = 'Unlabelled';
                    end
                else
                    inside = false;
                end
            end
            result = struct('insideAtlasGrid',logical(inside),'voxel',voxel, ...
                'labelCode',code,'labelName',name);
        end

        function rows = statistics(atlas, overlayData, supportData, displayState, minPct)
            % statistics  Compute ROI coverage/value summaries in one grouped pass.
            minPct = max(0,double(minPct));
            if ~isstruct(atlas) || ~isfield(atlas,'data')
                error('NMImagingAtlasService:InvalidPreparedAtlas','Prepared atlas is required.');
            end
            labels = uint32(atlas.data);
            overlayData = double(overlayData);
            supportData = logical(supportData);
            if ~isequal(size(labels),size(overlayData),size(supportData))
                error('NMImagingAtlasService:ROIStatisticsGridMismatch', ...
                    'Atlas, overlay, and support arrays must share one display grid.');
            end
            flatLabels = double(labels(:));
            labelled = flatLabels > 0 & isfinite(flatLabels);
            if ~any(labelled)
                rows = struct('roiCode',{},'roiName',{},'totalVox',{},'supportedVox',{}, ...
                    'nPositive',{},'nNegative',{},'pctPositive',{},'pctNegative',{}, ...
                    'pctSuprathreshold',{},'meanValue',{},'stdValue',{},'minValue',{},'maxValue',{});
                return;
            end
            labelledCodes = flatLabels(labelled);
            [ids,~,groups] = unique(labelledCodes,'sorted');
            nGroups = numel(ids);
            total = accumarray(groups,1,[nGroups 1],@sum,0);
            labelledValues = overlayData(labelled);
            labelledSupport = supportData(labelled);
            valid = labelledSupport & isfinite(labelledValues);
            validGroups = groups(valid);
            validValues = labelledValues(valid);
            supported = accumarray(validGroups,1,[nGroups 1],@sum,0);
            sums = accumarray(validGroups,validValues,[nGroups 1],@sum,0);
            sumSquares = accumarray(validGroups,validValues.^2,[nGroups 1],@sum,0);
            minima = accumarray(validGroups,validValues,[nGroups 1],@min,NaN);
            maxima = accumarray(validGroups,validValues,[nGroups 1],@max,NaN);

            if ~isstruct(displayState) || ~isscalar(displayState) || ~isfield(displayState,'displayContract')
                error('NMImagingAtlasService:MissingDisplayContract', ...
                    'ROI statistics require complete spatial display information. Run Preview again.');
            end
            classes = NMResultsViewerDisplaySemanticsTools.classifyArray( ...
                labelledValues,displayState.displayContract,labelledSupport);
            positive = classes > 0;
            negative = classes < 0;
            nPositive = accumarray(groups(positive),1,[nGroups 1],@sum,0);
            nNegative = accumarray(groups(negative),1,[nGroups 1],@sum,0);
            nStat = nPositive + nNegative;
            pctStat = 100*nStat./max(1,total);
            keep = nStat > 0 & pctStat >= minPct;

            tmpl = struct('roiCode',0,'roiName','','totalVox',0,'supportedVox',0, ...
                'nPositive',NaN,'nNegative',NaN,'pctPositive',NaN,'pctNegative',NaN, ...
                'pctSuprathreshold',0,'meanValue',NaN,'stdValue',NaN,'minValue',NaN,'maxValue',NaN);
            keptIndices = find(keep);
            rows = repmat(tmpl,1,numel(keptIndices));
            for rr=1:numel(keptIndices)
                ii = keptIndices(rr);
                rows(rr).roiCode = ids(ii);
                rows(rr).roiName = NMImagingAtlasService.labelForCode(atlas.roiLabels,ids(ii));
                rows(rr).totalVox = total(ii);
                rows(rr).supportedVox = supported(ii);
                rows(rr).nPositive = nPositive(ii);
                rows(rr).pctPositive = 100*nPositive(ii)/max(1,total(ii));
                rows(rr).nNegative = nNegative(ii);
                rows(rr).pctNegative = 100*nNegative(ii)/max(1,total(ii));
                rows(rr).pctSuprathreshold = pctStat(ii);
                if supported(ii) > 0
                    rows(rr).meanValue = sums(ii)/supported(ii);
                    if supported(ii) > 1
                        variance = max(0,(sumSquares(ii)-sums(ii)^2/supported(ii))/(supported(ii)-1));
                        rows(rr).stdValue = sqrt(variance);
                    end
                    rows(rr).minValue = minima(ii);
                    rows(rr).maxValue = maxima(ii);
                end
            end
            [~,order] = sort([rows.pctSuprathreshold],'descend');
            rows = rows(order);
        end

        function audit = alignmentAudit(sourceAtlasVolume, alignedAtlasVolume, displayReference)
            NMImagingVolumeAccess.validateVolume(sourceAtlasVolume);
            NMImagingVolumeAccess.validateVolume(alignedAtlasVolume);
            displayReference = NMImagingSpatialReference.fromVolume(displayReference);
            sourceReference = sourceAtlasVolume.spatialReference;
            dims = double(displayReference.dimensions);
            coords = cell(1,3);
            for aa=1:3
                coords{aa} = unique(round(linspace(1,dims(aa),5)));
            end
            [I,J,K] = ndgrid(coords{1},coords{2},coords{3});
            displayVox = [I(:) J(:) K(:)];
            world = NMImagingSpatialReference.voxelToWorld(displayReference,displayVox);
            sourceVox = NMImagingSpatialReference.worldToVoxel(sourceReference,world);
            sourceIJK = round(sourceVox);
            inside = NMImagingSpatialReference.containsVoxel(sourceReference,sourceIJK,0);
            expected = zeros(size(displayVox,1),1,'uint32');
            if any(inside)
                lin = sub2ind(double(sourceAtlasVolume.dimensions), ...
                    sourceIJK(inside,1),sourceIJK(inside,2),sourceIJK(inside,3));
                vals = double(sourceAtlasVolume.data(lin));
                vals(~isfinite(vals)) = 0;
                expected(inside) = uint32(max(0,round(vals)));
            end
            displayLin = sub2ind(double(alignedAtlasVolume.dimensions), ...
                displayVox(:,1),displayVox(:,2),displayVox(:,3));
            observed = uint32(alignedAtlasVolume.data(displayLin));
            comparable = inside;
            mismatch = comparable & expected ~= observed;
            audit = struct( ...
                'schema','NMImagingAtlasAlignmentAudit', ...
                'schemaVersion',1, ...
                'coordinateConvention','spm_one_based_direct', ...
                'sampleCount',double(numel(inside)), ...
                'inBoundsSampleCount',double(nnz(comparable)), ...
                'outOfBoundsSampleCount',double(nnz(~inside)), ...
                'matchCount',double(nnz(comparable & ~mismatch)), ...
                'mismatchCount',double(nnz(mismatch)), ...
                'passed',logical(~any(mismatch)), ...
                'sourceGridId',sourceReference.gridId, ...
                'displayGridId',displayReference.gridId);
        end
    end

    methods (Static, Access = private)
        function profileLog(enabled, varargin)
            if ~enabled, return; end
            fprintf(varargin{:});
        end

    end

    methods (Static)
        function [labels,message,provenance,descriptorInfo] = resolveLabels(entry,roiIds)
            % resolveLabels  Resolve display labels without competing with canonical ROI provenance.
            % Canonical ROI returns generated placeholders immediately; the Results Viewer then applies persisted
            % DataIO ROI names. Descriptor/LUT discovery is retained only for non-ROI/legacy display atlases.
            labels = struct();
            for ii=1:numel(roiIds)
                labels.(sprintf('roi_%.0f',roiIds(ii))) = sprintf('ROI %g',roiIds(ii));
            end
            message = 'Generated ROI labels from atlas IDs.';
            provenance = 'generated_ids';
            descriptorInfo = struct('file','','delimiter','auto','columns',{{}},'nameColumn','', ...
                'candidates',{entry.descriptorCandidates});
            if strcmp(entry.provenance,'canonical_roi_provenance')
                message = 'ROI names are taken from the validated ROI definition saved during import.';
                provenance = 'canonical_roi_provenance';
                return;
            end
            descriptor = entry.descriptorFile;
            if ~isempty(descriptor) && exist(descriptor,'file') == 2
                out = NMDataIOAtlasDescriptorTools.resolveDescriptorTable( ...
                    entry.file,descriptor,struct('roiIDs',roiIds,'delimiter',entry.descriptorOptions.delimiter, ...
                    'nameColumn',entry.descriptorOptions.nameColumn));
                descriptorInfo = struct('file',descriptor,'delimiter',out.delimiter, ...
                    'columns',{out.columns},'nameColumn',out.defaultNameColumn, ...
                    'candidates',{entry.descriptorCandidates});
                if ~out.ok && (~strcmp(entry.descriptorOptions.delimiter,'auto') || ~isempty(entry.descriptorOptions.nameColumn))
                    error('NMImagingAtlasService:InvalidROIDescriptorSelection','%s',out.message);
                end
                if ~isempty(out.orderedIDs)
                    for ii=1:numel(out.orderedIDs)
                        if ~isempty(out.orderedNames{ii})
                            labels.(sprintf('roi_%.0f',out.orderedIDs(ii))) = out.orderedNames{ii};
                        end
                    end
                    provenance = 'dataio_descriptor';
                    message = out.message;
                    return;
                end
            end
            if ~startsWith(entry.provenance,'legacy_')
                return;
            end
            lutFile = entry.lutFile;
            if ~isempty(lutFile) && exist(lutFile,'file') == 2
                parsed = NMImagingAtlasService.readLegacyLUT(lutFile);
                parsedFields = fieldnames(parsed);
                for ii=1:numel(parsedFields), labels.(parsedFields{ii}) = parsed.(parsedFields{ii}); end
                provenance = 'legacy_lut';
                message = sprintf('ROI labels resolved from legacy LUT %s.',lutFile);
            end
        end

    end

    methods (Static, Access = private)
        function [lutFile,provenance] = findLegacyLUT(atlasFile)
            % findLegacyLUT  Resolve deterministic legacy LUT sidecars.
            %
            % The exact atlas stem is authoritative. A second stem with the
            % conventional trailing _atlas suffix removed is also checked because
            % established NeuroMiner distributions use both naming schemes.
            atlasFile = NMImagingAtlasService.normalizeFile(atlasFile);
            [pn,stem,ext] = fileparts(atlasFile);
            if strcmpi(ext,'.gz'), [~,stem,~] = fileparts(stem); end
            stems = {stem};
            reduced = regexprep(stem,'_atlas$','','ignorecase');
            if ~strcmpi(reduced,stem), stems{end+1} = reduced; end %#ok<AGROW>
            suffixes = {'_LUT.txt','_lut.txt','_labels.txt','.labels.txt','.txt','.tsv','.csv','.nii.txt'};
            candidates = cell(1,numel(stems)*numel(suffixes));
            kk = 0;
            for ss=1:numel(stems)
                for uu=1:numel(suffixes)
                    kk = kk + 1;
                    candidates{kk} = fullfile(pn,[stems{ss} suffixes{uu}]);
                end
            end
            lutFile = ''; provenance = 'none';
            for ii=1:numel(candidates)
                if exist(candidates{ii},'file') == 2
                    lutFile = candidates{ii};
                    provenance = 'legacy_sidecar_discovery';
                    return;
                end
            end
            % Windows paths are case-insensitive, while Linux test/build hosts are
            % not. Resolve a unique case-insensitive filename match without broad
            % heuristic scanning or interactive column selection.
            if exist(pn,'dir') == 7
                listing = [dir(fullfile(pn,'*.txt')); dir(fullfile(pn,'*.tsv')); dir(fullfile(pn,'*.csv'))];
                expected = lower(cellfun(@(x) NMImagingAtlasService.baseName(x),candidates,'UniformOutput',false));
                matches = false(1,numel(listing));
                for ii=1:numel(listing), matches(ii) = any(strcmp(lower(listing(ii).name),expected)); end
                hit = find(matches);
                if numel(hit) == 1
                    lutFile = fullfile(listing(hit).folder,listing(hit).name);
                    provenance = 'legacy_sidecar_discovery_case_insensitive';
                end
            end
        end

        function labels = readLegacyLUT(lutFile)
            fid = fopen(lutFile,'r');
            if fid < 0
                error('NMImagingAtlasService:LUTOpenFailed','Cannot open atlas LUT: %s',lutFile);
            end
            cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
            labels = struct();
            lineNumber = 0;
            while true
                line = fgetl(fid);
                if ~ischar(line), break; end
                lineNumber = lineNumber + 1;
                line = strtrim(line);
                if isempty(line) || startsWith(line,'#') || startsWith(line,'%') || startsWith(line,'//'), continue; end
                tokens = NMImagingAtlasService.tokenizeLUTLine(line);
                if numel(tokens) < 2, continue; end
                numericValues = cellfun(@str2double,tokens);
                codeIndex = find(isfinite(numericValues) & numericValues == round(numericValues),1,'first');
                if isempty(codeIndex), continue; end
                code = numericValues(codeIndex);
                if code < 0, continue; end
                nonNumeric = ~isfinite(numericValues);
                nonNumeric(1:max(0,codeIndex-1)) = false;
                segments = NMImagingAtlasService.trueSegments(nonNumeric);
                if isempty(segments), continue; end
                lengths = segments(:,2)-segments(:,1)+1;
                [~,best] = max(lengths);
                nameTokens = tokens(segments(best,1):segments(best,2));
                name = strtrim(strjoin(nameTokens,' '));
                name = regexprep(name,'^["'']|["'']$','');
                if isempty(name), continue; end
                key = sprintf('roi_%.0f',code);
                if ~isfield(labels,key), labels.(key) = name; end
            end
            if isempty(fieldnames(labels))
                error('NMImagingAtlasService:LUTParseFailed', ...
                    'No ROI code/name pairs could be parsed from LUT %s.',lutFile);
            end
        end

        function tokens = tokenizeLUTLine(line)
            if contains(line,sprintf('\t'))
                tokens = strsplit(line,sprintf('\t'));
            elseif contains(line,',')
                tokens = strsplit(line,',');
            elseif contains(line,';')
                tokens = strsplit(line,';');
            else
                tokens = regexp(line,'\s+','split');
            end
            tokens = cellfun(@strtrim,tokens,'UniformOutput',false);
            tokens = tokens(~cellfun(@isempty,tokens));
        end

        function segments = trueSegments(mask)
            mask = logical(mask(:)');
            starts = find(mask & [true ~mask(1:end-1)]);
            ends = find(mask & [~mask(2:end) true]);
            segments = [starts(:) ends(:)];
        end

        function name = labelForCode(labels,code)
            key = sprintf('roi_%.0f',double(code));
            if isstruct(labels) && isfield(labels,key)
                name = char(string(labels.(key)));
            else
                name = sprintf('ROI %g',double(code));
            end
        end

        function name = baseName(fileName)
            [~,name,ext] = fileparts(char(string(fileName)));
            name = [name ext];
        end

        function fileName = normalizeFile(value)
            fileName = regexprep(char(string(value)),',\d+$','');
        end
    end
end

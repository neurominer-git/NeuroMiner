classdef NMImagingTemplateService
% NMImagingTemplateService
% -------------------------------------------------------------------------
% Deterministic structural-template discovery for the imaging viewer.
% The current descriptor/reference is authoritative and is followed by
% legacy *_struct.nii / *_struct.nii.gz references from the same directory.
% No UI dialogs, rendering, or NM mutation are permitted here.
%
% Documentation: docs/NMImagingTemplateContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function fileName = structuralReferenceFile(NM)
            % structuralReferenceFile  Resolve the shared NM structural-template root.
            fileName = '';
            candidate = regexprep(NM.defs.atlas_path,',\d+$','');
            if exist(candidate,'dir') ~= 7
                if ~isempty(regexp(candidate,'[/\\]atlas$','once'))
                    candidate = fullfile(fileparts(which('nk_Initialize')),'atlas');
                else
                    fileName = candidate;
                    return;
                end
            end
            patterns = {'*_struct.nii','*_struct.nii.gz','*_struct.img','*_struct.hdr'};
            matches = {};
            for pp = 1:numel(patterns)
                listing = dir(fullfile(candidate,patterns{pp}));
                for ii = 1:numel(listing)
                    matches{end+1} = fullfile(candidate,listing(ii).name); %#ok<AGROW>
                end
            end
            if ~isempty(matches)
                matches = sort(matches);
                fileName = matches{1};
            end
        end

        function catalogue = catalogue(primaryFile, legacyDirectory, extraCandidates)
            if nargin < 1, primaryFile = ''; end
            if nargin < 2, legacyDirectory = ''; end
            if nargin < 3 || isempty(extraCandidates), extraCandidates = {}; end
            primaryFile = NMImagingTemplateService.normalizeFile(primaryFile);
            legacyDirectory = char(string(legacyDirectory));
            candidates = {};
            provenance = {};
            isDefault = false(1,0);
            if ~isempty(primaryFile)
                candidates{end+1} = primaryFile; %#ok<AGROW>
                provenance{end+1} = 'authoritative_structural_reference'; %#ok<AGROW>
                isDefault(end+1) = true; %#ok<AGROW>
            end
            if isempty(legacyDirectory) && ~isempty(primaryFile)
                legacyDirectory = fileparts(primaryFile);
            end
            if ~isempty(legacyDirectory) && exist(legacyDirectory,'dir') == 7
                patterns = {'*_struct.nii','*_struct.nii.gz'};
                for pp=1:numel(patterns)
                    listing = dir(fullfile(legacyDirectory,patterns{pp}));
                    [~,order] = sort(lower({listing.name}));
                    listing = listing(order);
                    for ii=1:numel(listing)
                        candidates{end+1} = fullfile(listing(ii).folder,listing(ii).name); %#ok<AGROW>
                        provenance{end+1} = 'legacy_structural_directory_discovery'; %#ok<AGROW>
                        isDefault(end+1) = false; %#ok<AGROW>
                    end
                end
            end
            for ii=1:numel(extraCandidates)
                fileName = NMImagingTemplateService.normalizeFile(extraCandidates{ii});
                if isempty(fileName), continue; end
                candidates{end+1} = fileName; %#ok<AGROW>
                provenance{end+1} = 'explicit_candidate'; %#ok<AGROW>
                isDefault(end+1) = false; %#ok<AGROW>
            end
            [candidates,keep] = NMImagingTemplateService.uniqueFiles(candidates);
            provenance = provenance(keep);
            isDefault = isDefault(keep);
            tmpl = struct('templateId','','label','','file','','fileExists',false, ...
                'provenance','none','isDefault',false,'enabled',false,'disabledReason','');
            catalogue = repmat(tmpl,1,numel(candidates));
            for ii=1:numel(candidates)
                fileName = candidates{ii};
                [~,stem,ext] = fileparts(fileName);
                if strcmpi(ext,'.gz'), [~,stem,~] = fileparts(stem); end
                catalogue(ii).templateId = sprintf('template_%s', ...
                    NMImagingContractTools.stableId(fileName));
                catalogue(ii).label = strrep(stem,'_',' ');
                catalogue(ii).file = fileName;
                catalogue(ii).fileExists = NMDataIOImageFileTools.existsForSPM(fileName);
                catalogue(ii).provenance = provenance{ii};
                catalogue(ii).isDefault = logical(isDefault(ii));
                catalogue(ii).enabled = catalogue(ii).fileExists;
                if ~catalogue(ii).enabled
                    catalogue(ii).disabledReason = sprintf('Structural template is unavailable: %s',fileName);
                end
            end
            if ~isempty(catalogue) && ~any([catalogue.isDefault])
                firstEnabled = find([catalogue.enabled],1,'first');
                if ~isempty(firstEnabled), catalogue(firstEnabled).isDefault = true; end
            end
        end

        function [entry,index] = select(catalogue, requestedId)
            entry = struct(); index = 0;
            if isempty(catalogue), return; end
            requestedId = char(string(requestedId));
            if ~isempty(requestedId) && ~strcmpi(requestedId,'default')
                index = find(strcmp({catalogue.templateId},requestedId) & [catalogue.enabled],1,'first');
            end
            if isempty(index) || index == 0
                index = find([catalogue.isDefault] & [catalogue.enabled],1,'first');
            end
            if isempty(index) || index == 0
                index = find([catalogue.enabled],1,'first');
            end
            if isempty(index), index = 0; return; end
            entry = catalogue(index);
        end
    end

    methods (Static, Access = private)
        function fileName = normalizeFile(value)
            fileName = regexprep(char(string(value)),',\d+$','');
        end

        function [files,keep] = uniqueFiles(files)
            if isempty(files), keep = []; return; end
            keys = cellfun(@(x)lower(strrep(char(string(x)),'/','\')),files,'UniformOutput',false);
            [~,keep] = unique(keys,'stable');
            files = files(keep);
        end
    end
end
